from app.main import app


def test_root_returns_200():
    client = app.test_client()
    response = client.get("/")
    assert response.status_code == 200


def test_root_payload_has_required_keys():
    client = app.test_client()
    payload = client.get("/").get_json()
    assert payload["app"] == "cubiculum-magistri-app"
    assert "version" in payload
    assert "env" in payload
