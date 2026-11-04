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


def test_moderators_remove_course_feedback_without_strikes(client, campus):
    """Course moderators remove feedback on their course; department moderators on any course in their
    department. Removing it never creates a seller strike (strikes are for Buy & Sell listings)."""
    hpca, cloud = campus["hpca"]["id"], campus["cloud"]["id"]
    fb = client.post(f"{API}/courses/{hpca}/feedback", headers=ASHA, json={"content": "Tough but great"}).json()
    other = client.post(f"{API}/courses/{cloud}/feedback", headers=KIRAN, json={"content": "Good"}).json()
    listed = client.get(f"{API}/courses/{hpca}/feedback", headers=RAVI).json()["items"]
    assert [f["can_remove"] for f in listed] == [True]
    assert client.get(f"{API}/courses/{hpca}/feedback", headers=KIRAN).json()["items"][0]["can_remove"] is False
    assert client.get(f"{API}/courses/{hpca}/feedback", headers=ASHA).json()["items"][0]["can_remove"] is True
    # Ravi moderates E0 243 only: not the other department's course.
    assert client.delete(f"{API}/feedback/{other['id']}", headers=RAVI).status_code == 403
    assert client.delete(f"{API}/feedback/{fb['id']}", headers=RAVI).status_code == 204
    # The department moderator (CSA) may remove feedback on E0 243, but not on DS 252 (CDS).
    fb = client.post(f"{API}/courses/{hpca}/feedback", headers=KIRAN, json={"content": "Heavy workload"}).json()
    assert client.delete(f"{API}/feedback/{other['id']}", headers=DEPTMOD).status_code == 403
    assert client.delete(f"{API}/feedback/{fb['id']}", headers=DEPTMOD).status_code == 204
    assert sql("SELECT count(*) FROM seller_strikes")[0][0] == 0
    assert sql("SELECT count(*) FROM moderation_log WHERE action = 'remove_course_feedback'")[0][0] == 2


def test_course_moderator_manages_only_own_course_materials(client, s3, campus):
    """FR-13: course moderators manage materials; others can't edit what they didn't share."""
    hpca, cloud = campus["hpca"]["id"], campus["cloud"]["id"]
    assert client.get(f"{API}/courses/{hpca}").json()["has_content"] is False  # FR-11 "no data yet"
    key = upload(client, s3, RAVI, "course_material", b"%PDF-1.4", "application/pdf", course_id=hpca)
    r = client.post(f"{API}/courses/{hpca}/materials", headers=RAVI,
                    json={"title": "Lecture 1", "material_type": "slides", "s3_key": key})
    assert r.status_code == 201 and r.json()["download_url"]
    assert client.get(f"{API}/courses/{hpca}").json()["has_content"] is True
    # Rev 22: materials are a shared repository, so anyone signed in gets an upload ticket for any course.
    r = client.post(f"{API}/uploads", headers=ASHA, json={
        "kind": "course_material", "content_type": "application/pdf", "size_bytes": 10,
        "checksum_sha256": "47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=", "course_id": cloud})
    assert r.status_code == 201
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


# ---------------------------------------------------------------- rev 22: shared repository and follows
def _zip(files: dict[str, bytes]) -> bytes:
    import io
    import zipfile
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        for name, data in files.items():
            zf.writestr(name, data)
    return buf.getvalue()


def _share(client, s3, headers, course_id, content, content_type, **body):
    key = upload(client, s3, headers, "course_material", content, content_type, course_id=course_id)
    return client.post(f"{API}/courses/{course_id}/materials", headers=headers, json={"s3_key": key} | body)


def test_anyone_shares_materials_and_followers_hear(client, s3, campus):
    hpca = campus["hpca"]["id"]
    assert client.put(f"{API}/courses/{hpca}/follow", headers=MEERA).json()["following"] is True
    assert client.get(f"{API}/courses/{hpca}", headers=MEERA).json()["follower_count"] == 1
    r = _share(client, s3, ASHA, hpca, b"%PDF-1.4 endsem 2025", "application/pdf",
               title="Endsem 2025", tags=["pyq", "solutions"], description="With worked answers",
               file_name="endsem-2025.pdf")
    assert r.status_code == 201, r.text
    m = r.json()
    assert (m["tags"], m["material_type"], m["held"], m["can_edit"], m["file_name"]) == \
        (["pyq", "solutions"], "exam_material", False, True, "endsem-2025.pdf")
    alerts = [n["payload"] for n in client.get(f"{API}/me/notifications", headers=MEERA).json()["items"]
              if n["type"] == "course_update"]
    assert alerts[0]["message"] == "E0 243: new material “Endsem 2025”"
    assert [x["id"] for x in client.get(f"{API}/courses/{hpca}/materials", params={"tag": "pyq"}).json()["items"]] == [m["id"]]
    # The uploader edits their own; someone else can't; the course moderator can.
    assert client.patch(f"{API}/materials/{m['id']}", headers=ASHA, json={"tags": ["quiz"]}).json()["tags"] == ["quiz"]
    assert client.patch(f"{API}/materials/{m['id']}", headers=KIRAN, json={"title": "x"}).status_code == 403
    assert client.delete(f"{API}/materials/{m['id']}", headers=RAVI).status_code == 204
    # Feedback and forum posts reach followers too; never the person who posted.
    client.post(f"{API}/courses/{hpca}/feedback", headers=KIRAN, json={"content": "Great course"})
    forum = client.get(f"{API}/courses/{hpca}/forum").json()
    client.post(f"{API}/forums/{forum['id']}/threads", headers=KIRAN, json={"title": "Midsem tips?", "content": "Any?"})
    messages = [n["payload"]["message"] for n in client.get(f"{API}/me/notifications", headers=MEERA).json()["items"]
                if n["type"] == "course_update"]
    assert "E0 243: new feedback posted" in messages and "E0 243: new forum post “Midsem tips?”" in messages
    assert not [n for n in client.get(f"{API}/me/notifications", headers=KIRAN).json()["items"]
                if n["type"] == "course_update"]
    assert client.delete(f"{API}/courses/{hpca}/follow", headers=MEERA).json()["following"] is False


@pytest.mark.parametrize("content, content_type, name, why", [
    (b"MZ\x90\x00 windows program", "application/pdf", "notes.pdf", "is a program"),
    (b"<html>not a pdf", "application/pdf", "notes.pdf", "isn't really a PDF"),
    (b"PK\x03\x04" + b"x" * 20, "application/zip", "x.zip", "damaged"),
    (None, "application/zip", "apps.zip", "Android app"),
    (None, "application/zip", "tools.zip", "programs or scripts"),
    (b"%PDF-1.4", "application/pdf", "cheat.apk", ".apk files"),
])
def test_programs_and_disguised_files_are_refused(client, s3, campus, content, content_type, name, why):
    if name == "apps.zip":
        content = _zip({"AndroidManifest.xml": b"<manifest/>", "classes.dex": b"dex\n035"})
    if name == "tools.zip":
        content = _zip({"readme.txt": b"hi", "setup.exe": b"MZ..."})
    r = _share(client, s3, ASHA, campus["hpca"]["id"], content, content_type, title="Notes", file_name=name)
    assert r.status_code == 422 and why in r.text, r.text
    assert client.get(f"{API}/courses/{campus['hpca']['id']}/materials").json()["items"] == []


def test_suspicious_uploads_are_held_for_moderators(client, s3, campus):
    hpca = campus["hpca"]["id"]
    nested = _zip({"week1/slides.pdf": b"%PDF-1.4", "old.zip": b"PK\x03\x04"})
    r = _share(client, s3, ASHA, hpca, nested, "application/zip", title="Leaked endsem paper, selling cheap")
    assert r.status_code == 201 and r.json()["held"] is True
    material = r.json()
    # Hidden from others, visible to the uploader and the course's moderator.
    assert client.get(f"{API}/courses/{hpca}/materials", headers=KIRAN).json()["items"] == []
    assert len(client.get(f"{API}/courses/{hpca}/materials", headers=ASHA).json()["items"]) == 1
    assert len(client.get(f"{API}/courses/{hpca}/materials", headers=RAVI).json()["items"]) == 1
    report = sql("SELECT reason, module::text FROM reports WHERE course_material_id = $1::uuid", material["id"])[0]
    assert report["module"] == "academic_help" and "archive inside the archive" in report["reason"]
    assert "Leaked" in report["reason"] or "leaked" in report["reason"].lower()
    # The moderator keeps it: it appears for everyone.
    report_id = sql("SELECT id FROM reports WHERE course_material_id = $1::uuid", material["id"])[0]["id"]
    r = client.post(f"{API}/reports/{report_id}/resolve", headers=RAVI, json={"action": "dismissed"})
    assert r.status_code == 200, r.text
    assert len(client.get(f"{API}/courses/{hpca}/materials", headers=KIRAN).json()["items"]) == 1


def test_macro_documents_are_refused():
    from app.material_check import Rejected, check_material
    docm = _zip({"[Content_Types].xml": b"x", "word/document.xml": b"x", "word/vbaProject.bin": b"x"})
    with pytest.raises(Rejected, match="macros"):
        check_material(docm, "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "a.docx")
    ok = _zip({"[Content_Types].xml": b"x", "word/document.xml": b"x"})
    assert check_material(ok, "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                          "a.docx").flags == []


def test_my_posts_lists_feedback_materials_companies_and_events(client, s3, campus):
    """GET /me/posts: my course feedback and materials; for moderators also the companies and events they
    added. Other people's posts and removed ones are left out."""
    hpca = campus["hpca"]["id"]
    client.post(f"{API}/courses/{hpca}/feedback", headers=ASHA, json={"content": "Loved it", "is_anonymous": True})
    client.post(f"{API}/courses/{hpca}/feedback", headers=KIRAN, json={"content": "Hard"})
    key = upload(client, s3, ASHA, "course_material", b"%PDF-1.4 notes", "application/pdf", course_id=hpca)
    r = client.post(f"{API}/courses/{hpca}/materials", headers=ASHA,
                    json={"title": "Week 1 notes", "tags": ["notes"], "s3_key": key})
    assert r.status_code == 201, r.text
    mine = client.get(f"{API}/me/posts", headers=ASHA).json()
    assert [(f["course_code"], f["content"], f["is_anonymous"]) for f in mine["feedback"]] == [("E0 243", "Loved it", True)]
    assert [(m["course_code"], m["title"]) for m in mine["materials"]] == [("E0 243", "Week 1 notes")]
    assert mine["companies"] == mine["events"] == mine["mess_menus"] == []

    assert grant(client, ADMIN, "meera@iisc.ac.in", "placement_hub").status_code == 201
    assert client.post(f"{API}/companies", headers=MEERA, json={"name": "Acme"}).status_code == 201
    csv = "Name,Industry\nGlobex,Software\nAcme,Retail\n"
    assert client.post(f"{API}/placement/companies/import", headers=MEERA, json={"csv": csv}).status_code == 201
    assert [c["name"] for c in client.get(f"{API}/me/posts", headers=MEERA).json()["companies"]] == ["Globex", "Acme"]
    assert client.get(f"{API}/me/posts", headers=KIRAN).json()["companies"] == []

    client.delete(f"{API}/materials/{r.json()['id']}", headers=ASHA)
    assert client.get(f"{API}/me/posts", headers=ASHA).json()["materials"] == []
    assert client.get(f"{API}/me/posts").status_code == 401
