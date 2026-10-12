from datetime import date, datetime, timedelta
from decimal import Decimal

from flask import redirect, render_template, request, session, url_for
from sqlalchemy import func

from ..extensions import db
from ..models import (
    AccountingJournalEntry,
    AccountingJournalLine,
    AccountingVoucher,
    Admin,
    Currency,
    Customer,
    CustomerLedgerOperation,
    LedgerAccount,
    Order,
)
from ..services.accounting import (
    ACCOUNT_TYPES,
    create_posted_entry,
    create_voucher,
    ensure_accounting_setup,
    ledger_balance,
    post_unposted_sales,
    reverse_entry,
    create_customer_operation,
    reverse_customer_operation,
    account_is_in_cash_tree,
)


def _ready():
    # The security hook prepares chart/permissions before access checks and marks
    # this request as ready. The fallback keeps tests/direct view invocation safe.
    from flask import g
    if getattr(g, "accounting_ready", False):
        return
    ensure_accounting_setup(db.session, backfill_parties=True)
    db.session.commit()
    g.accounting_ready = True


def _actor_id():
    return session.get("admin_id")


def _parse_date(value, default):
    try:
        return datetime.strptime((value or "").strip(), "%Y-%m-%d").date()
    except (ValueError, TypeError):
        return default


def _currency_options():
    currencies = Currency.query.filter_by(is_active=True).order_by(Currency.code).all()
    rows = [{"code": row.code, "name": row.name_ar or row.code} for row in currencies]
    if not any(row["code"] == "YER" for row in rows):
        rows.insert(0, {"code": "YER", "name": "ريال يمني"})
    return rows


def _postable_accounts():
    return (
        LedgerAccount.query
        .filter_by(is_active=True, is_group=False, allow_manual_posting=True)
        .order_by(LedgerAccount.code)
        .all()
    )


def _account_tree(accounts, parent_id=None, depth=0, ancestors=None):
    by_parent = {}
    for account in accounts:
        by_parent.setdefault(account.parent_id, []).append(account)
    for rows in by_parent.values():
        rows.sort(key=lambda row: row.code or "")
    ancestors = set(ancestors or ())
    result = []
    for account in by_parent.get(parent_id, []):
        if account.id in ancestors:
            continue
        branch = _account_tree(
            accounts,
            parent_id=account.id,
            depth=depth + 1,
            ancestors=ancestors | {account.id},
        )
        result.append({"account": account, "depth": depth, "children": branch})
    if parent_id is None:
        included = set()
        def mark(nodes):
            for node in nodes:
                included.add(node["account"].id)
                mark(node["children"])
        mark(result)
        # Preserve malformed/orphaned branches in the tree instead of hiding data.
        for account in accounts:
            if account.id not in included:
                branch = _account_tree(
                    accounts,
                    parent_id=account.id,
                    depth=1,
                    ancestors={account.id},
                )
                result.append({"account": account, "depth": 0, "children": branch})
                included.add(account.id)
    return result


def _flatten_account_tree(tree):
    result = []
    for node in tree:
        result.append((node["account"], node["depth"]))
        result.extend(_flatten_account_tree(node["children"]))
    return result


def _find_tree_node(tree, account_id):
    for node in tree:
        if node["account"].id == account_id:
            return node
        found = _find_tree_node(node["children"], account_id)
        if found:
            return found
    return None


def _cash_tree_data(tree):
    root = LedgerAccount.query.filter_by(system_key="cash_root").one_or_none()
    root_node = _find_tree_node(tree, root.id) if root else None
    cash_tree = [root_node] if root_node else []
    cash_ids = set()
    for account, _depth in _flatten_account_tree(cash_tree):
        if not account.is_group and account.is_active and account.allow_manual_posting:
            cash_ids.add(account.id)
    postable_ids = {
        account.id
        for account in _postable_accounts()
    }
    counterpart_ids = postable_ids - cash_ids
    return cash_tree, sorted(cash_ids), sorted(counterpart_ids), sorted(postable_ids)


def _account_balance_tree(accounts, tree):
    raw = {}
    rows = (
        db.session.query(
            AccountingJournalLine.account_id,
            AccountingJournalEntry.currency_code,
            func.coalesce(func.sum(AccountingJournalLine.debit), 0),
            func.coalesce(func.sum(AccountingJournalLine.credit), 0),
        )
        .join(AccountingJournalEntry, AccountingJournalEntry.id == AccountingJournalLine.entry_id)
        .filter(AccountingJournalEntry.status == "posted")
        .group_by(AccountingJournalLine.account_id, AccountingJournalEntry.currency_code)
        .all()
    )
    for account_id, currency, debit, credit in rows:
        raw.setdefault(account_id, {})[currency] = Decimal(str(debit or 0)) - Decimal(str(credit or 0))

    balances = {}
    def roll(node):
        account = node["account"]
        own = dict(raw.get(account.id, {}))
        for child in node["children"]:
            for currency, amount in roll(child).items():
                own[currency] = own.get(currency, Decimal("0")) + amount
        balances[account.id] = [
            {"currency": currency, "balance": amount}
            for currency, amount in sorted(own.items())
        ]
        return own
    for node in tree:
        roll(node)
    return balances


def _account_picker_context():
    accounts = LedgerAccount.query.order_by(LedgerAccount.code).all()
    tree = _account_tree(accounts)
    cash_tree, cash_ids, counterpart_ids, postable_ids = _cash_tree_data(tree)
    labels = {account.id: f"{account.code} · {account.name}" for account in accounts}
    return {
        "account_tree": tree,
        "cash_tree": cash_tree,
        "cashbox_ids": cash_ids,
        "counterpart_ids": counterpart_ids,
        "postable_ids": postable_ids,
        "account_label_map": labels,
    }



def _account_period_rows(start, end, currency=None):
    """Build a currency-separated period trial balance without per-account queries."""
    def aggregate(upper=None, lower=None):
        q = (
            db.session.query(
                AccountingJournalLine.account_id,
                AccountingJournalEntry.currency_code,
                func.coalesce(func.sum(AccountingJournalLine.debit), 0).label("debit"),
                func.coalesce(func.sum(AccountingJournalLine.credit), 0).label("credit"),
            )
            .join(AccountingJournalEntry, AccountingJournalEntry.id == AccountingJournalLine.entry_id)
            .join(LedgerAccount, LedgerAccount.id == AccountingJournalLine.account_id)
            .filter(AccountingJournalEntry.status == "posted")
        )
        if upper:
            q = q.filter(AccountingJournalEntry.entry_date <= upper)
        if lower:
            q = q.filter(AccountingJournalEntry.entry_date >= lower)
        if currency:
            q = q.filter(AccountingJournalEntry.currency_code == currency)
        return {
            (row.account_id, row.currency_code): (
                Decimal(str(row.debit or 0)),
                Decimal(str(row.credit or 0)),
            )
            for row in q.group_by(
                AccountingJournalLine.account_id,
                AccountingJournalEntry.currency_code,
            ).all()
        }

    period = aggregate(upper=end, lower=start)
    opening = aggregate(upper=start - timedelta(days=1))
    closing = aggregate(upper=end)
    currency_keys = set(period) | set(closing)
    if not currency_keys:
        return []

    accounts = {
        account.id: account
        for account in LedgerAccount.query.filter(LedgerAccount.is_group.is_(False)).all()
    }
    rows = []
    for account_id, currency_code in currency_keys:
        account = accounts.get(account_id)
        if not account:
            continue
        debit, credit = period.get((account_id, currency_code), (Decimal("0"), Decimal("0")))
        open_debit, open_credit = opening.get((account_id, currency_code), (Decimal("0"), Decimal("0")))
        close_debit, close_credit = closing.get((account_id, currency_code), (Decimal("0"), Decimal("0")))
        rows.append({
            "id": account.id,
            "code": account.code,
            "name": account.name,
            "account_type": account.account_type,
            "currency_code": currency_code,
            "opening": open_debit - open_credit,
            "debit": debit,
            "credit": credit,
            "closing": close_debit - close_credit,
        })
    rows.sort(key=lambda row: (row["currency_code"], row["code"]))
    return rows

def register_accounting_views(admin_bp):
    @admin_bp.get("/accounting")
    def accounting_home():
        _ready()
        account_count = LedgerAccount.query.filter_by(is_active=True).count()
        group_count = LedgerAccount.query.filter_by(is_active=True, is_group=True).count()
        detail_count = LedgerAccount.query.filter_by(is_active=True, is_group=False).count()
        journal_count = AccountingJournalEntry.query.filter_by(status="posted").count()
        voucher_count = AccountingVoucher.query.filter_by(status="posted").count()
        with db.session.no_autoflush:
            posted_order_ids = (
                db.session.query(AccountingJournalEntry.source_id)
                .filter(
                    AccountingJournalEntry.source_type == "order_sale",
                    AccountingJournalEntry.source_id.isnot(None),
                )
                .subquery()
            )
            pending_sales = (
                Order.query
                .filter(Order.status.notin_(("cancelled", "canceled", "void")))
                .filter(~Order.id.in_(db.session.query(posted_order_ids.c.source_id)))
                .count()
            )
        latest_entries = AccountingJournalEntry.query.order_by(
            AccountingJournalEntry.entry_date.desc(), AccountingJournalEntry.id.desc()
        ).limit(8).all()
        latest_vouchers = AccountingVoucher.query.order_by(
            AccountingVoucher.voucher_date.desc(), AccountingVoucher.id.desc()
        ).limit(6).all()
        return render_template(
            "admin/accounting/dashboard.html",
            title="النظام المحاسبي",
            account_count=account_count,
            group_count=group_count,
            detail_count=detail_count,
            journal_count=journal_count,
            voucher_count=voucher_count,
            pending_sales=pending_sales,
            latest_entries=latest_entries,
            latest_vouchers=latest_vouchers,
            success=request.args.get("success"),
            error=request.args.get("error"),
            **_context(),
        )

    @admin_bp.route("/accounting/accounts", methods=["GET", "POST"])
    def accounting_accounts():
        _ready()
        error = None
        success = request.args.get("success")
        if request.method == "POST":
            action = (request.form.get("action") or "create").strip()
            try:
                if action == "create":
                    parent = db.session.get(LedgerAccount, request.form.get("parent_id", type=int))
                    name = (request.form.get("name") or "").strip()
                    if not name:
                        raise ValueError("اسم الحساب مطلوب.")
                    if parent is None or not parent.is_group or not parent.is_active:
                        raise ValueError("اختر حسابًا أبًا تجميعيًا نشطًا.")
                    code = (request.form.get("code") or "").strip()
                    if not code:
                        children_count = LedgerAccount.query.filter_by(parent_id=parent.id).count()
                        code = f"{parent.code}{children_count + 1:02d}"
                    if LedgerAccount.query.filter_by(code=code).first():
                        raise ValueError("رمز الحساب مستخدم مسبقًا.")
                    is_group = request.form.get("is_group") == "on"
                    account = LedgerAccount(
                        code=code,
                        name=name,
                        account_type=parent.account_type,
                        parent_id=parent.id,
                        is_group=is_group,
                        allow_manual_posting=not is_group,
                        description=(request.form.get("description") or "").strip() or None,
                        is_active=True,
                    )
                    db.session.add(account)
                    db.session.commit()
                    return redirect(url_for("admin.accounting_accounts", success="تم إنشاء الحساب."))
                account = db.session.get(LedgerAccount, request.form.get("id", type=int))
                if account is None:
                    raise ValueError("الحساب غير موجود.")
                if account.system_key:
                    raise ValueError("هذا حساب نظامي محمي حتى لا تنقطع ارتباطاته المحاسبية.")
                if action == "update":
                    name = (request.form.get("name") or "").strip()
                    parent = db.session.get(LedgerAccount, request.form.get("parent_id", type=int))
                    if not name or parent is None or not parent.is_group or not parent.is_active:
                        raise ValueError("اسم الحساب والحساب الأب التجميعي مطلوبان.")
                    if parent.id == account.id:
                        raise ValueError("لا يمكن جعل الحساب أبًا لنفسه.")
                    cursor = parent
                    seen = {account.id}
                    while cursor:
                        if cursor.id in seen:
                            raise ValueError("هذا الترتيب سيُنشئ حلقة في شجرة الحسابات.")
                        seen.add(cursor.id)
                        cursor = db.session.get(LedgerAccount, cursor.parent_id) if cursor.parent_id else None
                    account.name = name
                    account.parent_id = parent.id
                    account.account_type = parent.account_type
                    account.description = (request.form.get("description") or "").strip() or None
                    desired_active = request.form.get("is_active") == "on"
                    if account.is_group and not desired_active and any(child.is_active for child in account.children):
                        raise ValueError("لا يمكن تعطيل حساب تجميعي ما دامت له حسابات فرعية نشطة.")
                    account.is_active = desired_active
                    account.allow_manual_posting = (not account.is_group) and request.form.get("allow_manual_posting") == "on"
                elif action == "toggle":
                    if account.is_group and account.children:
                        raise ValueError("لا يمكن تعطيل حساب تجميعي يحتوي فروعًا؛ عطّل الحسابات الفرعية أولًا.")
                    account.is_active = not account.is_active
                elif action == "delete":
                    if account.children:
                        raise ValueError("لا يمكن حذف حساب له فروع. احذف الفروع غير المستخدمة أولًا.")
                    if db.session.query(AccountingJournalLine.id).filter_by(account_id=account.id).first():
                        raise ValueError("لا يمكن حذف حساب استُخدم في القيود. عطّله بدلًا من ذلك.")
                    if Customer.query.filter_by(ledger_account_id=account.id).first():
                        raise ValueError("هذا حساب مرتبط بعميل ولا يمكن حذفه.")
                    if CustomerLedgerOperation.query.filter(
                        (CustomerLedgerOperation.cash_account_id == account.id) |
                        (CustomerLedgerOperation.contra_account_id == account.id)
                    ).first():
                        raise ValueError("الحساب مرتبط بحركات عملاء ولا يمكن حذفه.")
                    db.session.delete(account)
                    success = "تم حذف الحساب لأنه غير مستخدم في أي حركة."
                else:
                    raise ValueError("إجراء الحساب غير معروف.")
                db.session.commit()
                return redirect(url_for("admin.accounting_accounts", success="تم حفظ التغييرات."))
            except (ValueError, TypeError) as exc:
                db.session.rollback()
                error = str(exc)

        all_accounts = LedgerAccount.query.order_by(LedgerAccount.code).all()
        tree = _account_tree(all_accounts)
        picker_context = _account_picker_context()
        balances = _account_balance_tree(all_accounts, tree)
        return render_template(
            "admin/accounting/accounts.html",
            title="شجرة الحسابات",
            tree=tree,
            accounts=all_accounts,
            parent_options=[row for row in all_accounts if row.is_group and row.is_active],
            balances=balances,
            stats={
                "count": len(all_accounts),
                "groups": sum(1 for row in all_accounts if row.is_group),
                "leaves": sum(1 for row in all_accounts if not row.is_group),
                "journal_count": AccountingJournalEntry.query.filter_by(status="posted").count(),
                "voucher_count": AccountingVoucher.query.filter_by(status="posted").count(),
                "customer_count": Customer.query.filter(Customer.ledger_account_id.isnot(None)).count(),
            },
            account_type_labels=ACCOUNT_TYPES,
            error=error,
            success=success,
            **picker_context,
            **_context(),
        )

    @admin_bp.get("/accounting/accounts/<int:account_id>")
    def accounting_account_detail(account_id):
        _ready()
        account = db.session.get(LedgerAccount, account_id)
        if account is None:
            return render_template(
                "admin/accounting/account_detail.html",
                title="الحساب غير موجود",
                account=None,
                error="الحساب المطلوب غير موجود.",
                **_context(),
            ), 404
        start = _parse_date(request.args.get("start"), date.today().replace(day=1))
        end = _parse_date(request.args.get("end"), date.today())
        currency = (request.args.get("currency") or "YER").strip().upper()
        opening = ledger_balance(account.id, currency_code=currency, end_date=start - timedelta(days=1))
        movement_query = (
            db.session.query(AccountingJournalLine, AccountingJournalEntry)
            .join(AccountingJournalEntry, AccountingJournalEntry.id == AccountingJournalLine.entry_id)
            .filter(
                AccountingJournalLine.account_id == account.id,
                AccountingJournalEntry.status == "posted",
                AccountingJournalEntry.currency_code == currency,
                AccountingJournalEntry.entry_date >= start,
                AccountingJournalEntry.entry_date <= end,
            )
            .order_by(AccountingJournalEntry.entry_date, AccountingJournalEntry.id, AccountingJournalLine.id)
        )
        movements = []
        balance = opening
        for line, entry in movement_query.all():
            balance += Decimal(str(line.debit or 0)) - Decimal(str(line.credit or 0))
            movements.append({"line": line, "entry": entry, "balance": balance})
        children = LedgerAccount.query.filter_by(parent_id=account.id).order_by(LedgerAccount.code).all()
        children_summaries = [
            {"account": child, "balance": ledger_balance(child.id, currency_code=currency)}
            for child in children
        ]
        return render_template(
            "admin/accounting/account_detail.html",
            title=f"{account.code} · {account.name}",
            account=account,
            start=start,
            end=end,
            currency=currency,
            currencies=_currency_options(),
            opening=opening,
            closing=balance,
            movements=movements,
            children_summaries=children_summaries,
            parent_tree=_flatten_account_tree(_account_tree(LedgerAccount.query.order_by(LedgerAccount.code).all())),
            account_type_labels=ACCOUNT_TYPES,
            error=None,
            **_context(),
        )

    @admin_bp.route("/accounting/journal", methods=["GET", "POST"])
    def accounting_journal():
        _ready()
        error = None
        success = None
        if request.method == "POST":
            try:
                description = (request.form.get("description") or "").strip()
                entry_date = _parse_date(request.form.get("entry_date"), date.today())
                currency_code = (request.form.get("currency_code") or "SAR").strip().upper()
                account_ids = request.form.getlist("account_id")
                debits = request.form.getlist("debit")
                credits = request.form.getlist("credit")
                descriptions = request.form.getlist("line_description")
                refs = request.form.getlist("reference")
                lines = []
                for index, account_id in enumerate(account_ids):
                    debit = debits[index] if index < len(debits) else ""
                    credit = credits[index] if index < len(credits) else ""
                    if not account_id and not debit and not credit:
                        continue
                    if not account_id:
                        raise ValueError(f"اختر الحساب في السطر {index + 1}.")
                    lines.append({
                        "account_id": int(account_id),
                        "debit": debit or 0,
                        "credit": credit or 0,
                        "description": descriptions[index] if index < len(descriptions) else "",
                        "reference": refs[index] if index < len(refs) else "",
                    })
                entry = create_posted_entry(
                    description=description,
                    entry_date=entry_date,
                    currency_code=currency_code,
                    created_by_admin_id=_actor_id(),
                    lines=lines,
                    source_type="manual",
                    prefix="JE",
                )
                db.session.commit()
                return redirect(url_for("admin.accounting_journal", success=f"تم ترحيل القيد {entry.number}."))
            except (ValueError, TypeError) as exc:
                db.session.rollback()
                error = str(exc)

        query = (request.args.get("q") or "").strip()
        source = (request.args.get("source") or "").strip()
        currency = (request.args.get("currency") or "").strip().upper()
        start = _parse_date(request.args.get("start"), date.today().replace(day=1))
        end = _parse_date(request.args.get("end"), date.today())
        statement = AccountingJournalEntry.query
        if query:
            like = f"%{query}%"
            statement = statement.filter(
                AccountingJournalEntry.number.ilike(like)
                | AccountingJournalEntry.description.ilike(like)
            )
        if source:
            statement = statement.filter(AccountingJournalEntry.source_type == source)
        if currency:
            statement = statement.filter(AccountingJournalEntry.currency_code == currency)
        statement = statement.filter(
            AccountingJournalEntry.entry_date >= start,
            AccountingJournalEntry.entry_date <= end,
        ).order_by(AccountingJournalEntry.entry_date.desc(), AccountingJournalEntry.id.desc())
        entries = statement.limit(300).all()
        for entry in entries:
            entry._debit_total, entry._credit_total = entry.totals()
        return render_template(
            "admin/accounting/journal.html",
            title="القيود اليومية",
            entries=entries,
            accounts=_postable_accounts(),
            currencies=_currency_options(),
            **_account_picker_context(),
            query=query,
            source=source,
            currency=currency,
            start=start,
            end=end,
            today=date.today(),
            error=error,
            success=request.args.get("success") or success,
            **_context(),
        )

    @admin_bp.route("/accounting/vouchers", methods=["GET", "POST"])
    def accounting_vouchers():
        _ready()
        error = None
        success = request.args.get("success")
        if request.method == "POST":
            edit_id = request.form.get("edit_id", type=int)
            old_voucher = db.session.get(AccountingVoucher, edit_id) if edit_id else None
            try:
                voucher_type = (request.form.get("voucher_type") or "receipt").strip()
                counterpart_id = request.form.get("account_id", type=int)
                cash_id = request.form.get("cash_account_id", type=int)
                if voucher_type not in {"receipt", "payment"}:
                    raise ValueError("اختر سند قبض أو سند صرف.")
                if not counterpart_id or not cash_id:
                    raise ValueError("اختر الحساب والصندوق من شجرة الحسابات.")
                if not account_is_in_cash_tree(cash_id, db.session):
                    raise ValueError("حساب المصدر يجب أن يكون من شجرة الصناديق.")
                if counterpart_id == cash_id:
                    raise ValueError("لا يمكن اختيار الحساب نفسه طرفًا وصندوقًا.")
                description = (request.form.get("description") or "").strip()
                if not description:
                    raise ValueError("البيان مطلوب.")
                voucher_date = _parse_date(request.form.get("voucher_date"), date.today())
                if old_voucher:
                    if old_voucher.status != "posted":
                        raise ValueError("لا يمكن تعديل سند ملغى.")
                    old_entry = db.session.get(AccountingJournalEntry, old_voucher.journal_entry_id)
                    reverse_entry(
                        old_entry,
                        admin_id=_actor_id(),
                        reason=f"تعديل السند {old_voucher.number}",
                    )
                    old_voucher.status = "void"
                if voucher_type == "receipt":
                    from_id, to_id = counterpart_id, cash_id
                else:
                    from_id, to_id = cash_id, counterpart_id
                voucher = create_voucher(
                    voucher_type=voucher_type,
                    voucher_date=voucher_date,
                    amount=request.form.get("amount"),
                    currency_code="YER",
                    from_account_id=from_id,
                    to_account_id=to_id,
                    beneficiary=None,
                    description=description,
                    admin_id=_actor_id(),
                )
                db.session.commit()
                message = f"تم إصدار السند {voucher.number} بالريال اليمني."
                if old_voucher:
                    message = f"تم تعديل السند بعكس السابق وإصدار سند جديد {voucher.number}."
                return redirect(url_for("admin.accounting_vouchers", success=message))
            except (ValueError, TypeError, LookupError) as exc:
                db.session.rollback()
                error = str(exc)

        vouchers = AccountingVoucher.query.order_by(
            AccountingVoucher.voucher_date.desc(), AccountingVoucher.id.desc()
        ).limit(500).all()
        picker_context = _account_picker_context()
        editing_id = request.args.get("edit", type=int)
        editing_voucher = db.session.get(AccountingVoucher, editing_id) if editing_id else None
        if editing_voucher and editing_voucher.status != "posted":
            error = error or "لا يمكن تعديل سند ملغى."
            editing_voucher = None
        selected_type = (
            editing_voucher.voucher_type
            if editing_voucher and editing_voucher.voucher_type in {"receipt", "payment"}
            else request.args.get("new", "receipt")
            if request.args.get("new") in {"receipt", "payment"}
            else "receipt"
        )
        selected_counterpart_id = None
        selected_cash_id = None
        if editing_voucher:
            if editing_voucher.voucher_type == "receipt":
                selected_counterpart_id = editing_voucher.from_account_id
                selected_cash_id = editing_voucher.to_account_id
            elif editing_voucher.voucher_type == "payment":
                selected_counterpart_id = editing_voucher.to_account_id
                selected_cash_id = editing_voucher.from_account_id
        return render_template(
            "admin/accounting/vouchers.html",
            title="السندات",
            vouchers=vouchers,
            currencies=_currency_options(),
            today=date.today(),
            error=error,
            success=success,
            editing_voucher=editing_voucher,
            selected_type=selected_type,
            selected_counterpart_id=selected_counterpart_id,
            selected_cash_id=selected_cash_id,
            show_composer=bool(editing_voucher or request.args.get("new") in {"receipt", "payment"}),
            account_picker_context=picker_context,
            **picker_context,
            **_context(),
        )

    @admin_bp.get("/accounting/vouchers/<int:voucher_id>")
    def accounting_voucher_detail(voucher_id):
        _ready()
        voucher = db.session.get(AccountingVoucher, voucher_id)
        if voucher is None:
            return render_template(
                "admin/accounting/voucher_detail.html",
                title="السند غير موجود",
                voucher=None,
                error="السند المطلوب غير موجود.",
                **_context(),
            ), 404
        entry = db.session.get(AccountingJournalEntry, voucher.journal_entry_id)
        return render_template(
            "admin/accounting/voucher_detail.html",
            title=f"السند {voucher.number}",
            voucher=voucher,
            entry=entry,
            error=None,
            **_context(),
        )

    @admin_bp.post("/accounting/journal/<int:entry_id>/reverse")
    def accounting_journal_reverse(entry_id):
        _ready()
        try:
            entry = db.session.get(AccountingJournalEntry, entry_id)
            if entry is None:
                raise ValueError("القيد غير موجود.")
            reversal = reverse_entry(
                entry,
                admin_id=_actor_id(),
                reason=request.form.get("reason") or "تصحيح محاسبي",
            )
            db.session.commit()
            return redirect(url_for("admin.accounting_journal", success=f"تم عكس القيد إلى {reversal.number}."))
        except (ValueError, TypeError) as exc:
            db.session.rollback()
            return redirect(url_for("admin.accounting_journal", q=request.form.get("query") or "", success=str(exc)))

    @admin_bp.post("/accounting/vouchers/<int:voucher_id>/void")
    def accounting_voucher_void(voucher_id):
        _ready()
        try:
            voucher = db.session.get(AccountingVoucher, voucher_id)
            if voucher is None:
                raise ValueError("السند غير موجود.")
            if voucher.status != "posted":
                raise ValueError("هذا السند ملغى مسبقًا.")
            entry = db.session.get(AccountingJournalEntry, voucher.journal_entry_id)
            reverse_entry(entry, admin_id=_actor_id(), reason="إلغاء سند " + voucher.number)
            voucher.status = "void"
            db.session.commit()
            return redirect(url_for("admin.accounting_vouchers", success=f"تم إلغاء السند {voucher.number} بقيد عكسي."))
        except (ValueError, TypeError) as exc:
            db.session.rollback()
            return redirect(url_for("admin.accounting_vouchers", error=str(exc)))

    @admin_bp.post("/accounting/sales/post")
    def accounting_post_sales():
        _ready()
        try:
            result = post_unposted_sales(admin_id=_actor_id(), limit=1000)
            db.session.commit()
            msg = f"تم ترحيل {result['posted_count']} طلب، وتجاوز {result['skipped_count']} طلب سبق ترحيله أو لا يمكن ترحيله."
            return redirect(url_for("admin.accounting_home", success=msg))
        except (ValueError, TypeError) as exc:
            db.session.rollback()
            return redirect(url_for("admin.accounting_home", error=str(exc)))

    @admin_bp.route("/accounting/insurance", methods=["GET", "POST"])
    def accounting_insurance():
        _ready()
        error = None
        success = request.args.get("success")
        editing_id = request.args.get("edit", type=int)
        editing_operation = db.session.get(CustomerLedgerOperation, editing_id) if editing_id else None
        if editing_operation and (
            editing_operation.operation_type != "insurance" or editing_operation.status != "posted"
        ):
            editing_operation = None
            error = "التأمين غير موجود أو تم عكسه مسبقًا."
        if request.method == "POST":
            try:
                operation_id = request.form.get("operation_id", type=int)
                old = db.session.get(CustomerLedgerOperation, operation_id) if operation_id else None
                if old and (old.operation_type != "insurance" or old.status != "posted"):
                    raise ValueError("لا يمكن تعديل تأمين غير مرحّل.")
                if old:
                    reverse_customer_operation(old, admin_id=_actor_id(), reason="تعديل بيانات تأمين عميل")
                    db.session.flush()
                operation = create_customer_operation(
                    operation_type="insurance",
                    customer_id=request.form.get("customer_id", type=int),
                    entered_amount=request.form.get("amount"),
                    currency_code="YER",
                    operation_date=_parse_date(request.form.get("operation_date"), date.today()),
                    cash_account_id=request.form.get("cash_account_id", type=int),
                    description=request.form.get("description"),
                    admin_id=_actor_id(),
                )
                db.session.commit()
                message = "تم تسجيل التأمين وترحيله على حساب العميل."
                if old:
                    message = f"تم تعديل التأمين بعكس القيد السابق وإصدار الحركة الجديدة #{operation.id}."
                return redirect(url_for("admin.accounting_insurance", success=message))
            except (ValueError, TypeError, LookupError) as exc:
                db.session.rollback()
                error = str(exc)
                editing_operation = db.session.get(CustomerLedgerOperation, request.form.get("operation_id", type=int)) if request.form.get("operation_id") else None

        customers = Customer.query.order_by(Customer.name, Customer.id.desc()).all()
        picker_context = _account_picker_context()
        operations = CustomerLedgerOperation.query.filter_by(operation_type="insurance").order_by(
            CustomerLedgerOperation.operation_date.desc(), CustomerLedgerOperation.id.desc()
        ).limit(500).all()
        for operation in operations:
            operation.ui_status = "ساري" if operation.status == "posted" else "معكوس"
            operation.ui_customer_balance = (
                -ledger_balance(operation.customer.ledger_account_id, currency_code="YER")
                if operation.customer and operation.customer.ledger_account_id else Decimal("0")
            )
        return render_template(
            "admin/accounting/insurance.html",
            title="تأمينات العملاء",
            customers=customers,
            operations=operations,
            editing_operation=editing_operation,
            show_form=bool(editing_operation or request.args.get("new")),
            error=error,
            success=success,
            today=date.today(),
            **picker_context,
            **_context(),
        )

    @admin_bp.route("/accounting/customer-daybook", methods=["GET", "POST"])
    def accounting_customer_daybook():
        _ready()
        error = None
        success = request.args.get("success")
        editing_id = request.args.get("edit", type=int)
        editing_operation = db.session.get(CustomerLedgerOperation, editing_id) if editing_id else None
        if editing_operation and (
            editing_operation.operation_type != "daybook" or editing_operation.status != "posted"
        ):
            editing_operation = None
            error = "قيد اليومية غير موجود أو تم عكسه مسبقًا."
        editing_side = "debit"
        if editing_operation and editing_operation.journal_entry and editing_operation.customer.ledger_account_id:
            customer_line = next(
                (line for line in editing_operation.journal_entry.lines
                 if line.account_id == editing_operation.customer.ledger_account_id),
                None,
            )
            editing_side = "credit" if customer_line and Decimal(str(customer_line.credit or 0)) > 0 else "debit"

        if request.method == "POST":
            try:
                operation_id = request.form.get("operation_id", type=int)
                old = db.session.get(CustomerLedgerOperation, operation_id) if operation_id else None
                if old and (old.operation_type != "daybook" or old.status != "posted"):
                    raise ValueError("لا يمكن تعديل قيد يومية غير مرحّل.")
                if old:
                    reverse_customer_operation(old, admin_id=_actor_id(), reason="تعديل قيد يومية العميل")
                    db.session.flush()
                credit_amount = (request.form.get("amount_credit") or "").strip()
                debit_amount = (request.form.get("amount_debit") or "").strip()
                has_credit = bool(credit_amount) and Decimal(credit_amount) > 0
                has_debit = bool(debit_amount) and Decimal(debit_amount) > 0
                if has_credit == has_debit:
                    raise ValueError("أدخل مبلغًا واحدًا فقط: في حقل «له» أو «عليه».")
                side = "credit" if has_credit else "debit"
                entered_amount = credit_amount if has_credit else debit_amount
                operation = create_customer_operation(
                    operation_type="daybook",
                    customer_id=request.form.get("customer_id", type=int),
                    entered_amount=entered_amount,
                    currency_code="YER",
                    operation_date=_parse_date(request.form.get("operation_date"), date.today()),
                    contra_account_id=request.form.get("contra_account_id", type=int),
                    side=side,
                    description=request.form.get("description"),
                    admin_id=_actor_id(),
                )
                db.session.commit()
                message = "تم تسجيل قيد يومية العميل وترحيله."
                if old:
                    message = f"تم تعديل القيد بعكس الحركة السابقة وإصدار قيد جديد #{operation.id}."
                return redirect(url_for("admin.accounting_customer_daybook", success=message))
            except (ValueError, TypeError, LookupError) as exc:
                db.session.rollback()
                error = str(exc)
                editing_operation = db.session.get(CustomerLedgerOperation, request.form.get("operation_id", type=int)) if request.form.get("operation_id") else None

        customers = Customer.query.order_by(Customer.name, Customer.id.desc()).all()
        picker_context = _account_picker_context()
        operations = CustomerLedgerOperation.query.filter_by(operation_type="daybook").order_by(
            CustomerLedgerOperation.operation_date.desc(), CustomerLedgerOperation.id.desc()
        ).limit(700).all()
        for operation in operations:
            customer_account_id = operation.customer.ledger_account_id if operation.customer else None
            customer_line = next(
                (line for line in operation.journal_entry.lines if line.account_id == customer_account_id),
                None,
            ) if operation.journal_entry and customer_account_id else None
            operation.ui_side = "credit" if customer_line and Decimal(str(customer_line.credit or 0)) > 0 else "debit"
            operation.ui_side_label = "له" if operation.ui_side == "credit" else "عليه"
            operation.ui_status = "ساري" if operation.status == "posted" else "معكوس"
        return render_template(
            "admin/accounting/customer_daybook.html",
            title="يوميات العملاء",
            customers=customers,
            operations=operations,
            editing_operation=editing_operation,
            editing_side=editing_side,
            show_form=bool(editing_operation or request.args.get("new")),
            error=error,
            success=success,
            today=date.today(),
            **picker_context,
            **_context(),
        )

    @admin_bp.get("/accounting/customers")
    def accounting_customers():
        _ready()
        query = (request.args.get("q") or "").strip()
        customers_query = Customer.query
        if query:
            like = f"%{query}%"
            customers_query = customers_query.filter(
                Customer.name.ilike(like)
                | Customer.phone_normalized.ilike(like)
                | Customer.invite_code.ilike(like)
            )
        customers = customers_query.order_by(Customer.name, Customer.id.desc()).limit(1000).all()
        rows = []
        for customer in customers:
            account = customer.ledger_account
            raw_balance = ledger_balance(account.id, currency_code="YER") if account else Decimal("0")
            rows.append({
                "customer": customer,
                "account": account,
                "balance": -raw_balance,
                "movement_count": CustomerLedgerOperation.query.filter_by(customer_id=customer.id).count(),
            })
        return render_template(
            "admin/accounting/customers.html",
            title="حسابات العملاء",
            rows=rows,
            query=query,
            **_context(),
        )

    @admin_bp.get("/accounting/customers/<int:customer_id>")
    def accounting_customer_statement(customer_id):
        _ready()
        customer = db.session.get(Customer, customer_id)
        if customer is None:
            return render_template(
                "admin/accounting/customer_statement.html",
                title="كشف حساب عميل",
                customer=None,
                error="العميل غير موجود.",
                **_context(),
            ), 404
        from ..services.accounting import ensure_customer_account
        account = ensure_customer_account(customer, db.session)
        db.session.flush()
        start = _parse_date(request.args.get("start"), date.today().replace(day=1))
        end = _parse_date(request.args.get("end"), date.today())
        opening_ledger = ledger_balance(account.id, currency_code="YER", end_date=start - timedelta(days=1))
        entries = (
            db.session.query(AccountingJournalEntry)
            .join(AccountingJournalLine, AccountingJournalLine.entry_id == AccountingJournalEntry.id)
            .filter(
                AccountingJournalLine.account_id == account.id,
                AccountingJournalEntry.status == "posted",
                AccountingJournalEntry.currency_code == "YER",
                AccountingJournalEntry.entry_date >= start,
                AccountingJournalEntry.entry_date <= end,
            )
            .order_by(AccountingJournalEntry.entry_date, AccountingJournalEntry.id)
            .distinct()
            .all()
        )
        movements = []
        balance = opening_ledger
        for entry in entries:
            for line in sorted(entry.lines, key=lambda row: row.id):
                if line.account_id != account.id:
                    continue
                balance += Decimal(str(line.debit or 0)) - Decimal(str(line.credit or 0))
                movements.append({"entry": entry, "line": line, "balance": balance})
        operation_rows = CustomerLedgerOperation.query.filter(
            CustomerLedgerOperation.customer_id == customer.id,
            CustomerLedgerOperation.operation_date >= start,
            CustomerLedgerOperation.operation_date <= end,
        ).order_by(CustomerLedgerOperation.operation_date.desc(), CustomerLedgerOperation.id.desc()).all()
        return render_template(
            "admin/accounting/customer_statement.html",
            title=f"كشف حساب · {customer.name or customer.phone_normalized}",
            customer=customer,
            account=account,
            start=start,
            end=end,
            opening=opening_ledger,
            closing=balance,
            customer_credit_balance=-balance,
            movements=movements,
            operations=operation_rows,
            error=None,
            **_context(),
        )

    @admin_bp.get("/accounting/ledger")
    def accounting_general_ledger():
        _ready()
        start = _parse_date(request.args.get("start"), date.today().replace(day=1))
        end = _parse_date(request.args.get("end"), date.today())
        account_id = request.args.get("account_id", type=int)
        currency = (request.args.get("currency") or "").strip().upper()
        query = (
            db.session.query(AccountingJournalLine, AccountingJournalEntry)
            .join(AccountingJournalEntry, AccountingJournalEntry.id == AccountingJournalLine.entry_id)
            .filter(
                AccountingJournalEntry.status == "posted",
                AccountingJournalEntry.entry_date >= start,
                AccountingJournalEntry.entry_date <= end,
            )
        )
        account = db.session.get(LedgerAccount, account_id) if account_id else None
        if account_id:
            query = query.filter(AccountingJournalLine.account_id == account_id)
        if currency:
            query = query.filter(AccountingJournalEntry.currency_code == currency)
        rows = query.order_by(
            AccountingJournalEntry.entry_date, AccountingJournalEntry.id, AccountingJournalLine.id
        ).limit(3000).all()
        opening = ledger_balance(account_id, currency_code=currency or None, end_date=start - timedelta(days=1)) if account_id else Decimal("0")
        running = opening
        movements = []
        for line, entry in rows:
            if account_id:
                running += Decimal(str(line.debit or 0)) - Decimal(str(line.credit or 0))
                balance = running
            else:
                balance = None
            movements.append({"line": line, "entry": entry, "balance": balance})
        return render_template(
            "admin/accounting/ledger.html",
            title="دفتر الأستاذ",
            rows=movements,
            account=account,
            account_id=account_id,
            account_start=opening,
            account_end=running if account_id else None,
            start=start,
            end=end,
            currency=currency,
            currencies=_currency_options(),
            **_account_picker_context(),
            **_context(),
        )

    @admin_bp.get("/accounting/reconciliation")
    def accounting_reconciliation():
        _ready()
        start = _parse_date(request.args.get("start"), date.today().replace(day=1))
        end = _parse_date(request.args.get("end"), date.today())
        currency = (request.args.get("currency") or "").strip().upper()
        query = (
            db.session.query(
                AccountingJournalEntry.currency_code,
                func.coalesce(func.sum(AccountingJournalLine.debit), 0),
                func.coalesce(func.sum(AccountingJournalLine.credit), 0),
            )
            .join(AccountingJournalLine, AccountingJournalLine.entry_id == AccountingJournalEntry.id)
            .filter(
                AccountingJournalEntry.status == "posted",
                AccountingJournalEntry.entry_date >= start,
                AccountingJournalEntry.entry_date <= end,
            )
        )
        if currency:
            query = query.filter(AccountingJournalEntry.currency_code == currency)
        totals = {}
        for code, debit, credit in query.group_by(AccountingJournalEntry.currency_code).all():
            debit_total = Decimal(str(debit or 0))
            credit_total = Decimal(str(credit or 0))
            totals[code] = {
                "debit": debit_total,
                "credit": credit_total,
                "difference": debit_total - credit_total,
                "balanced": abs(debit_total - credit_total) < Decimal("0.0001"),
            }
        return render_template(
            "admin/accounting/reconciliation.html",
            title="مطابقة الحسابات",
            start=start,
            end=end,
            currency=currency,
            currencies=_currency_options(),
            totals=totals,
            rows=_account_period_rows(start, end, currency or None),
            **_context(),
        )

    @admin_bp.get("/accounting/reports")
    def accounting_reports():
        _ready()
        start = _parse_date(request.args.get("start"), date.today().replace(day=1))
        end = _parse_date(request.args.get("end"), date.today())
        currency = (request.args.get("currency") or "").strip().upper()
        rows = _account_period_rows(start, end, currency or None)
        currencies = sorted({row["currency_code"] for row in rows})
        summaries = {}
        for row in rows:
            summary = summaries.setdefault(row["currency_code"], {
                "revenue": Decimal("0"), "expenses": Decimal("0"),
                "debit": Decimal("0"), "credit": Decimal("0"),
                "assets_at_end": Decimal("0"), "liabilities_at_end": Decimal("0"),
                "equity_at_end": Decimal("0"), "lifetime_revenue": Decimal("0"),
                "lifetime_expenses": Decimal("0"),
            })
            summary["debit"] += row["debit"]
            summary["credit"] += row["credit"]
            if row["account_type"] == "asset":
                summary["assets_at_end"] += row["closing"]
            elif row["account_type"] == "liability":
                summary["liabilities_at_end"] -= row["closing"]
            elif row["account_type"] == "equity":
                summary["equity_at_end"] -= row["closing"]
            elif row["account_type"] == "revenue":
                summary["revenue"] += row["credit"] - row["debit"]
                summary["lifetime_revenue"] -= row["closing"]
            elif row["account_type"] == "expense":
                summary["expenses"] += row["debit"] - row["credit"]
                summary["lifetime_expenses"] += row["closing"]
        for summary in summaries.values():
            summary["net"] = summary["revenue"] - summary["expenses"]
            # The result remains separate from retained earnings so the balance
            # sheet can display current accumulated profit before year-end closing.
            summary["lifetime_profit"] = summary["lifetime_revenue"] - summary["lifetime_expenses"]
            summary["balance_sheet_equity"] = summary["equity_at_end"] + summary["lifetime_profit"]
            summary["balance_difference"] = summary["assets_at_end"] - (
                summary["liabilities_at_end"] + summary["balance_sheet_equity"]
            )
        return render_template(
            "admin/accounting/reports.html",
            title="التقارير المحاسبية",
            rows=rows,
            summaries=summaries,
            currencies=_currency_options(),
            selected_currency=currency,
            available_currencies=currencies,
            start=start,
            end=end,
            **_context(),
        )

    @admin_bp.get("/accounting/reports/accounts/<int:account_id>")
    def accounting_account_statement(account_id):
        _ready()
        account = db.session.get(LedgerAccount, account_id)
        if account is None:
            return render_template("admin/accounting/statement.html", account=None, error="الحساب غير موجود.", **_context()), 404
        start = _parse_date(request.args.get("start"), date.today().replace(day=1))
        end = _parse_date(request.args.get("end"), date.today())
        currency = (request.args.get("currency") or "SAR").strip().upper()
        opening = ledger_balance(account.id, currency_code=currency, end_date=start - timedelta(days=1))
        lines = (
            db.session.query(AccountingJournalLine, AccountingJournalEntry)
            .join(AccountingJournalEntry, AccountingJournalEntry.id == AccountingJournalLine.entry_id)
            .filter(
                AccountingJournalLine.account_id == account.id,
                AccountingJournalEntry.status == "posted",
                AccountingJournalEntry.currency_code == currency,
                AccountingJournalEntry.entry_date >= start,
                AccountingJournalEntry.entry_date <= end,
            )
            .order_by(AccountingJournalEntry.entry_date, AccountingJournalEntry.id, AccountingJournalLine.id)
            .all()
        )
        running = opening
        movements = []
        for line, entry in lines:
            running += Decimal(str(line.debit or 0)) - Decimal(str(line.credit or 0))
            movements.append({"line": line, "entry": entry, "balance": running})
        return render_template(
            "admin/accounting/statement.html",
            title="كشف حساب",
            account=account,
            movements=movements,
            opening=opening,
            closing=running,
            start=start,
            end=end,
            currency=currency,
            currencies=_currency_options(),
            **_context(),
        )


def _context():
    from .context import build_admin_context
    return build_admin_context()
