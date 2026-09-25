import os
from pathlib import Path


class Config:
    SECRET_KEY = os.getenv("SECRET_KEY", "change-me")
    SQLALCHEMY_DATABASE_URI = os.getenv(
        "DATABASE_URL",
        "postgresql+psycopg://postgres:postgres@localhost:5432/altakhfidalsh",
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    MAX_CONTENT_LENGTH = int(os.getenv("MAX_UPLOAD_BYTES", 25 * 1024 * 1024))
    APP_TIMEZONE = os.getenv("APP_TIMEZONE", "Asia/Aden")

    MEDIA_ROOT = os.getenv(
        "MEDIA_ROOT",
        str(Path(__file__).resolve().parent / "storage" / "media"),
    )
    MEDIA_BASE_URL = os.getenv("MEDIA_BASE_URL", "/media")
    MEDIA_MAX_SIDE = int(os.getenv("MEDIA_MAX_SIDE", "1600"))
    MEDIA_WEBP_QUALITY = int(os.getenv("MEDIA_WEBP_QUALITY", "82"))
    ADMIN_DEV_BYPASS = os.getenv("ADMIN_DEV_BYPASS", "0") == "1"
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = "Lax"
    SESSION_COOKIE_SECURE = os.getenv("SESSION_COOKIE_SECURE", "0") == "1"
    CORS_ORIGINS = os.getenv("CORS_ORIGINS", "*")
