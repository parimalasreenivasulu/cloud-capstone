import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app"))
from app import app  # noqa: E402

client = app.test_client()


def test_health():
    r = client.get("/health")
    assert r.status_code == 200 and r.get_json() == {"status": "ok"}


def test_index_reads_environment(monkeypatch):
    monkeypatch.setenv("APP_MESSAGE", "configured via env")
    monkeypatch.setenv("APP_ENV", "production")
    body = client.get("/").get_json()
    assert body["message"] == "configured via env" and body["environment"] == "production"


def test_metrics_exposed():
    client.get("/health")
    text = client.get("/metrics").get_data(as_text=True)
    assert "app_http_requests_total" in text and "app_http_request_duration_seconds" in text


def test_demo_endpoints_disabled_by_default(monkeypatch):
    monkeypatch.delenv("ENABLE_DEMO_ENDPOINTS", raising=False)
    assert client.get("/error").status_code == 404


def test_demo_error_when_enabled(monkeypatch):
    monkeypatch.setenv("ENABLE_DEMO_ENDPOINTS", "true")
    assert client.get("/error").status_code == 500
