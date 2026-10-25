# Step 17: Saved Searches, Wanted Posts, Campus Services & Course Survival Guide Report

**Timestamp:** 2026-10-25T00:30:00+05:30
**Status:** Complete & Verified
**TestSuite:** 65/65 Tests Passing • 0 Flutter Analyze Issues
**Backend:** needs branch `backend_v2` (schema rev 6, 88 endpoints)

---

## 1. Executive Summary

Frontend for four ideas from "CampusHub: Taking It Further", whose backend landed on `backend_v2`:

1. **Saved searches & alerts:** "Save this search" on the Buy & Sell and Lost & Found toolbars, a notification bell with an unread badge and inbox (the app had none), and a saved-searches manager.
2. **Wanted posts:** a **For sale | Wanted** switch in Buy & Sell, a Wanted feed, a "Post Wanted" form, and a detail dialog listing the listings that already match.
3. **Campus services:** an app-bar button opening Health Centre, Wellness Centre, emergency and grievance links (tap to open or call), plus a **Campus Services** tab in the admin panel.
4. **Course survival guide:** a new **Courses** tab (department → course) opening `/courses/:id` with the guide: summary, sentiment-over-time chart, themes, repeated advice, semester cards, recent feedback and "Share your feedback".

Every feature has an API repository and a mock repository, so `USE_MOCK=true` (the default) still works offline.

---

## 2. Where things are

| Feature | New files | Hooked into |
| :--- | :--- | :--- |
| Alerts | `features/alerts/` (models, `alerts_repository.dart`, providers, `save_search_dialog.dart`, `saved_searches_dialog.dart`, `notifications_button.dart`) | `buy_sell_feed_screen.dart` and `lost_found_filter_bar.dart` (bell-plus icon in the toolbar); `app_router.dart` (bell) |
| Wanted | `features/wanted/` (model, repository, providers, `wanted_feed_sliver.dart`, `create_wanted_dialog.dart`, `wanted_detail_dialog.dart`) | `buy_sell_feed_screen.dart` (switch, Post Wanted button/FAB), `buy_sell_providers.dart` (`buySellSectionProvider`), profile "Wanted Posts" tab |
| Campus services | `features/campus_services/` (model, repository, providers, `campus_services_dialog.dart`, `campus_services_admin_panel.dart`) | `app_router.dart` (button), `admin_controls_screen.dart` (6th tab) |
| Survival guide | `features/academics/` (models, repository, providers, `courses_screen.dart`, `course_guide_screen.dart`, `sentiment_trend_chart.dart`) | `app_router.dart` (Courses tab, `/courses/:id` route) |
| Shared | `core/utils/error_text.dart`; new routes in `api_endpoints.dart`; `url_launcher` in `pubspec.yaml` | Refresh button also reloads the new data |

---

## 3. Behaviour worth knowing

- **Inbox:** refreshed every 60 s while signed in and whenever the bell is opened. Tapping a `saved_search_match` / `wanted_post_match` opens the listing; a found-item alert opens the found report. Items removed since show "Listing not found."
- **Saved search → results:** sets the feed's filters (query, category, price, Available only), switches tab, and calls `/seen` to clear the "N new" badge.
- **Category names:** the feeds filter by category *name* while the API wants an id, so the dialogs look the id up in the server's categories. A preset chip with no server category (e.g. "Lab Equipment" on a fresh database) is saved without a category, and the dialog says so. Category chips now compare names case-insensitively (the server had `books` while the chip says `Books`).
- **Wanted feed** shares the Buy & Sell search box and category chips; "Show closed" adds fulfilled and closed posts.
- **Phones (≤750 px):** Campus services, the theme toggle and the Admin/Moderator panel moved into a ⋮ menu; with the two new buttons the search box had shrunk to an icon.
- **Chart:** one line on a fixed −1…+1 axis with a neutral zero line; hover a point for term, score and review count; the in-progress semester is hollow and dashed. The semester cards repeat the numbers as text.

---

## 4. Verification

```bash
flutter analyze   # No issues found!
flutter test      # 00:03 +65: All tests passed!  (52 existing + 13 in test/taking_it_further_test.dart)
flutter build web --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://localhost:8000
```

Checked in a browser against the local `backend_v2` server with the seeded data (`scripts/seed_dummy_data.py`), signed in as `priya.iyer@iisc.ac.in`, at 1280×860 and 375×812: inbox and tap-through, saved-search results, Wanted feed and matches, Courses → DS 252 guide, campus services dialog, save-search dialog. A layout bug found by the new tests (course tiles 8 px too short for two-line names) was fixed.

---

## 5. Not done

- Lost & Found has no Wanted-style "looking for" posts; only saved searches cover found items.
- Academic Help beyond the guide (materials, forums, moderation of feedback) is still not in the app.
- Real push notifications: the backend only logs pushes, so alerts arrive through the in-app inbox.
