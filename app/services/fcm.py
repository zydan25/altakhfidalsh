import json
import logging
import os
import re
from urllib.parse import urljoin, urlparse

import firebase_admin
from firebase_admin import credentials, messaging
from flask import current_app

from ..extensions import db
from ..models import CustomerDevice

logger = logging.getLogger(__name__)


class FCMService:
    """Best-effort Firebase Cloud Messaging delivery for customer devices."""

    _app = None

    # FCM reserves specific data-payload keys, including message_type.
    # Namespace reserved keys instead of sending them as-is so Firebase
    # accepts the notification and the original application data is retained.
    _reserved_data_key_names = frozenset({
        "from",
        "message_type",
    })

    @classmethod
    def _firebase_app(cls):
        if cls._app is not None:
            return cls._app

        try:
            cls._app = firebase_admin.get_app()
            return cls._app
        except ValueError:
            pass

        credentials_path = (
            current_app.config.get("FIREBASE_CREDENTIALS")
            or os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
        )
        if not credentials_path:
            logger.warning("FCM disabled: Firebase service-account credentials are not configured.")
            return None

        try:
            cls._app = firebase_admin.initialize_app(
                credentials.Certificate(credentials_path)
            )
            return cls._app
        except Exception:
            logger.exception("FCM initialization failed.")
            return None

    @classmethod
    def _safe_data_key(cls, key):
        key = str(key)
        lowered = key.lower()
        if (
            lowered in cls._reserved_data_key_names
            or lowered.startswith("google.")
            or lowered.startswith("gcm.")
        ):
            return "data_" + key
        return key

    @classmethod
    def _string_data(cls, data):
        result = {}
        for raw_key, value in dict(data or {}).items():
            key = cls._safe_data_key(raw_key)
            if key != str(raw_key):
                logger.debug(
                    "Renamed reserved FCM data key %r to %r",
                    str(raw_key),
                    key,
                )
            if value is None:
                result[key] = ""
            elif isinstance(value, str):
                result[key] = value
            else:
                result[key] = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
        return result

    @classmethod
    def _absolute_image_url(cls, value):
        raw = str(value or "").strip()
        if not raw:
            return None
        parsed = urlparse(raw)
        if parsed.scheme in {"https", "http"} and parsed.netloc:
            return raw
        # MEDIA_BASE_URL commonly uses a local /media path. FCM requires an
        # absolute URL, so resolve paths against the public storefront host.
        base = str(current_app.config.get("PUBLIC_BASE_URL") or "https://takhfidsh.alattab.site").rstrip("/") + "/"
        absolute = urljoin(base, raw.lstrip("/"))
        parsed_absolute = urlparse(absolute)
        return absolute if parsed_absolute.scheme == "https" and parsed_absolute.netloc else None

    @classmethod
    def _message(cls, title, body, data, token, *, local_actions=False):
        # Always include the standard FCM notification payload. Android/FCM
        # displays it in the system tray while the app is backgrounded or
        # terminated. Local action buttons must never suppress the notification.
        data_map = cls._string_data(data)
        title_text = str(title or "التخفيض الصح")[:240]
        body_text = str(body or "")[:1000]
        image_url = cls._absolute_image_url((data or {}).get("image_url"))
        raw_color = str((data or {}).get("accent_color") or "").strip()
        accent_color = raw_color if re.fullmatch(r"#[0-9a-fA-F]{6}", raw_color) else None
        raw_action_color = str((data or {}).get("action_color") or "").strip()
        action_color = (
            raw_action_color
            if re.fullmatch(r"#[0-9a-fA-F]{6}", raw_action_color)
            else None
        )

        # Keep display fields in data for foreground local notifications and
        # navigation, without replacing the system notification payload.
        data_map["title"] = title_text
        data_map["body"] = body_text
        if image_url:
            data_map["image_url"] = image_url
        else:
            data_map.pop("image_url", None)
        if accent_color:
            data_map["accent_color"] = accent_color
        else:
            data_map.pop("accent_color", None)
        if action_color:
            data_map["action_color"] = action_color
        else:
            data_map.pop("action_color", None)

        return messaging.Message(
            notification=messaging.Notification(
                title=title_text,
                body=body_text,
                image=image_url,
            ),
            data=data_map,
            token=token,
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    title=title_text,
                    body=body_text,
                    channel_id="altakhfid_alerts_v7",
                    sound="default",
                    priority="max",
                    visibility="public",
                    icon="notification_icon",
                    color=accent_color,
                    image=image_url,
                    ticker=title_text,
                    default_sound=True,
                    default_vibrate_timings=True,
                ),
            ),
        )

    @classmethod
    def send_to_customer(cls, customer_id, title, body, data=None):
        app = cls._firebase_app()
        if app is None:
            return {"sent": 0, "failed": 0}

        rows = (
            CustomerDevice.query
            .filter(
                CustomerDevice.customer_id == int(customer_id),
                CustomerDevice.is_active.is_(True),
                CustomerDevice.push_token.isnot(None),
            )
            .order_by(CustomerDevice.id)
            .all()
        )
        messages = []
        device_rows = []
        for row in rows:
            token = str(row.push_token or "").strip()
            if not token:
                continue
            messages.append(
                cls._message(
                    title,
                    body,
                    data,
                    token,
                    local_actions=str(row.platform or "").strip().lower() == "android_actions_v1",
                )
            )
            device_rows.append(row)

        if not messages:
            return {"sent": 0, "failed": 0}

        try:
            response = messaging.send_each(messages, app=app)
        except Exception:
            logger.exception("FCM batch delivery failed for customer %s", customer_id)
            return {"sent": 0, "failed": len(messages)}
        sent = 0
        failed = 0
        changed = False

        for row, result in zip(device_rows, response.responses):
            if result.success:
                sent += 1
                continue
            failed += 1
            error = result.exception
            if isinstance(error, (messaging.UnregisteredError, messaging.SenderIdMismatchError)):
                row.push_token = None
                row.is_active = False
                changed = True
                logger.info("Removed invalid FCM token for customer device %s", row.id)
            else:
                logger.warning("FCM delivery failed for customer device %s: %s", row.id, error)

        if changed:
            db.session.commit()
        return {"sent": sent, "failed": failed}

    @classmethod
    def send_to_customers(cls, customer_ids, title, body, data=None):
        total_sent = 0
        total_failed = 0
        for customer_id in customer_ids:
            result = cls.send_to_customer(customer_id, title, body, data)
            total_sent += int(result.get("sent", 0))
            total_failed += int(result.get("failed", 0))
        return {"sent": total_sent, "failed": total_failed}
