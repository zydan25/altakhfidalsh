import pytest

from app import create_app
from app.extensions import db


class TestConfig:
    TESTING = True
    DEBUG = True
    SECRET_KEY = "test-secret"
    SQLALCHEMY_DATABASE_URI = "sqlite:///:memory:"
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    MEDIA_ROOT = "/tmp/altakhfidalsh-test-media"
    MEDIA_BASE_URL = "/media"
    MEDIA_MAX_SIDE = 800
    MEDIA_WEBP_QUALITY = 80
    ADMIN_DEV_BYPASS = True


@pytest.fixture
def app():
    app = create_app(TestConfig)
    with app.app_context():
        db.create_all()
        yield app
        db.session.remove()
        db.drop_all()


@pytest.fixture
def client(app):
    return app.test_client()