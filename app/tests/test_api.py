def test_health(client):
    res = client.get("/api/health")
    assert res.status_code == 200
    assert res.get_json() == {"status": "ok"}


def test_ready_reaches_database(client):
    res = client.get("/api/ready")
    assert res.status_code == 200
    assert res.get_json()["database"] == "reachable"


def test_info(client):
    body = client.get("/api/info").get_json()
    assert set(body) == {"instance_id", "availability_zone", "version"}


def test_create_and_list(client):
    res = client.post("/api/notes", json={"title": "First", "content": "Hello"})
    assert res.status_code == 201
    note = res.get_json()
    assert note["id"] == 1
    assert note["title"] == "First"

    notes = client.get("/api/notes").get_json()
    assert [n["title"] for n in notes] == ["First"]


def test_create_requires_title(client):
    res = client.post("/api/notes", json={"title": "   ", "content": "x"})
    assert res.status_code == 400
    assert "Title" in res.get_json()["error"]


def test_create_rejects_non_json(client):
    res = client.post("/api/notes", data="not json", content_type="text/plain")
    assert res.status_code == 400


def test_title_length_limit(client):
    res = client.post("/api/notes", json={"title": "x" * 201})
    assert res.status_code == 400


def test_get_update_delete(client):
    note_id = client.post("/api/notes", json={"title": "Draft"}).get_json()["id"]

    assert client.get(f"/api/notes/{note_id}").get_json()["title"] == "Draft"

    res = client.put(f"/api/notes/{note_id}", json={"title": "Final", "content": "Done"})
    assert res.status_code == 200
    assert res.get_json()["content"] == "Done"

    assert client.delete(f"/api/notes/{note_id}").status_code == 204
    assert client.get(f"/api/notes/{note_id}").status_code == 404


def test_missing_note_returns_404(client):
    assert client.put("/api/notes/999", json={"title": "x"}).status_code == 404
    assert client.delete("/api/notes/999").status_code == 404


def test_sql_injection_is_stored_as_text(client):
    evil = "x'); DROP TABLE notes; --"
    client.post("/api/notes", json={"title": evil})
    notes = client.get("/api/notes").get_json()
    assert notes[0]["title"] == evil
