import json
import queue
import threading
import time

import psycopg
from flask import current_app

from flask_sock import Sock


sock = Sock()


class RealtimeNotificationHub:
    CHANNEL = "customer_notifications"

    def __init__(self):
        self._lock = threading.RLock()
        self._connections = {}
        self._listener_started = False

    def subscribe(self, customer_id):
        customer_id = int(customer_id)
        q = queue.Queue(maxsize=50)
        with self._lock:
            self._connections.setdefault(customer_id, set()).add(q)
            self._ensure_listener()
        return q

    def unsubscribe(self, customer_id, q):
        customer_id = int(customer_id)
        with self._lock:
            rows = self._connections.get(customer_id)
            if not rows:
                return
            rows.discard(q)
            if not rows:
                self._connections.pop(customer_id, None)

    def publish_local(self, customer_id, payload):
        with self._lock:
            rows = list(self._connections.get(int(customer_id), set()))
        for q in rows:
            try:
                q.put_nowait(payload)
            except queue.Full:
                # A slow socket will catch up from the durable notifications
                # endpoint after reconnect; never block the business request.
                pass

    def _ensure_listener(self):
        if self._listener_started:
            return
        self._listener_started = True
        uri = current_app.config.get("SQLALCHEMY_DATABASE_URI", "")
        threading.Thread(
            target=self._listen_forever,
            args=(uri,),
            name="altakhfid-notification-listener",
            daemon=True,
        ).start()

    def _listen_forever(self, uri):
        if not uri or "postgres" not in uri:
            return

        dsn = uri.replace("postgresql+psycopg://", "postgresql://", 1)

        while True:
            conn = None
            try:
                conn = psycopg.connect(dsn, autocommit=True)
                conn.execute(f"LISTEN {self.CHANNEL}")
                for notify in conn.notifies(timeout=30):
                    try:
                        payload = json.loads(notify.payload or "{}")
                        customer_id = int(payload.get("customer_id") or 0)
                        if customer_id <= 0:
                            continue
                        self.publish_local(customer_id, payload)
                    except (TypeError, ValueError, json.JSONDecodeError):
                        continue
            except Exception:
                time.sleep(3)
            finally:
                try:
                    if conn is not None:
                        conn.close()
                except Exception:
                    pass


hub = RealtimeNotificationHub()


def init_realtime(app):
    app.config.setdefault(
        "SOCK_SERVER_OPTIONS",
        {
            "ping_interval": 25,
            "max_message_size": 64 * 1024,
        },
    )
    sock.init_app(app)


@sock.route("/api/v1/notifications/ws")
def customer_notification_socket(ws):
    from .modules.customer.security import current_customer

    customer = current_customer()
    if customer is None:
        try:
            ws.send(json.dumps({
                "type": "error",
                "code": "unauthorized",
            }))
        except Exception:
            pass
        return

    customer_id = int(customer.id)
    events = hub.subscribe(customer_id)

    try:
        ws.send(json.dumps({
            "type": "connected",
            "customer_id": customer_id,
        }, ensure_ascii=False))

        while True:
            try:
                payload = events.get(timeout=20)
                ws.send(json.dumps(payload, ensure_ascii=False))
            except queue.Empty:
                ws.send(json.dumps({
                    "type": "heartbeat",
                    "ts": int(time.time()),
                }))
    except Exception:
        pass
    finally:
        hub.unsubscribe(customer_id, events)
