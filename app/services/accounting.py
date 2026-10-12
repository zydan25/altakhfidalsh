"""Double-entry accounting services for the commerce application.

The chart and journal rules are adapted from zydan25/kareem, but use the
commerce system's existing Customer, Admin, Currency and Order records.
"""
from datetime import date, datetime, timezone
from decimal import Decimal, InvalidOperation
import secrets

from sqlalchemy import event, func
from sqlalchemy.orm import Session

from ..extensions import db
from ..models import (
    Admin,
    AdminRole,
    AccountingJournalEntry,
    AccountingJournalLine,
    AccountingVoucher,
    Customer,
    LedgerAccount,
    Order,
    OrderItem,
    Permission,
    Role,
    RolePermission,
    Currency,
)


ACCOUNT_TYPES = {
    "asset": "الأصول",
    "liability": "الخصوم",
    "equity": "حقوق الملكية",
    "revenue": "الإيرادات",
    "expense": "المصروفات",
}

ROOT_ACCOUNTS = [
    ("1000", "الأصول", "asset", "assets_root"),
    ("2000", "الخصوم", "liability", "liabilities_root"),
    ("3000", "حقوق الملكية", "equity", "equity_root"),
    ("4000", "الإيرادات", "revenue", "revenue_root"),
    ("5000", "المصروفات", "expense", "expenses_root"),
]

CHILD_ACCOUNTS = [
    ("1100", "النقد والبنوك", "asset", "assets_root", True, "cash_root"),
    ("1101", "الصندوق الرئيسي", "asset", "cash_root", False, "main_cash"),
    ("1102", "مبالغ قيد التحصيل الإلكتروني", "asset", "cash_root", False, "payment_clearing"),
    ("1200", "حسابات العملاء المدينة", "asset", "assets_root", True, "customers_root"),
    ("1300", "حسابات الموظفين", "asset", "assets_root", True, "staff_root"),
    ("2100", "التزامات قصيرة الأجل", "liability", "liabilities_root", True, "payables_root"),
    ("2101", "مستحقات الموظفين", "liability", "payables_root", False, "staff_payables"),
    ("3010", "أرصدة افتتاحية", "equity", "equity_root", False, "opening_equity"),
    ("4100", "إيرادات المبيعات", "revenue", "revenue_root", False, "sales_revenue"),
    ("4200", "إيرادات أخرى", "revenue", "revenue_root", False, "other_revenue"),
    ("5100", "تكلفة البضاعة والمصروفات المباشرة", "expense", "expenses_root", False, "cost_of_sales"),
    ("5200", "مصروفات تشغيلية", "expense", "expenses_root", False, "operating_expenses"),
    ("5300", "خصومات ومردودات المبيعات", "expense", "expenses_root", False, "sales_returns"),
]

ACCOUNTING_PERMISSIONS = [
    ("accounting.view", "عرض النظام المحاسبي"),
    ("accounting.manage", "إدارة الحسابات والسندات"),
    ("accounting.post", "ترحيل وعكس القيود المحاسبية"),
]


def D(value, label="المبلغ"):
    try:
        return Decimal(str(value if value not in (None, "") else "0")).quantize(Decimal("0.0001"))
    except (InvalidOperation, ValueError, TypeError) as exc:
        raise ValueError(f"{label}: قيمة رقمية غير صحيحة.") from exc


def _new_accounts(session):
    return [row for row in session.new if isinstance(row, LedgerAccount)]


def _find_system_account(session, key):
    for row in _new_accounts(session):
        if row.system_key == key:
            return row
    with session.no_autoflush:
        return session.query(LedgerAccount).filter_by(system_key=key).first()


def _unique_account_code(session, proposed):
    codes = {row.code for row in _new_accounts(session)}
    with session.no_autoflush:
        exists = session.query(LedgerAccount.id).filter_by(code=proposed).first()
    if proposed not in codes and not exists:
        return proposed
    while True:
        fallback = f"{proposed}-{secrets.token_hex(2).upper()}"
        with session.no_autoflush:
            exists = session.query(LedgerAccount.id).filter_by(code=fallback).first()
        if fallback not in codes and not exists:
            return fallback


def _ensure_account(session, *, system_key, code, name, account_type,
                    parent=None, is_group=False, allow_manual_posting=True, description=None):
    account = _find_system_account(session, system_key)
    if account:
        # Keep links stable; only refresh names for auto-generated party accounts.
        if system_key.startswith(("customer:", "staff:")):
            account.name = name
        return account
    account = LedgerAccount(
        code=_unique_account_code(session, code),
        name=name,
        account_type=account_type,
        parent=parent,
        is_group=is_group,
        allow_manual_posting=allow_manual_posting if not is_group else False,
        system_key=system_key,
        description=description,
        is_active=True,
    )
    session.add(account)
    return account


def ensure_chart(session=None):
    """Create the protected accounting chart idempotently without deleting user accounts."""
    session = session or db.session
    accounts = {}
    for code, name, account_type, key in ROOT_ACCOUNTS:
        accounts[key] = _ensure_account(
            session,
            system_key=key,
            code=code,
            name=name,
            account_type=account_type,
            is_group=True,
            allow_manual_posting=False,
        )
    for code, name, account_type, parent_key, is_group, key in CHILD_ACCOUNTS:
        accounts[key] = _ensure_account(
            session,
            system_key=key,
            code=code,
            name=name,
            account_type=account_type,
            parent=accounts[parent_key],
            is_group=is_group,
            allow_manual_posting=not is_group,
        )
    return accounts


def ensure_customer_account(customer, session=None):
    session = session or db.session
    if customer.ledger_account:
        return customer.ledger_account
    chart = ensure_chart(session)
    phone = (customer.phone_normalized or "").strip()
    key = f"customer:{phone}" if phone else f"customer:id:{customer.id or secrets.token_hex(5)}"
    account = _ensure_account(
        session,
        system_key=key,
        code=f"CUS-{secrets.token_hex(5).upper()}",
        name=f"عميل: {(customer.name or phone or ('#' + str(customer.id or 'جديد'))).strip()}",
        account_type="asset",
        parent=chart["customers_root"],
        description="حساب فرعي يُنشأ تلقائيًا للعميل.",
    )
    customer.ledger_account = account
    return account


def ensure_admin_account(admin, session=None):
    session = session or db.session
    if admin.ledger_account:
        return admin.ledger_account
    chart = ensure_chart(session)
    key = f"staff:{admin.username}"
    account = _ensure_account(
        session,
        system_key=key,
        code=f"STAFF-{secrets.token_hex(5).upper()}",
        name=f"حساب موظف: {admin.username}",
        account_type="asset",
        parent=chart["staff_root"],
        description="حساب فرعي يُنشأ تلقائيًا لحساب موظف الإدارة.",
    )
    admin.ledger_account = account
    return account


def ensure_accounting_permissions(session=None):
    session = session or db.session
    permissions = {}
    for code, name in ACCOUNTING_PERMISSIONS:
        with session.no_autoflush:
            permission = session.query(Permission).filter_by(code=code).first()
        if permission is None:
            permission = next((p for p in session.new if isinstance(p, Permission) and p.code == code), None)
        if permission is None:
            permission = Permission(code=code, name=name, is_active=True)
            session.add(permission)
        else:
            permission.name = name
            permission.is_active = True
        permissions[code] = permission

    # Materialize newly inserted permission IDs before creating RolePermission rows.
    session.flush()
    with session.no_autoflush:
        roles = session.query(Role).filter_by(is_active=True).all()
        system_manage = session.query(Permission).filter_by(code="system.manage", is_active=True).first()
    for role in roles:
        should_grant_all = role.code.lower() in {"admin", "administrator", "superadmin", "super_admin"}
        if system_manage:
            with session.no_autoflush:
                should_grant_all = should_grant_all or session.query(RolePermission.id).filter_by(
                    role_id=role.id, permission_id=system_manage.id
                ).first() is not None
        existing_pairs = {
            rp.permission_id
            for rp in session.new
            if isinstance(rp, RolePermission) and rp.role_id == role.id
        }
        for code, permission in permissions.items():
            grant = should_grant_all or (code == "accounting.view" and role.code.lower() in {"accountant", "auditor"})
            if not grant:
                continue
            with session.no_autoflush:
                assigned = session.query(RolePermission.id).filter_by(
                    role_id=role.id, permission_id=permission.id
                ).first() if permission.id else None
            if not assigned and permission.id not in existing_pairs:
                session.add(RolePermission(role_id=role.id, permission_id=permission.id))


def ensure_accounting_setup(session=None, *, backfill_parties=True):
    session = session or db.session
    chart = ensure_chart(session)
    ensure_accounting_permissions(session)
    if backfill_parties:
        with session.no_autoflush:
            customers = session.query(Customer).filter(Customer.ledger_account_id.is_(None)).all()
            staff = session.query(Admin).filter(Admin.ledger_account_id.is_(None)).all()
        for customer in customers:
            ensure_customer_account(customer, session)
        for admin in staff:
            ensure_admin_account(admin, session)
    session.flush()
    return chart


def _account_by_id(session, account_id):
    account = session.get(LedgerAccount, account_id)
    if account is None:
        raise ValueError("الحساب المحدد غير موجود.")
    if not account.is_active:
        raise ValueError(f"الحساب «{account.name}» غير نشط.")
    if account.is_group or not account.allow_manual_posting:
        raise ValueError(f"لا يمكن القيد مباشرة على الحساب الرئيسي «{account.name}». اختر حسابًا فرعيًا.")
    return account


def next_entry_number(session=None, prefix="JE", entry_date=None):
    session = session or db.session
    day = (entry_date or date.today()).strftime("%Y%m%d")
    with session.no_autoflush:
        count = session.query(func.count(AccountingJournalEntry.id)).filter(
            AccountingJournalEntry.number.like(f"{prefix}-{day}-%")
        ).scalar() or 0
    number = f"{prefix}-{day}-{count + 1:05d}"
    while True:
        with session.no_autoflush:
            existing = session.query(AccountingJournalEntry.id).filter_by(number=number).first()
        if not existing:
            return number
        count += 1
        number = f"{prefix}-{day}-{count + 1:05d}"


def create_posted_entry(*, description, entry_date, currency_code, created_by_admin_id,
                        lines, source_type="manual", source_id=None, prefix="JE", session=None):
    session = session or db.session
    description = (description or "").strip()
    if not description:
        raise ValueError("وصف القيد مطلوب.")
    if not currency_code or len(currency_code) > 16:
        raise ValueError("رمز العملة غير صحيح.")
    if source_id is not None:
        with session.no_autoflush:
            duplicate = session.query(AccountingJournalEntry).filter_by(
                source_type=source_type, source_id=source_id
            ).first()
        if duplicate:
            raise ValueError(f"هذا المصدر مرحّل مسبقًا بالقيد {duplicate.number}.")

    normalized = []
    debit_total = Decimal("0")
    credit_total = Decimal("0")
    for item in lines:
        account = item.get("account")
        if not account:
            account = _account_by_id(session, item.get("account_id"))
        else:
            account = _account_by_id(session, account.id)
        debit = D(item.get("debit"), "المدين")
        credit = D(item.get("credit"), "الدائن")
        if debit < 0 or credit < 0 or ((debit > 0) == (credit > 0)):
            raise ValueError("كل سطر يجب أن يحتوي مدينًا أو دائنًا واحدًا بقيمة موجبة.")
        debit_total += debit
        credit_total += credit
        normalized.append((account, debit, credit, (item.get("description") or "").strip(), item.get("reference")))

    if len(normalized) < 2 or debit_total <= 0 or debit_total != credit_total:
        raise ValueError("القيد غير متزن. يجب أن تتساوى المجاميع المدينة والدائنة وأن يحتوي سطرين على الأقل.")

    entry = AccountingJournalEntry(
        number=next_entry_number(session, prefix=prefix, entry_date=entry_date),
        entry_date=entry_date,
        description=description,
        status="posted",
        source_type=source_type,
        source_id=source_id,
        currency_code=currency_code,
        created_by_admin_id=created_by_admin_id,
        posted_at=datetime.now(timezone.utc),
    )
    session.add(entry)
    session.flush()
    for account, debit, credit, line_description, reference in normalized:
        session.add(AccountingJournalLine(
            entry_id=entry.id,
            account_id=account.id,
            debit=debit,
            credit=credit,
            description=line_description or description,
            reference=reference,
        ))
    session.flush()
    return entry


def reverse_entry(entry, *, admin_id, reason=None, session=None):
    session = session or db.session
    if not entry:
        raise ValueError("القيد غير موجود.")
    if entry.status != "posted":
        raise ValueError("يمكن عكس القيود المرحلة فقط.")
    if entry.reversed_entry_id:
        raise ValueError("تم عكس هذا القيد مسبقًا.")
    reason = (reason or "تصحيح محاسبي").strip()
    lines = [
        {
            "account": line.account,
            "debit": line.credit,
            "credit": line.debit,
            "description": f"عكس: {line.description or entry.description}",
            "reference": entry.number,
        }
        for line in entry.lines
    ]
    reversal = create_posted_entry(
        description=f"عكس القيد {entry.number}: {reason}",
        entry_date=date.today(),
        currency_code=entry.currency_code,
        created_by_admin_id=admin_id,
        lines=lines,
        source_type="reverse",
        source_id=entry.id,
        prefix="REV",
        session=session,
    )
    entry.reversed_entry_id = reversal.id
    entry.status = "void"
    return reversal


def create_voucher(*, voucher_type, voucher_date, amount, currency_code, from_account_id,
                   to_account_id, beneficiary, description, admin_id, session=None):
    session = session or db.session
    amount = D(amount)
    if amount <= 0:
        raise ValueError("قيمة السند يجب أن تكون أكبر من صفر.")
    voucher_type = (voucher_type or "").strip()
    if voucher_type not in {"receipt", "payment", "transfer", "adjustment"}:
        raise ValueError("نوع السند غير مدعوم.")
    from_account = _account_by_id(session, from_account_id) if from_account_id else None
    to_account = _account_by_id(session, to_account_id) if to_account_id else None
    if not from_account or not to_account:
        raise ValueError("اختر الحسابين من شجرة الحسابات.")
    if from_account.id == to_account.id:
        raise ValueError("لا يمكن استخدام الحساب نفسه طرفًا مدينًا ودائنًا.")

    if voucher_type == "receipt":
        lines = [
            {"account": to_account, "debit": amount, "credit": 0},
            {"account": from_account, "debit": 0, "credit": amount},
        ]
    elif voucher_type == "payment":
        lines = [
            {"account": from_account, "debit": amount, "credit": 0},
            {"account": to_account, "debit": 0, "credit": amount},
        ]
    else:
        lines = [
            {"account": to_account, "debit": amount, "credit": 0},
            {"account": from_account, "debit": 0, "credit": amount},
        ]

    prefix = {"receipt": "RV", "payment": "PV", "transfer": "TV", "adjustment": "AV"}[voucher_type]
    entry = create_posted_entry(
        description=description,
        entry_date=voucher_date,
        currency_code=currency_code,
        created_by_admin_id=admin_id,
        lines=lines,
        source_type="voucher",
        prefix=prefix,
        session=session,
    )
    number = f"{prefix}-{voucher_date.strftime('%Y%m%d')}-{entry.number.rsplit('-',1)[-1]}"
    voucher = AccountingVoucher(
        number=number,
        voucher_type=voucher_type,
        voucher_date=voucher_date,
        amount=amount,
        currency_code=currency_code,
        from_account_id=from_account.id,
        to_account_id=to_account.id,
        beneficiary=(beneficiary or "").strip() or None,
        description=description.strip(),
        status="posted",
        journal_entry_id=entry.id,
        created_by_admin_id=admin_id,
    )
    session.add(voucher)
    session.flush()
    return voucher


def order_currency_code(session, order):
    currency = session.get(Currency, order.currency_id) if getattr(order, "currency_id", None) else None
    return (getattr(currency, "code", None) or "SAR").strip().upper()


def post_unposted_sales(*, admin_id, limit=500, session=None):
    """Post orders to the GL once. Paid sales debit the payment clearing account;
    unpaid orders debit the customer's receivable account. Canceled orders are skipped.
    """
    session = session or db.session
    chart = ensure_chart(session)
    with session.no_autoflush:
        orders = (
            session.query(Order)
            .filter(Order.status.notin_(("cancelled", "canceled", "void")))
            .order_by(Order.id.asc())
            .limit(limit)
            .all()
        )
    posted = []
    skipped = 0
    for order in orders:
        with session.no_autoflush:
            exists = session.query(AccountingJournalEntry.id).filter_by(
                source_type="order_sale", source_id=order.id
            ).first()
        if exists:
            skipped += 1
            continue
        customer = session.get(Customer, order.customer_id)
        if customer is None:
            skipped += 1
            continue
        customer_account = ensure_customer_account(customer, session)
        paid = (getattr(order, "payment_status", "") or "").lower() in {"paid", "succeeded", "captured", "complete", "completed"}
        debit_account = chart["payment_clearing"] if paid else customer_account
        created = order.created_at
        entry_date = created.date() if created else date.today()
        try:
            entry = create_posted_entry(
                description=f"مبيعات الطلب {order.order_no}",
                entry_date=entry_date,
                currency_code=order_currency_code(session, order),
                created_by_admin_id=admin_id,
                lines=[
                    {"account": debit_account, "debit": D(order.total), "credit": 0,
                     "description": "ذمم العميل" if not paid else "مبالغ قيد التحصيل الإلكتروني",
                     "reference": order.order_no},
                    {"account": chart["sales_revenue"], "debit": 0, "credit": D(order.total),
                     "description": f"إيراد المبيعات - {order.order_no}", "reference": order.order_no},
                ],
                source_type="order_sale",
                source_id=order.id,
                prefix="SALE",
                session=session,
            )
            posted.append(entry)
        except ValueError as exc:
            # Idempotency issues are safely counted as skipped; validation issues are raised.
            if "مرحل مسبقًا" in str(exc):
                skipped += 1
                continue
            raise
    return {"posted": posted, "posted_count": len(posted), "skipped_count": skipped}


def ledger_balance(account_id, *, currency_code=None, start_date=None, end_date=None, session=None):
    session = session or db.session
    query = (
        session.query(func.coalesce(func.sum(AccountingJournalLine.debit - AccountingJournalLine.credit), 0))
        .join(AccountingJournalEntry, AccountingJournalEntry.id == AccountingJournalLine.entry_id)
        .filter(
            AccountingJournalLine.account_id == account_id,
            AccountingJournalEntry.status == "posted",
        )
    )
    if currency_code:
        query = query.filter(AccountingJournalEntry.currency_code == currency_code)
    if start_date:
        query = query.filter(AccountingJournalEntry.entry_date >= start_date)
    if end_date:
        query = query.filter(AccountingJournalEntry.entry_date <= end_date)
    return D(query.scalar())

_ACCOUNTING_EVENTS_REGISTERED = False


def _auto_create_party_accounts(session, flush_context, instances):
    pending_customers = [row for row in session.new if isinstance(row, Customer)]
    pending_staff = [row for row in session.new if isinstance(row, Admin)]
    if not pending_customers and not pending_staff:
        return
    # The listener runs within the same transaction as the party creation.
    ensure_chart(session)
    for customer in pending_customers:
        if not customer.ledger_account_id and not customer.ledger_account:
            ensure_customer_account(customer, session)
    for staff in pending_staff:
        if not staff.ledger_account_id and not staff.ledger_account:
            ensure_admin_account(staff, session)


def register_accounting_events():
    """Register auto-subledger creation once, for API and admin-created parties alike."""
    global _ACCOUNTING_EVENTS_REGISTERED
    if not _ACCOUNTING_EVENTS_REGISTERED:
        event.listen(Session, "before_flush", _auto_create_party_accounts)
        _ACCOUNTING_EVENTS_REGISTERED = True
