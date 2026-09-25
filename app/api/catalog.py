from flask import request

from . import api_bp
from ..models import Category, Product, ProductCategory


def _build_tree(categories):
    nodes = {
        category.id: {
            "id": category.id,
            "parent_id": category.parent_id,
            "name": category.name,
            "slug": category.slug,
            "icon_asset_id": category.icon_asset_id,
            "badge_id": category.badge_id,
            "display_style": category.display_style,
            "sort_order": category.sort_order,
            "children": [],
        }
        for category in categories
    }
    roots = []
    for category in categories:
        node = nodes[category.id]
        if category.parent_id and category.parent_id in nodes:
            nodes[category.parent_id]["children"].append(node)
        else:
            roots.append(node)

    def sort_node(node):
        node["children"].sort(key=lambda item: (item["sort_order"], item["name"]))
        for child in node["children"]:
            sort_node(child)

    roots.sort(key=lambda item: (item["sort_order"], item["name"]))
    for root in roots:
        sort_node(root)
    return roots


@api_bp.get("/categories/tree")
def category_tree():
    categories = (
        Category.query
        .filter(Category.is_active.is_(True))
        .order_by(Category.parent_id, Category.sort_order, Category.name)
        .all()
    )
    return {"items": _build_tree(categories)}


@api_bp.get("/catalog/products")
def product_list():
    page = max(request.args.get("page", 1, type=int), 1)
    per_page = min(max(request.args.get("per_page", 20, type=int), 1), 100)
    status = request.args.get("status", "published")
    category_id = request.args.get("category_id", type=int)

    query = Product.query.filter(
        Product.is_active.is_(True),
        Product.status == status,
    )
    if category_id:
        query = query.join(ProductCategory).filter(ProductCategory.category_id == category_id)

    pagination = query.order_by(Product.id.desc()).paginate(
        page=page,
        per_page=per_page,
        error_out=False,
    )
    return {
        "items": [
            {
                "id": product.id,
                "sku": product.sku,
                "name": product.name,
                "base_price_sar": str(product.base_price),
                "compare_at_price": (
                    str(product.compare_at_price)
                    if product.compare_at_price is not None
                    else None
                ),
                "status": product.status,
            }
            for product in pagination.items
        ],
        "pagination": {
            "page": pagination.page,
            "per_page": pagination.per_page,
            "pages": pagination.pages,
            "total": pagination.total,
        },
    }
