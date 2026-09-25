import re

def normalize_phone(raw: str, default_country_code: str = "967") -> str:
    digits = re.sub(r"\D+", "", raw or "")
    if digits.startswith("00"):
        digits = digits[2:]
    if digits.startswith("+967"):
        digits = digits[1:]
    if digits.startswith("7") and len(digits) == 9:
        digits = default_country_code + digits
    return digits
