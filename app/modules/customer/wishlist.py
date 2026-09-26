from ...extensions import db
from ...models import RecentlyViewed, Wishlist, WishlistItem


class CustomerEngagementService:
    @staticmethod
    def add_wishlist(customer_id, product_id):
        wishlist = Wishlist.query.filter_by(customer_id=customer_id).first()
        if wishlist is None:
            wishlist = Wishlist(customer_id=customer_id)
            db.session.add(wishlist)
            db.session.flush()
        item = WishlistItem.query.filter_by(wishlist_id=wishlist.id, product_id=product_id).first()
        if item is None:
            item = WishlistItem(wishlist_id=wishlist.id, product_id=product_id)
            db.session.add(item)
            db.session.commit()
        return {"wishlist_id": wishlist.id, "product_id": product_id}


    @staticmethod
    def list_wishlist(customer_id):
        wishlist = Wishlist.query.filter_by(customer_id=customer_id).first()
        if wishlist is None:
            return []
        rows = WishlistItem.query.filter_by(wishlist_id=wishlist.id).order_by(WishlistItem.id.desc()).all()
        return [{"id": x.id, "product_id": x.product_id, "added_at": x.added_at.isoformat()} for x in rows]


    @staticmethod
    def track_view(customer_id, product_id):
        row = RecentlyViewed(customer_id=customer_id, product_id=product_id)
        db.session.add(row)
        db.session.commit()
        return {"id": row.id}


    @staticmethod
    def remove_wishlist(customer_id, product_id):
        wishlist = Wishlist.query.filter_by(customer_id=customer_id).first()
        if wishlist is None:
            return {"ok": True}
        row = WishlistItem.query.filter_by(wishlist_id=wishlist.id, product_id=product_id).first()
        if row:
            db.session.delete(row)
            db.session.commit()
        return {"ok": True, "product_id": product_id}


    @staticmethod
    def list_recent_views(customer_id, limit=30):
        rows = (
            RecentlyViewed.query
            .filter_by(customer_id=customer_id)
            .order_by(RecentlyViewed.viewed_at.desc(), RecentlyViewed.id.desc())
            .limit(min(max(int(limit), 1), 100))
            .all()
        )
        return [
            {"id": row.id, "product_id": row.product_id, "viewed_at": row.viewed_at.isoformat()}
            for row in rows
        ]
