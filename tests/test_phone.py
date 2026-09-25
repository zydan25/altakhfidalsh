from app.services.phone import normalize_phone


def test_normalize_yemen_mobile():
    assert normalize_phone("771234567") == "967771234567"


def test_normalize_with_plus_prefix():
    assert normalize_phone("+967771234567") == "967771234567"
