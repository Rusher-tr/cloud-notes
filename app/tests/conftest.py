import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

# Defaults match the Postgres service container in the GitHub Actions workflow.
os.environ.setdefault("DB_HOST", "localhost")
os.environ.setdefault("DB_PORT", "5432")
os.environ.setdefault("DB_NAME", "notes")
os.environ.setdefault("DB_USER", "notes")
os.environ.setdefault("DB_PASSWORD", "test-only-password")
os.environ.setdefault("DB_SSLMODE", "disable")

import app as notes_app  # noqa: E402


@pytest.fixture()
def client():
    flask_app = notes_app.create_app()
    flask_app.config.update(TESTING=True)
    with notes_app.get_conn() as conn:
        conn.execute("TRUNCATE notes RESTART IDENTITY")
    with flask_app.test_client() as c:
        yield c
