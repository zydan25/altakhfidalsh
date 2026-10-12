from datetime import date
from decimal import Decimal

from app.extensions import db
from app.models import (
    AccountingJournalEntry,
    AccountingJournalLine,
    AccountingVoucher,
    Admin,
    Customer,
    LedgerAccount,
)
from app.services.accounting import (
    create_posted_entry,
    create_voucher,
    ensure_chart,
    ledger_balance,
    reverse_entry,
)


def test_customer_and_staff_receive_automatic_ledger_accounts(app):
    with app.app_context():
        customer = Customer(phone_normalized="967700001001", name="عميل محاسبي")
        admin = Admin(username="accounting-test-staff", status="active")
        db.session.add_all([customer, admin])
        db.session.commit()

        assert customer.ledger_account_id is not None
        assert admin.ledger_account_id is not None
        assert customer.ledger_account.system_key == "customer:967700001001"
        assert admin.ledger_account.system_key == "staff:accounting-test-staff"
        assert customer.ledger_account.parent.system_key == "customers_root"
        assert admin.ledger_account.parent.system_key == "staff_root"


def test_manual_journal_must_be_balanced_and_uses_detail_accounts(app):
    with app.app_context():
        chart = ensure_chart(db.session)
        db.session.flush()
        entry = create_posted_entry(
            description="قيد اختبار متوازن",
            entry_date=date.today(),
            currency_code="SAR",
            created_by_admin_id=None,
            lines=[
                {"account": chart["main_cash"], "debit": "125.50", "credit": "0"},
                {"account": chart["sales_revenue"], "debit": "0", "credit": "125.50"},
            ],
            source_type="manual",
            prefix="TEST",
        )
        db.session.commit()

        assert entry.status == "posted"
        assert entry.totals() == (Decimal("125.5000"), Decimal("125.5000"))
        assert len(entry.lines) == 2
        assert ledger_balance(chart["main_cash"].id, currency_code="SAR") == Decimal("125.5000")


def test_receipt_voucher_creates_balanced_journal_and_reversal(app):
    with app.app_context():
        customer = Customer(phone_normalized="967700001002", name="عميل سند")
        db.session.add(customer)
        db.session.commit()

        chart = ensure_chart(db.session)
        voucher = create_voucher(
            voucher_type="receipt",
            voucher_date=date.today(),
            amount="75",
            currency_code="SAR",
            from_account_id=customer.ledger_account_id,
            to_account_id=chart["main_cash"].id,
            beneficiary="عميل سند",
            description="سند قبض اختبار",
            admin_id=None,
        )
        db.session.commit()
        entry = db.session.get(AccountingJournalEntry, voucher.journal_entry_id)

        assert voucher.status == "posted"
        assert voucher.amount == Decimal("75.0000")
        assert entry.totals() == (Decimal("75.0000"), Decimal("75.0000"))
        assert next(line for line in entry.lines if line.account_id == chart["main_cash"].id).debit == Decimal("75.0000")

        reversal = reverse_entry(entry, admin_id=None, reason="اختبار العكس")
        db.session.commit()
        db.session.refresh(entry)
        assert entry.status == "void"
        assert entry.reversed_entry_id == reversal.id
        assert reversal.totals() == (Decimal("75.0000"), Decimal("75.0000"))
        assert AccountingJournalEntry.query.filter_by(source_type="reverse", source_id=entry.id).count() == 1
        assert AccountingVoucher.query.get(voucher.id).journal_entry_id == entry.id


def test_accounting_dashboard_and_screens_render(app, client):
    with app.app_context():
        admin = Admin(username="accounting-screen-admin", status="active")
        db.session.add(admin)
        db.session.commit()
        admin_id = admin.id

    with client.session_transaction() as state:
        state["admin_id"] = admin_id

    for path in (
        "/admin/accounting",
        "/admin/accounting/accounts",
        "/admin/accounting/journal",
        "/admin/accounting/vouchers",
        "/admin/accounting/reports",
    ):
        response = client.get(path)
        assert response.status_code == 200, path
