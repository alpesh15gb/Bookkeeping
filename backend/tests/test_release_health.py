"""Release-gate regression tests for process and dependency probes."""

from unittest.mock import Mock


def test_liveness_is_dependency_independent(client):
    response = client.get("/livez")

    assert response.status_code == 200
    assert response.json()["status"] == "alive"


def test_readiness_has_structured_dependency_failure(client, monkeypatch):
    import src.main as main

    monkeypatch.setattr(main, "engine", Mock(connect=Mock(side_effect=RuntimeError("db down"))))

    response = client.get("/readyz")

    assert response.status_code == 503
    body = response.json()
    assert body["status"] == "degraded"
    assert body["checks"]["database"] == "error"
    assert "detail" not in body


def test_health_and_readiness_share_contract(client, monkeypatch):
    import src.main as main

    monkeypatch.setattr(main, "_dependency_health", lambda: {"database": "error", "redis": "ok"})

    health = client.get("/health")
    ready = client.get("/readiness")

    assert health.status_code == ready.status_code == 503
    assert health.json() == ready.json()
