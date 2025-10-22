from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_ping():
    response = client.get("/api/ping")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}

def test_echo():
    response = client.post("/api/echo", json={"message": "Hi"})
    assert response.status_code == 200
    assert response.json() == {"echo": "Hi"}
