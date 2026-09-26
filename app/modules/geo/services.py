import re
from sqlalchemy import func

from ...extensions import db
from ...models import City, CityArea


_ARABIC_SLUG_MAP = str.maketrans({
    "ا": "a", "أ": "a", "إ": "i", "آ": "a", "ب": "b", "ت": "t", "ث": "th",
    "ج": "j", "ح": "h", "خ": "kh", "د": "d", "ذ": "th", "ر": "r", "ز": "z",
    "س": "s", "ش": "sh", "ص": "s", "ض": "d", "ط": "t", "ظ": "z", "ع": "a",
    "غ": "gh", "ف": "f", "ق": "q", "ك": "k", "ل": "l", "م": "m", "ن": "n",
    "ه": "h", "و": "w", "ي": "y", "ى": "a", "ة": "h", "ؤ": "w", "ئ": "y",
    "ء": "", "ـ": "",
})


def slug_code(value: str, fallback: str = "ITEM") -> str:
    text = (value or "").strip().lower().translate(_ARABIC_SLUG_MAP)
    text = re.sub(r"[^a-z0-9]+", "-", text).strip("-")
    return (text or fallback.lower()).upper()[:40]


def generate_unique_code(model, name: str, parent_field, parent_id: int, fallback: str) -> str:
    base = slug_code(name, fallback=fallback)
    code = base
    index = 2
    while (
        db.session.query(model.id)
        .filter(parent_field == parent_id, model.code == code)
        .first()
        is not None
    ):
        suffix = f"-{index}"
        code = (base[:40 - len(suffix)] + suffix).upper()
        index += 1
    return code


def generate_city_code(name: str, region_id: int) -> str:
    return generate_unique_code(City, name, City.region_id, region_id, "CITY")


def generate_area_code(name: str, city_id: int) -> str:
    return generate_unique_code(CityArea, name, CityArea.city_id, city_id, "AREA")
