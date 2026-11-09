"""Notes API - Application tier (Flask).

Stateless REST API. All state lives in PostgreSQL (Amazon RDS in the cloud),
so any number of identical containers can run behind the load balancer.

Credentials:
  * In AWS, DB_SECRET_ARN points at the RDS-managed secret in Secrets Manager.
    The container reads it with the EC2 instance role, so no password is ever
    written to disk, an image, the repo, or the CI/CD pipeline.
  * Locally / in CI, DB_USER and DB_PASSWORD env vars are used instead.
"""

import json
import logging
import os
import threading
import time

import psycopg
from flask import Flask, jsonify, request
from psycopg.rows import dict_row

log = logging.getLogger("notes")
logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"),
                    format="%(asctime)s %(levelname)s %(name)s %(message)s")

TITLE_MAX = 200
CONTENT_MAX = 10_000
SECRET_TTL_SECONDS = 300  # re-read the secret periodically so rotation is picked up

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS notes (
    id          SERIAL PRIMARY KEY,
    title       VARCHAR(200) NOT NULL,
    content     TEXT         NOT NULL DEFAULT '',
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
)
"""

_secret_cache = {"creds": None, "expires": 0.0}
_schema_ready = False
_lock = threading.Lock()


def _credentials():
    """Return (user, password) from Secrets Manager or environment."""
    secret_arn = os.getenv("DB_SECRET_ARN")
    if not secret_arn:
        return os.environ["DB_USER"], os.environ["DB_PASSWORD"]

    with _lock:
        if _secret_cache["creds"] and _secret_cache["expires"] > time.time():
            return _secret_cache["creds"]
        import boto3  # imported lazily: not needed locally / in CI

        client = boto3.client("secretsmanager", region_name=os.getenv("AWS_REGION"))
        secret = json.loads(client.get_secret_value(SecretId=secret_arn)["SecretString"])
        creds = (secret["username"], secret["password"])
        _secret_cache.update(creds=creds, expires=time.time() + SECRET_TTL_SECONDS)
        return creds


def _connect():
    user, password = _credentials()
    return psycopg.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=int(os.getenv("DB_PORT", "5432")),
        dbname=os.getenv("DB_NAME", "notes"),
        user=user,
        password=password,
        sslmode=os.getenv("DB_SSLMODE", "prefer"),  # "require" in AWS -> TLS to RDS
        connect_timeout=5,
        row_factory=dict_row,
    )


def _ensure_schema(conn):
    """Create the table once. An advisory lock stops several containers
    (on several hosts) racing each other on first start."""
    global _schema_ready
    if _schema_ready:
        return
    with conn.transaction():
        conn.execute("SELECT pg_advisory_xact_lock(4242)")
        conn.execute(SCHEMA_SQL)
    _schema_ready = True


def get_conn():
    try:
        conn = _connect()
    except psycopg.OperationalError:
        # Password may have been rotated: drop the cached secret and retry once.
        _secret_cache["expires"] = 0.0
        conn = _connect()
    try:
        _ensure_schema(conn)
    except Exception:
        conn.close()
        raise
    return conn


def _serialize(row):
    return {
        "id": row["id"],
        "title": row["title"],
        "content": row["content"],
        "created_at": row["created_at"].isoformat(),
        "updated_at": row["updated_at"].isoformat(),
    }


def _validate(payload):
    if not isinstance(payload, dict):
        return None, "Request body must be a JSON object"
    title = str(payload.get("title", "")).strip()
    content = str(payload.get("content", "")).strip()
    if not title:
        return None, "Title is required"
    if len(title) > TITLE_MAX:
        return None, f"Title must be at most {TITLE_MAX} characters"
    if len(content) > CONTENT_MAX:
        return None, f"Content must be at most {CONTENT_MAX} characters"
    return {"title": title, "content": content}, None


def create_app():
    app = Flask(__name__)
    app.json.sort_keys = False

    # ---------- health / info ----------
    @app.get("/api/health")
    def health():
        """Liveness check used by the ALB target group (no DB call, so a DB blip
        does not make every target unhealthy at once)."""
        return jsonify(status="ok")

    @app.get("/api/ready")
    def ready():
        """Readiness check: proves the app can reach the database."""
        try:
            with get_conn() as conn:
                conn.execute("SELECT 1")
            return jsonify(status="ok", database="reachable")
        except Exception as exc:  # noqa: BLE001
            log.warning("readiness check failed: %s", exc)
            return jsonify(status="error", database="unreachable"), 503

    @app.get("/api/info")
    def info():
        """Shown in the UI footer: proves load balancing and which commit is live."""
        return jsonify(
            instance_id=os.getenv("INSTANCE_ID", "local"),
            availability_zone=os.getenv("AVAILABILITY_ZONE", "local"),
            version=os.getenv("APP_VERSION", "dev")[:7],
        )

    # ---------- notes CRUD ----------
    @app.get("/api/notes")
    def list_notes():
        with get_conn() as conn:
            rows = conn.execute(
                "SELECT * FROM notes ORDER BY updated_at DESC, id DESC LIMIT 200"
            ).fetchall()
        return jsonify([_serialize(r) for r in rows])

    @app.get("/api/notes/<int:note_id>")
    def get_note(note_id):
        with get_conn() as conn:
            row = conn.execute("SELECT * FROM notes WHERE id = %s", (note_id,)).fetchone()
        if not row:
            return jsonify(error="Note not found"), 404
        return jsonify(_serialize(row))

    @app.post("/api/notes")
    def create_note():
        data, err = _validate(request.get_json(silent=True))
        if err:
            return jsonify(error=err), 400
        with get_conn() as conn:
            row = conn.execute(
                "INSERT INTO notes (title, content) VALUES (%s, %s) RETURNING *",
                (data["title"], data["content"]),
            ).fetchone()
        log.info("created note id=%s", row["id"])
        return jsonify(_serialize(row)), 201

    @app.put("/api/notes/<int:note_id>")
    def update_note(note_id):
        data, err = _validate(request.get_json(silent=True))
        if err:
            return jsonify(error=err), 400
        with get_conn() as conn:
            row = conn.execute(
                "UPDATE notes SET title = %s, content = %s, updated_at = now() "
                "WHERE id = %s RETURNING *",
                (data["title"], data["content"], note_id),
            ).fetchone()
        if not row:
            return jsonify(error="Note not found"), 404
        return jsonify(_serialize(row))

    @app.delete("/api/notes/<int:note_id>")
    def delete_note(note_id):
        with get_conn() as conn:
            cur = conn.execute("DELETE FROM notes WHERE id = %s", (note_id,))
        if cur.rowcount == 0:
            return jsonify(error="Note not found"), 404
        return "", 204

    # ---------- errors ----------
    @app.errorhandler(404)
    def not_found(_):
        return jsonify(error="Not found"), 404

    @app.errorhandler(405)
    def method_not_allowed(_):
        return jsonify(error="Method not allowed"), 405

    @app.errorhandler(500)
    def server_error(exc):
        log.exception("unhandled error: %s", exc)
        return jsonify(error="Internal server error"), 500

    return app
