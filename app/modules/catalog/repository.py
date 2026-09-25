from ...models import Product


class ProductRepository:
    @staticmethod
    def get(product_id):
        return Product.query.get(product_id)
