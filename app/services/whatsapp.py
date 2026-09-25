import requests
from flask import current_app


class WhatsAppService:
    @staticmethod
    def session_name():
        return current_app.config.get("WHATSAPP_SESSION", "basheer")

    @staticmethod
    def base_url():
        return current_app.config.get("WHATSAPP_BASE_URL", "https://whatsapp.alattab.site").rstrip("/")

    @classmethod
    def session_url(cls, suffix=""):
        return f"{cls.base_url()}/api/sessions/{cls.session_name()}{suffix}"

    @staticmethod
    def _request(method, url, **kwargs):
        timeout = current_app.config.get("WHATSAPP_TIMEOUT", 20)
        headers = dict(kwargs.pop("headers", {}) or {})
        api_key = current_app.config.get("WHATSAPP_API_KEY")
        if api_key:
            headers["Authorization"] = f"Bearer {api_key}"
        response = requests.request(method, url, timeout=timeout, headers=headers, **kwargs)
        response.raise_for_status()
        return response.json() if response.content else {"success": True}

    @classmethod
    def status(cls):
        return cls._request("GET", cls.session_url("/status"))

    @classmethod
    def qr(cls):
        return cls._request("GET", cls.session_url("/qr"))

    @classmethod
    def connect(cls):
        return cls._request("POST", cls.session_url("/connect"), json={})

    @classmethod
    def disconnect(cls):
        return cls._request("POST", cls.session_url("/disconnect"), json={})

    @classmethod
    def logout(cls):
        return cls._request("POST", cls.session_url("/logout"), json={})

    @classmethod
    def api_url(cls, external_url):
        return cls._request("POST", cls.session_url("/api-url"), json={"apiBaseUrl": external_url})

    @classmethod
    def messages(cls, limit=50, offset=0):
        return cls._request("GET", cls.session_url("/messages"), params={"limit": limit, "offset": offset})

    @classmethod
    def errors(cls, limit=25):
        return cls._request("GET", cls.session_url("/errors"), params={"limit": limit})

    @classmethod
    def notifications(cls, limit=50):
        return cls._request("GET", cls.session_url("/notifications"), params={"limit": limit})

    @classmethod
    def send_text(cls, phone, message):
        return cls._request(
            "POST",
            cls.session_url("/send"),
            data={"phoneNumber": phone, "message": message},
        )

    @classmethod
    def send_media(cls, phone, message, file_storage):
        return cls._request(
            "POST",
            cls.session_url("/send"),
            data={"phoneNumber": phone, "message": message},
            files={"media": (
                file_storage.filename or "attachment",
                file_storage.stream,
                file_storage.mimetype or "application/octet-stream",
            )},
        )
