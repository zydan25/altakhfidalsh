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
)


def _ready():
    ensure_accounting_setup(db.session, backfill_parties=True)
    db.session.commit()


def _actor_id():
    return session.get("admin_id")


def _parse_date(value, default):
    try:
        return datetime.strptime((value or "").strip(), "%Y-%m-%d").date()
    except (ValueError, TypeError):
        return default


def _currency_options():
    currencies = Currency.query.filter_by(is_active=True).order_by(Currency.code).all()
    rows = [{"code": row.code, "name": getattr(row, "name", None) or row.code} for row in currencies]
    if not any(row["code"] == "SAR" for row in rows):
        rows.insert(0, {"code": "SAR", "name": "ريال سعودي (افتراضي)"})
    return rows


def _postable_accounts():
    return (
        LedgerAccount.query
        .filter_by(is_active=True, is_group=False, allow_manual_posting=True)
        .order_by(LedgerAccount.code)
        .all()
    )


def _account_options():
    accounts = LedgerAccount.query.order_by(LedgerAccount.code).all()
    return [
        {
            "account": row,
            "label": f"{row.code} · {row.name}" + (" (غير نشط)" if not row.is_active else ""),
        }
        for row in accounts
    ]


def _account_tree(accounts):
    by_parent = {}
    for account in accounts:
        by_parent.setdefault(account.parent_id, []).append(account)
    for rows in by_parent.values():
        rows.sort(key=lambda row: row.code or "")
    result = []
    visited = set()

    def walk(parent_id=None, depth=0):
        for row in by_parent.get(parent_id, []):
            if row.id in visited:
                continue
            visited.add(row.id)
            result.append({"account": row, "depth": depth})
            walk(row.id, depth + 1)

    walk()
    # Retain any malformed/orphaned branches visibly rather than silently hiding them.
    for row in accounts:
        if row.id not in visited:
            result.append({"account": row, "depth": 0})
            walk(row.id, 1)
    return result


def _account_period_rows(start, end, currency=None):
    q = (
        db.session.query(
            LedgerAccount.id,
            LedgerAccount.code,
            LedgerAccount.name,
            LedgerAccount.account_type,
            AccountingJournalEntry.currency_code,
            func.coalesce(func.sum(AccountingJournalLine.debit), 0).label("debit"),
            func.coalesce(func.sum(AccountingJournalLine.credit), 0).label("credit"),
        )
        .join(AccountingJournalLine, AccountingJournalLine.account_id == LedgerAccount.id)
        .join(AccountingJournalEntry, AccountingJournalEntry.id == AccountingJournalLine.entry_id)
        .filter(
            LedgerAccount.is_group.is_(False),
            AccountingJournalEntry.status == "posted",
            AccountingJournalEntry.entry_date >= start,
            AccountingJournalEntry.entry_date <= end,
        )
    )
    if currency:
        q = q.filter(AccountingJournalEntry.currency_code == currency)
    q = q.group_by(
        LedgerAccount.id,
        LedgerAccount.code,
        LedgerAccount.name,
        LedgerAccount.account_type,
        AccountingJournalEntry.currency_code,
    ).order_by(LedgerAccount.code, AccountingJournalEntry.currency_code)
    rows = []
    for row in q.all():
        debit = Decimal(str(row.debit or 0))
        credit = Decimal(str(row.credit or 0))
        rows.append({
            "id": row.id,
            "code": row.code,
            "name": row.name,
            "account_type": row.account_type,
            "currency_code": row.currency_code,
            "opening": ledger_balance(row.id, currency_code=row.currency_code, end_date=start - timedelta(days=1)),
            "debit": debit,
            "credit": credit,
            "closing": ledger_balance(row.id, currency_code=row.currency_code, end_date=end),
        })
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
                    account.is_active = request.form.get("is_active") == "on"
                    account.allow_manual_posting = (not account.is_group) and request.form.get("allow_manual_posting") == "on"
                elif action == "toggle":
                    if account.is_group and account.children:
                        raise ValueError("لا يمكن تعطيل حساب تجميعي يحتوي فروعًا؛ عطّل الحسابات الفرعية أولًا.")
                    account.is_active = not account.is_active
                elif action == "delete":
                    raise ValueError("لا يُحذف الحساب من السجل المحاسبي؛ عطّله بدلًا من ذلك حتى تبقى القيود والتقارير سليمة.")
                else:
                    raise ValueError("إجراء الحساب غير معروف.")
                db.session.commit()
                return redirect(url_for("admin.accounting_accounts", success="تم حفظ التغييرات."))
            except (ValueError, TypeError) as exc:
                db.session.rollback()
                error = str(exc)

        all_accounts = LedgerAccount.query.order_by(LedgerAccount.code).all()
        balances = {}
        movement_rows = (
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
        for account_id, currency_code, debit, credit in movement_rows:
            balances.setdefault(account_id, []).append({
                "currency": currency_code,
                "balance": Decimal(str(debit or 0)) - Decimal(str(credit or 0)),
            })
        return render_template(
            "admin/accounting/accounts.html",
            title="شجرة الحسابات",
            tree=_account_tree(all_accounts),
            accounts=all_accounts,
            parent_options=[row for row in all_accounts if row.is_group and row.is_active],
            balances=balances,
            account_type_labels=ACCOUNT_TYPES,
            error=error,
            success=success,
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
        if request.method == "POST":
            try:
                voucher_type = (request.form.get("voucher_type") or "receipt").strip()
                voucher = create_voucher(
                    voucher_type=voucher_type,
                    voucher_date=_parse_date(request.form.get("voucher_date"), date.today()),
                    amount=request.form.get("amount"),
                    currency_code=(request.form.get("currency_code") or "SAR").strip().upper(),
                    from_account_id=request.form.get("from_account_id", type=int),
                    to_account_id=request.form.get("to_account_id", type=int),
                    beneficiary=request.form.get("beneficiary"),
                    description=request.form.get("description"),
                    admin_id=_actor_id(),
                )
                db.session.commit()
                return redirect(url_for("admin.accounting_vouchers", success=f"تم إصدار السند {voucher.number}."))
            except (ValueError, TypeError) as exc:
                db.session.rollback()
                error = str(exc)
        vouchers = AccountingVoucher.query.order_by(
            AccountingVoucher.voucher_date.desc(), AccountingVoucher.id.desc()
        ).limit(300).all()
        return render_template(
            "admin/accounting/vouchers.html",
            title="السندات المحاسبية",
            vouchers=vouchers,
            accounts=_postable_accounts(),
            currencies=_currency_options(),
            today=date.today(),
            error=error,
            success=request.args.get("success"),
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
            })
            summary["debit"] += row["debit"]
            summary["credit"] += row["credit"]
            if row["account_type"] == "revenue":
                summary["revenue"] += row["credit"] - row["debit"]
            elif row["account_type"] == "expense":
                summary["expenses"] += row["debit"] - row["credit"]
        for summary in summaries.values():
            summary["net"] = summary["revenue"] - summary["expenses"]
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
