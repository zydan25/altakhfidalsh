from flask import Flask


def register_module_blueprints(app: Flask) -> None:
    from .catalog import api_bp as catalog_api_bp
    from .pricing import api_bp as pricing_api_bp
    from .storefront import api_bp as storefront_api_bp
    from .commerce import api_bp as commerce_api_bp
    from .customer import api_bp as customer_api_bp
    from .support import api_bp as support_api_bp
    from .promotions import api_bp as promotions_api_bp
    from .system import api_bp as system_api_bp

    api_blueprints = (
        catalog_api_bp,
        pricing_api_bp,
        storefront_api_bp,
        commerce_api_bp,
        customer_api_bp,
        support_api_bp,
        promotions_api_bp,
        system_api_bp,
    )
    for blueprint in api_blueprints:
        app.register_blueprint(blueprint, url_prefix="/api/v1")
