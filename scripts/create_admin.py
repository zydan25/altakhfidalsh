import os

from app import create_app
from scripts.seed import seed


def main():
    username = os.getenv("ADMIN_USERNAME")
    password = os.getenv("ADMIN_PASSWORD")
    if not username or not password:
        raise SystemExit("Set ADMIN_USERNAME and ADMIN_PASSWORD first.")
    # Seed also creates the baseline permissions/role and attaches this admin.
    seed()
    print(f"Admin bootstrap completed for: {username}")


if __name__ == "__main__":
    main()
