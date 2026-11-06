"""Deleting notifications: one, several, or all (only ever my own)."""
from .conftest import API, ASHA, RAVI, sign_in, sql


def _notify(user_id: str, n: int) -> list[str]:
    return [str(r["id"]) for r in sql(
        """INSERT INTO notifications (user_id, type, payload)
           SELECT $1::uuid, 'forum_reply', '{}' FROM generate_series(1, $2) RETURNING id""", user_id, n)]


def _mine(client, headers) -> list[str]:
    return [n["id"] for n in client.get(f"{API}/me/notifications", headers=headers).json()["items"]]


def test_delete_one_several_and_all(client):
    asha, ravi = sign_in(client, ASHA), sign_in(client, RAVI)
    a1, a2, a3, a4 = _notify(asha, 4)
    [r1] = _notify(ravi, 1)

    assert client.delete(f"{API}/me/notifications/{a1}").status_code == 401
    assert client.delete(f"{API}/me/notifications/{a1}", headers=ASHA).status_code == 204
    assert client.delete(f"{API}/me/notifications/{r1}", headers=ASHA).status_code == 204   # not hers: ignored
    assert _mine(client, RAVI) == [r1]

    r = client.post(f"{API}/me/notifications/delete", headers=ASHA, json={"ids": [a2, a3, r1]})
    assert r.json() == {"deleted": 2} and set(_mine(client, ASHA)) == {a4}
    assert client.post(f"{API}/me/notifications/delete", headers=ASHA, json={"ids": []}).status_code == 422

    _notify(asha, 2)
    assert client.delete(f"{API}/me/notifications", headers=ASHA).json() == {"deleted": 3}
    assert _mine(client, ASHA) == [] and _mine(client, RAVI) == [r1]
