import pytest

from .conftest import ADMIN, API, ASHA, KIRAN, MEERA, RAVI, as_user, grant, make_admin, sign_in, sql, upload

DEPTMOD = as_user("deptmod@iisc.ac.in", "DeptMod")


@pytest.fixture
def campus(client):
    """CSA department with E0 243, CDS department with DS 252; DeptMod moderates CSA; Ravi moderates E0 243."""
    make_admin(client, ADMIN)
    for h in (DEPTMOD, RAVI, ASHA, MEERA, KIRAN):
        sign_in(client, h)
    csa = client.post(f"{API}/departments", headers=ADMIN, json={"name": "CSA"}).json()
    cds = client.post(f"{API}/departments", headers=ADMIN, json={"name": "CDS"}).json()
    hpca = client.post(f"{API}/departments/{csa['id']}/courses", headers=ADMIN,
                       json={"code": "E0 243", "name": "HPCA"}).json()
    cloud = client.post(f"{API}/departments/{cds['id']}/courses", headers=ADMIN,
                        json={"code": "DS 252", "name": "Cloud Computing"}).json()
    assert grant(client, ADMIN, "deptmod@iisc.ac.in", "academic_help", "department",
                 department_id=csa["id"]).status_code == 201
    assert grant(client, DEPTMOD, "ravi@iisc.ac.in", "academic_help", "course",
                 course_id=hpca["id"]).status_code == 201
    return {"csa": csa, "cds": cds, "hpca": hpca, "cloud": cloud}


def test_only_admin_adds_departments(client):
    assert client.post(f"{API}/departments", headers=ASHA, json={"name": "EE"}).status_code == 403


def test_department_moderator_limits(client, campus):
    # can't grant in another department, can't create department moderators
    assert grant(client, DEPTMOD, "kiran@iisc.ac.in", "academic_help", "course",
                 course_id=campus["cloud"]["id"]).status_code == 403
    assert grant(client, DEPTMOD, "kiran@iisc.ac.in", "academic_help", "department",
                 department_id=campus["csa"]["id"]).status_code == 403
    # can add a course in their own department, not in another
    assert client.post(f"{API}/departments/{campus['csa']['id']}/courses", headers=DEPTMOD,
                       json={"code": "E0 271", "name": "Graphics"}).status_code == 201
    assert client.post(f"{API}/departments/{campus['cds']['id']}/courses", headers=DEPTMOD,
                       json={"code": "DS 200", "name": "X"}).status_code == 403


def test_course_moderator_manages_only_own_course_materials(client, s3, campus):
    """FR-13 + team decision: course moderators can also create materials."""
    hpca, cloud = campus["hpca"]["id"], campus["cloud"]["id"]
    assert client.get(f"{API}/courses/{hpca}").json()["has_content"] is False  # FR-11 "no data yet"
    key = upload(client, s3, RAVI, "course_material", b"%PDF-1.4", "application/pdf", course_id=hpca)
    r = client.post(f"{API}/courses/{hpca}/materials", headers=RAVI,
                    json={"title": "Lecture 1", "material_type": "slides", "s3_key": key})
    assert r.status_code == 201 and r.json()["download_url"]
    assert client.get(f"{API}/courses/{hpca}").json()["has_content"] is True
    # Ravi can't even get an upload ticket for another course
    r = client.post(f"{API}/uploads", headers=RAVI, json={
        "kind": "course_material", "content_type": "application/pdf", "size_bytes": 10,
        "checksum_sha256": "47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=", "course_id": cloud})
    assert r.status_code == 403
    material_id = r_id = client.get(f"{API}/courses/{hpca}/materials").json()["items"][0]["id"]
    assert client.patch(f"{API}/materials/{material_id}", headers=ASHA, json={"title": "x"}).status_code == 403
    assert client.patch(f"{API}/materials/{r_id}", headers=DEPTMOD, json={"title": "Lecture 1 (v2)"}).status_code == 200


def test_feedback_permissions(client, campus):
    """FR-12 and scenario 4: department moderators can edit anyone's feedback."""
    hpca = campus["hpca"]["id"]
    fb = client.post(f"{API}/courses/{hpca}/feedback", headers=ASHA, json={"content": "Tough but great"}).json()
    assert client.patch(f"{API}/feedback/{fb['id']}", headers=MEERA, json={"content": "x"}).status_code == 403
    assert client.patch(f"{API}/feedback/{fb['id']}", headers=RAVI, json={"content": "x"}).status_code == 403
    assert client.patch(f"{API}/feedback/{fb['id']}", headers=DEPTMOD,
                        json={"content": "Tough but great."}).status_code == 200
    assert client.delete(f"{API}/feedback/{fb['id']}", headers=ASHA).status_code == 204
    assert client.get(f"{API}/courses/{hpca}/feedback").json()["items"] == []


def test_forum_threads_order_and_notifications(client, campus):
    forum = client.get(f"{API}/courses/{campus['hpca']['id']}/forum").json()
    assert client.get(f"{API}/courses/{campus['hpca']['id']}/forum").json()["id"] == forum["id"]
    thread = client.post(f"{API}/forums/{forum['id']}/threads", headers=ASHA,
                         json={"title": "Is E0 243 hard?", "content": "Opening post"}).json()
    client.post(f"{API}/threads/{thread['id']}/comments", headers=MEERA, json={"content": "Yes"})
    client.post(f"{API}/threads/{thread['id']}/comments", headers=KIRAN, json={"content": "Start early"})
    detail = client.get(f"{API}/threads/{thread['id']}").json()
    assert [c["content"] for c in detail["comments"]] == ["Opening post", "Yes", "Start early"]
    assert detail["author"]["name"] == "Asha"
    # Asha got two reply notifications; Meera got one (Kiran's reply); Kiran none
    count = lambda h: len(client.get(f"{API}/me/notifications", headers=h).json()["items"])  # noqa: E731
    assert (count(ASHA), count(MEERA), count(KIRAN)) == (2, 1, 0)


def test_thread_deletion_rules(client, campus):
    forum = client.get(f"{API}/courses/{campus['hpca']['id']}/forum").json()
    thread = client.post(f"{API}/forums/{forum['id']}/threads", headers=ASHA,
                         json={"title": "Notes?", "content": "Anyone have notes?"}).json()
    client.post(f"{API}/threads/{thread['id']}/comments", headers=MEERA, json={"content": "Me"})
    assert client.delete(f"{API}/threads/{thread['id']}", headers=MEERA).status_code == 403
    assert client.patch(f"{API}/threads/{thread['id']}", headers=MEERA, json={"title": "x"}).status_code == 403
    # Ravi moderates E0 243, so he can remove it; all comments go with it
    assert client.delete(f"{API}/threads/{thread['id']}", headers=RAVI).status_code == 204
    assert client.get(f"{API}/threads/{thread['id']}").status_code == 404
    assert sql("SELECT count(*) AS n FROM comments WHERE thread_id = $1::uuid AND deleted_at IS NULL",
               thread["id"])[0]["n"] == 0


def test_deleting_course_removes_everything_under_it(client, s3, campus):
    hpca = campus["hpca"]["id"]
    forum = client.get(f"{API}/courses/{hpca}/forum").json()
    client.post(f"{API}/forums/{forum['id']}/threads", headers=ASHA, json={"title": "t", "content": "c"})
    client.post(f"{API}/courses/{hpca}/feedback", headers=ASHA, json={"content": "good"})
    assert client.delete(f"{API}/courses/{hpca}", headers=RAVI).status_code == 403  # course mod can't
    assert client.delete(f"{API}/courses/{hpca}", headers=DEPTMOD).status_code == 204
    counts = sql("""SELECT (SELECT count(*) FROM forums) AS forums, (SELECT count(*) FROM threads) AS threads,
                           (SELECT count(*) FROM comments) AS comments, (SELECT count(*) FROM course_feedback) AS fb,
                           (SELECT count(*) FROM moderator_assignments WHERE course_id IS NOT NULL) AS grants""")[0]
    assert dict(counts) == {"forums": 0, "threads": 0, "comments": 0, "fb": 0, "grants": 0}
