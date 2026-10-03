import re


def normalize_phone(raw: str, default_country_code: str = "967") -> str:
    """Return the canonical Yemen mobile format when enough information exists."""
    digits = re.sub(r"\D+", "", raw or "")
    if digits.startswith("00"):
        digits = digits[2:]

    if digits.startswith(default_country_code):
        return digits

    # Accept +967/967 after non-digits have already been removed.
    if digits.startswith("+" + default_country_code):
        return digits[1:]

    # Accept the common local Yemen mobile form 07XXXXXXXX.
    if digits.startswith("0") and len(digits) == 10 and digits[1] == "7":
        return default_country_code + digits[1:]

    # Accept the local mobile form 7XXXXXXXX.
    if digits.startswith("7") and len(digits) == 9:
        return default_country_code + digits

    return digits


def phone_candidates(raw: str, default_country_code: str = "967") -> list[str]:
    """Return canonical/legacy representations used by older customer records."""
    digits = re.sub(r"\D+", "", raw or "")
    if digits.startswith("00"):
        digits = digits[2:]

    canonical = normalize_phone(digits, default_country_code)
    candidates = [canonical]

    if digits.startswith("0") and len(digits) == 10 and digits[1] == "7":
        candidates.append(digits)
    elif digits.startswith("7") and len(digits) == 9:
        candidates.append("0" + digits)
        candidates.append(digits)
    elif digits.startswith(default_country_code) and len(digits) == 12:
        local = digits[len(default_country_code):]
        if local.startswith("7") and len(local) == 9:
            candidates.append("0" + local)
            candidates.append(local)

    # Preserve order while removing duplicates/empty values.
    return list(dict.fromkeys(x for x in candidates if x))
