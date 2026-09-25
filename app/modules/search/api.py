from flask import request
from sqlalchemy import func, or_

from . import api_bp
from ...extensions import db
from ...models import (
    Category,
    Product,
    ProductCategory,
    ProductFilterValue,
    SearchSynonym,
)


@api_bp.get("/products")
def search_products():
    q = (request.args.get("q") or "").strip()
    category_id = request.args.get("category_id", type=int)
    filter_values = [
        int(x) for x in request.args.getlist("filter_value_id") if str(x).isdigit()
    ]

    terms = [q] if q else []
    if q:
        synonyms = SearchSynonym.query.filter(
            or_(
                SearchSynonym.term.ilike(q),
                SearchSynonym.synonym.ilike(q),
            ),
            SearchSynonym.locale == "ar",
            SearchSynonym.is_active.is_(True),
        ).limit(20).all()
        for row in synonyms:
            terms.extend([row.term, row.synonym])
    terms = list(dict.fromkeys([term for term in terms if term]))

    query = Product.query.filter(
        Product.is_active.is_(True),
        Product.status == "published",
    )

    if terms:
        search_clauses = []
        for term in terms:
            like = f"%{term}%"
            search_clauses.append(
                or_(
                    Product.name.ilike(like),
                    Product.sku.ilike(like),
                    Product.description.ilike(like),
                )
            )
        query = query.filter(or_(*search_clauses))

    if category_id:
        descendants = _category_descendants(category_id)
        query = query.join(ProductCategory).filter(ProductCategory.category_id.in_(descendants))

    if filter_values:
        unique_filter_values = sorted(set(filter_values))
        matching_products = (
            db.session.query(ProductFilterValue.product_id)
            .filter(ProductFilterValue.filter_value_id.in_(unique_filter_values))
            .group_by(ProductFilterValue.product_id)
            .having(func.count(func.distinct(ProductFilterValue.filter_value_id)) == len(unique_filter_values))
            .subquery()
        )
        query = query.filter(Product.id.in_(matching_products))

    rows = query.distinct().order_by(Product.id.desc()).limit(100).all()
    return {"items": [
        {
            "id": x.id,
            "sku": x.sku,
            "name": x.name,
            "base_price_sar": str(x.base_price),
            "compare_at_price": str(x.compare_at_price) if x.compare_at_price is not None else None,
        }
        for x in rows
    ]}


@api_bp.get("/synonyms")
def synonyms():
    rows = SearchSynonym.query.filter_by(is_active=True).order_by(SearchSynonym.term, SearchSynonym.synonym).limit(500).all()
    return {"items": [{"id": x.id, "term": x.term, "synonym": x.synonym, "locale": x.locale} for x in rows]}


@api_bp.post("/synonyms")
def create_synonym():
    payload = request.get_json(silent=True) or {}
    term = str(payload["term"]).strip()
    synonym = str(payload["synonym"]).strip()
    locale = str(payload.get("locale", "ar")).strip()
    if SearchSynonym.query.filter_by(term=term, synonym=synonym, locale=locale).first():
        return {"error": "duplicate_synonym"}, 400
    row = SearchSynonym(term=term, synonym=synonym, locale=locale)
    db.session.add(row)
    db.session.commit()
    return {"item": {"id": row.id, "term": row.term, "synonym": row.synonym, "locale": row.locale}}, 201


def _category_descendants(root_id):
    ids = {root_id}
    changed = True
    while changed:
        changed = False
        children = Category.query.filter(Category.parent_id.in_(ids), Category.is_active.is_(True)).all()
        for child in children:
            if child.id not in ids:
                ids.add(child.id)
                changed = True
    return ids
