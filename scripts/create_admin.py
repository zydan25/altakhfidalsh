import os

from app.admin.auth import AdminAuthService
from app import create_app


def main():
    username = os.getenv("ADMIN_USERNAME")
    password = os.getenv("ADMIN_PASSWORD")
    if not username or not password:
        raise SystemExit("Set ADMIN_USERNAME and ADMIN_PASSWORD first.")
    app = create_app()
    with app.app_context():
        print(AdminAuthService.bootstrap(username, password))


if __name__ == "__main__":
    main()
