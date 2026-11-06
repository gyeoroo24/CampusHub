"""API Endpoints Catalog for CampusHub Load Testing.

Defines all 10 modules, endpoints, auth requirements, methods, read/write classification,
and task code templates used by the Locustfile generator.
"""
from dataclasses import dataclass
from typing import List, Dict, Optional


@dataclass
class Endpoint:
    id: str
    name: str
    module_id: str
    module_name: str
    method: str
    path: str
    requires_auth: bool
    is_write: bool
    default_weight: int
    description: str
    code_template: str


MODULES = [
    {"id": "core", "name": "1. System & Health"},
    {"id": "profile", "name": "2. Profile & Users"},
    {"id": "notifications", "name": "3. Notifications & Alerts"},
    {"id": "buysell", "name": "4. Buy & Sell Marketplace"},
    {"id": "academic", "name": "5. Academic Help"},
    {"id": "events_mess", "name": "6. Events & Mess Menus"},
    {"id": "lostfound", "name": "7. Lost & Found"},
    {"id": "placement", "name": "8. Placement Hub"},
    {"id": "chat", "name": "9. Messaging & Chat"},
    {"id": "moderation", "name": "10. Moderation & Trust"},
]

ENDPOINTS: List[Endpoint] = [
    # -------------------------------------------------------------------------
    # 1. CORE & HEALTH
    # -------------------------------------------------------------------------
    Endpoint(
        id="health",
        name="GET /api/v1/health",
        module_id="core",
        module_name="1. System & Health",
        method="GET",
        path="/api/v1/health",
        requires_auth=False,
        is_write=False,
        default_weight=10,
        description="Fast baseline healthcheck ping",
        code_template='''    @task({weight})
    def test_health(self):
        """GET /api/v1/health (Baseline Ping)"""
        self.client.get("/api/v1/health", name="[Core] GET /api/v1/health")'''
    ),
    Endpoint(
        id="campus_services",
        name="GET /api/v1/campus-services",
        module_id="core",
        module_name="1. System & Health",
        method="GET",
        path="/api/v1/campus-services",
        requires_auth=False,
        is_write=False,
        default_weight=4,
        description="Campus services landing directory",
        code_template='''    @task({weight})
    def test_campus_services(self):
        """GET /api/v1/campus-services (Landing Page Directory)"""
        self.client.get("/api/v1/campus-services", headers=self.headers, name="[Core] GET /api/v1/campus-services")'''
    ),

    # -------------------------------------------------------------------------
    # 2. PROFILE & USERS
    # -------------------------------------------------------------------------
    Endpoint(
        id="profile_me",
        name="GET /api/v1/me",
        module_id="profile",
        module_name="2. Profile & Users",
        method="GET",
        path="/api/v1/me",
        requires_auth=True,
        is_write=False,
        default_weight=10,
        description="Current user profile lookup",
        code_template='''    @task({weight})
    def test_get_me(self):
        """GET /api/v1/me (Profile inspection)"""
        if not self.has_auth:
            return
        self.client.get("/api/v1/me", headers=self.headers, name="[Profile] GET /api/v1/me")'''
    ),
    Endpoint(
        id="profile_posts",
        name="GET /api/v1/me/posts",
        module_id="profile",
        module_name="2. Profile & Users",
        method="GET",
        path="/api/v1/me/posts",
        requires_auth=True,
        is_write=False,
        default_weight=4,
        description="Comprehensive user history across modules",
        code_template='''    @task({weight})
    def test_get_my_posts(self):
        """GET /api/v1/me/posts (User activity history)"""
        if not self.has_auth:
            return
        self.client.get("/api/v1/me/posts", headers=self.headers, name="[Profile] GET /api/v1/me/posts")'''
    ),
    Endpoint(
        id="profile_bookmarks",
        name="GET /api/v1/me/bookmarks",
        module_id="profile",
        module_name="2. Profile & Users",
        method="GET",
        path="/api/v1/me/bookmarks",
        requires_auth=True,
        is_write=False,
        default_weight=4,
        description="Saved bookmarks across campus modules",
        code_template='''    @task({weight})
    def test_get_my_bookmarks(self):
        """GET /api/v1/me/bookmarks"""
        if not self.has_auth:
            return
        self.client.get("/api/v1/me/bookmarks", headers=self.headers, name="[Profile] GET /api/v1/me/bookmarks")'''
    ),
    Endpoint(
        id="profile_watched",
        name="GET /api/v1/me/watched-listings",
        module_id="profile",
        module_name="2. Profile & Users",
        method="GET",
        path="/api/v1/me/watched-listings",
        requires_auth=True,
        is_write=False,
        default_weight=4,
        description="Watched marketplace items",
        code_template='''    @task({weight})
    def test_get_my_watched_listings(self):
        """GET /api/v1/me/watched-listings"""
        if not self.has_auth:
            return
        self.client.get("/api/v1/me/watched-listings", headers=self.headers, name="[Profile] GET /api/v1/me/watched-listings")'''
    ),
    Endpoint(
        id="profile_followed_tags",
        name="GET /api/v1/me/followed-tags",
        module_id="profile",
        module_name="2. Profile & Users",
        method="GET",
        path="/api/v1/me/followed-tags",
        requires_auth=True,
        is_write=False,
        default_weight=3,
        description="Subscribed interest tags",
        code_template='''    @task({weight})
    def test_get_my_followed_tags(self):
        """GET /api/v1/me/followed-tags"""
        if not self.has_auth:
            return
        self.client.get("/api/v1/me/followed-tags", headers=self.headers, name="[Profile] GET /api/v1/me/followed-tags")'''
    ),
    Endpoint(
        id="users_lookup",
        name="GET /api/v1/users/lookup",
        module_id="profile",
        module_name="2. Profile & Users",
        method="GET",
        path="/api/v1/users/lookup",
        requires_auth=True,
        is_write=False,
        default_weight=3,
        description="Lookup IISc student info by email",
        code_template='''    @task({weight})
    def test_user_lookup(self):
        """GET /api/v1/users/lookup?email=..."""
        if not self.has_auth:
            return
        self.client.get(f"/api/v1/users/lookup?email={self.email}", headers=self.headers, name="[Users] GET /api/v1/users/lookup")'''
    ),
    Endpoint(
        id="users_search",
        name="GET /api/v1/users/search",
        module_id="profile",
        module_name="2. Profile & Users",
        method="GET",
        path="/api/v1/users/search",
        requires_auth=True,
        is_write=False,
        default_weight=3,
        description="Search students by name autocomplete",
        code_template='''    @task({weight})
    def test_user_search(self):
        """GET /api/v1/users/search?q=..."""
        if not self.has_auth:
            return
        self.client.get("/api/v1/users/search?q=Mukund", headers=self.headers, name="[Users] GET /api/v1/users/search")'''
    ),

    # -------------------------------------------------------------------------
    # 3. NOTIFICATIONS
    # -------------------------------------------------------------------------
    Endpoint(
        id="notifications_inbox",
        name="GET /api/v1/me/notifications",
        module_id="notifications",
        module_name="3. Notifications & Alerts",
        method="GET",
        path="/api/v1/me/notifications",
        requires_auth=True,
        is_write=False,
        default_weight=12,
        description="Student notification inbox stream",
        code_template='''    @task({weight})
    def test_notifications_inbox(self):
        """GET /api/v1/me/notifications?limit=15"""
        if not self.has_auth:
            return
        self.client.get("/api/v1/me/notifications?limit=15", headers=self.headers, name="[Alerts] GET /api/v1/me/notifications")'''
    ),

    # -------------------------------------------------------------------------
    # 4. BUY & SELL MARKETPLACE
    # -------------------------------------------------------------------------
    Endpoint(
        id="listings_feed",
        name="GET /api/v1/listings",
        module_id="buysell",
        module_name="4. Buy & Sell Marketplace",
        method="GET",
        path="/api/v1/listings",
        requires_auth=False,
        is_write=False,
        default_weight=25,
        description="Main marketplace feed with pagination",
        code_template='''    @task({weight})
    def test_listings_feed(self):
        """GET /api/v1/listings?limit=20 (Main marketplace feed)"""
        r = self.client.get("/api/v1/listings?limit=20", headers=self.headers, name="[BuySell] GET /api/v1/listings [Feed]")
        if r.status_code == 200:
            items = r.json().get("items", [])
            if items:
                self.discovered_listings = [i["id"] for i in items[:10]]'''
    ),
    Endpoint(
        id="listings_category",
        name="GET /api/v1/listings?category_id=...&limit=20",
        module_id="buysell",
        module_name="4. Buy & Sell Marketplace",
        method="GET",
        path="/api/v1/listings?category_id=...&limit=20",
        requires_auth=False,
        is_write=False,
        default_weight=15,
        description="Filter listings by category (paginated)",
        code_template='''    @task({weight})
    def test_listings_filter_category(self):
        """GET /api/v1/listings?category_id=...&limit=20"""
        cat_id = random.choice(CATEGORIES)
        self.client.get(f"/api/v1/listings?category_id={cat_id}&limit=20", headers=self.headers, name="[BuySell] GET /api/v1/listings [Filter Category]")'''
    ),
    Endpoint(
        id="listings_search",
        name="GET /api/v1/listings?search=...&limit=20",
        module_id="buysell",
        module_name="4. Buy & Sell Marketplace",
        method="GET",
        path="/api/v1/listings?search=...&limit=20",
        requires_auth=False,
        is_write=False,
        default_weight=12,
        description="Keyword search across titles (paginated)",
        code_template='''    @task({weight})
    def test_listings_search(self):
        """GET /api/v1/listings?search=...&limit=20"""
        keyword = random.choice(SEARCH_KEYWORDS)
        self.client.get(f"/api/v1/listings?search={keyword}&limit=20", headers=self.headers, name="[BuySell] GET /api/v1/listings [Search Keyword]")'''
    ),
    Endpoint(
        id="listings_price",
        name="GET /api/v1/listings?min_price=...&max_price=...&limit=20",
        module_id="buysell",
        module_name="4. Buy & Sell Marketplace",
        method="GET",
        path="/api/v1/listings?price_range",
        requires_auth=False,
        is_write=False,
        default_weight=6,
        description="Filter listings by budget range (paginated)",
        code_template='''    @task({weight})
    def test_listings_price_filter(self):
        """GET /api/v1/listings?min_price=100&max_price=2000&limit=20"""
        self.client.get("/api/v1/listings?min_price=100&max_price=2000&limit=20", headers=self.headers, name="[BuySell] GET /api/v1/listings [Price Filter]")'''
    ),
    Endpoint(
        id="listings_detail",
        name="GET /api/v1/listings/{id}",
        module_id="buysell",
        module_name="4. Buy & Sell Marketplace",
        method="GET",
        path="/api/v1/listings/{id}",
        requires_auth=False,
        is_write=False,
        default_weight=8,
        description="View full listing details",
        code_template='''    @task({weight})
    def test_listing_detail(self):
        """GET /api/v1/listings/{id}"""
        if self.discovered_listings:
            lid = random.choice(self.discovered_listings)
            self.client.get(f"/api/v1/listings/{lid}", headers=self.headers, name="[BuySell] GET /api/v1/listings/{id}")'''
    ),
    Endpoint(
        id="buysell_categories",
        name="GET /api/v1/buy-sell/categories",
        module_id="buysell",
        module_name="4. Buy & Sell Marketplace",
        method="GET",
        path="/api/v1/buy-sell/categories",
        requires_auth=False,
        is_write=False,
        default_weight=4,
        description="List all marketplace categories",
        code_template='''    @task({weight})
    def test_buy_sell_categories(self):
        """GET /api/v1/buy-sell/categories"""
        self.client.get("/api/v1/buy-sell/categories", headers=self.headers, name="[BuySell] GET /api/v1/buy-sell/categories")'''
    ),
    Endpoint(
        id="buysell_category_suggest",
        name="GET /api/v1/buy-sell/categories/suggest",
        module_id="buysell",
        module_name="4. Buy & Sell Marketplace",
        method="GET",
        path="/api/v1/buy-sell/categories/suggest",
        requires_auth=False,
        is_write=False,
        default_weight=4,
        description="AI/Rule suggestion for item category",
        code_template='''    @task({weight})
    def test_buy_sell_category_suggest(self):
        """GET /api/v1/buy-sell/categories/suggest?title=..."""
        self.client.get("/api/v1/buy-sell/categories/suggest?title=Hercules+Road+Bicycle", headers=self.headers, name="[BuySell] GET /api/v1/buy-sell/categories/suggest")'''
    ),
    Endpoint(
        id="wanted_feed",
        name="GET /api/v1/wanted?limit=20",
        module_id="buysell",
        module_name="4. Buy & Sell Marketplace",
        method="GET",
        path="/api/v1/wanted?limit=20",
        requires_auth=False,
        is_write=False,
        default_weight=4,
        description="Browse student wanted requests (paginated)",
        code_template='''    @task({weight})
    def test_wanted_feed(self):
        """GET /api/v1/wanted?limit=20 (Wanted requests feed)"""
        self.client.get("/api/v1/wanted?limit=20", headers=self.headers, name="[BuySell] GET /api/v1/wanted [Feed]")'''
    ),
    Endpoint(
        id="saved_searches",
        name="GET /api/v1/me/saved-searches",
        module_id="buysell",
        module_name="4. Buy & Sell Marketplace",
        method="GET",
        path="/api/v1/me/saved-searches",
        requires_auth=True,
        is_write=False,
        default_weight=3,
        description="User saved search queries",
        code_template='''    @task({weight})
    def test_saved_searches(self):
        """GET /api/v1/me/saved-searches"""
        if not self.has_auth:
            return
        self.client.get("/api/v1/me/saved-searches", headers=self.headers, name="[BuySell] GET /api/v1/me/saved-searches")'''
    ),
    Endpoint(
        id="watch_listing",
        name="PUT /api/v1/listings/{id}/watch",
        module_id="buysell",
        module_name="4. Buy & Sell Marketplace",
        method="PUT",
        path="/api/v1/listings/{id}/watch",
        requires_auth=True,
        is_write=True,
        default_weight=4,
        description="Watch or unwatch listing for price updates",
        code_template='''    @task({weight})
    def test_watch_listing(self):
        """PUT /api/v1/listings/{id}/watch"""
        if not self.has_auth or not self.discovered_listings:
            return
        lid = random.choice(self.discovered_listings)
        with self.client.put(f"/api/v1/listings/{lid}/watch", headers=self.headers, name="[BuySell] PUT /api/v1/listings/{id}/watch", catch_response=True) as resp:
            if resp.status_code in (200, 204, 201):
                resp.success()
            else:
                resp.failure(f"Watch failed: {resp.status_code}")'''
    ),
    Endpoint(
        id="create_listing",
        name="POST /api/v1/listings",
        module_id="buysell",
        module_name="4. Buy & Sell Marketplace",
        method="POST",
        path="/api/v1/listings",
        requires_auth=True,
        is_write=True,
        default_weight=3,
        description="Create [LOAD_TEST] marketplace listing",
        code_template='''    @task({weight})
    def test_create_listing(self):
        """POST /api/v1/listings (Tagged [LOAD_TEST])"""
        if not self.has_auth:
            return
        cat_id = random.choice(CATEGORIES)
        payload = {
            "title": f"[LOAD_TEST] Item {random.randint(10000, 99999)}",
            "price": random.randint(100, 3500),
            "category_id": cat_id,
            "description": "Created automatically by Locust performance harness [LOAD_TEST]",
            "location": random.choice(["CDS", "CSA", "Hostel", "Main Gate", "Gymkhana"]),
            "negotiable": random.choice([True, False]),
            "photo_keys": [],
        }
        self.client.post("/api/v1/listings", json=payload, headers=self.headers, name="[BuySell] POST /api/v1/listings [Create Item]")'''
    ),

    # -------------------------------------------------------------------------
    # 5. ACADEMIC HELP
    # -------------------------------------------------------------------------
    Endpoint(
        id="academic_departments",
        name="GET /api/v1/departments",
        module_id="academic",
        module_name="5. Academic Help",
        method="GET",
        path="/api/v1/departments",
        requires_auth=False,
        is_write=False,
        default_weight=6,
        description="List all IISc departments (Redis cached)",
        code_template='''    @task({weight})
    def test_departments(self):
        """GET /api/v1/departments"""
        self.client.get("/api/v1/departments", headers=self.headers, name="[Academic] GET /api/v1/departments")'''
    ),
    Endpoint(
        id="department_courses",
        name="GET /api/v1/departments/{id}/courses",
        module_id="academic",
        module_name="5. Academic Help",
        method="GET",
        path="/api/v1/departments/{id}/courses",
        requires_auth=False,
        is_write=False,
        default_weight=8,
        description="Courses under department (Redis cached)",
        code_template='''    @task({weight})
    def test_department_courses(self):
        """GET /api/v1/departments/{id}/courses"""
        self.client.get(f"/api/v1/departments/{CDS_DEPT_ID}/courses", headers=self.headers, name="[Academic] GET /api/v1/departments/{id}/courses")'''
    ),
    Endpoint(
        id="course_detail",
        name="GET /api/v1/courses/{id}",
        module_id="academic",
        module_name="5. Academic Help",
        method="GET",
        path="/api/v1/courses/{id}",
        requires_auth=False,
        is_write=False,
        default_weight=6,
        description="Course syllabus and description",
        code_template='''    @task({weight})
    def test_course_detail(self):
        """GET /api/v1/courses/{id}"""
        cid = random.choice(self.discovered_courses)
        self.client.get(f"/api/v1/courses/{cid}", headers=self.headers, name="[Academic] GET /api/v1/courses/{id}")'''
    ),
    Endpoint(
        id="course_feedback",
        name="GET /api/v1/courses/{id}/feedback?limit=15",
        module_id="academic",
        module_name="5. Academic Help",
        method="GET",
        path="/api/v1/courses/{id}/feedback",
        requires_auth=False,
        is_write=False,
        default_weight=12,
        description="Student feedback, ratings & reviews (paginated)",
        code_template='''    @task({weight})
    def test_course_feedback(self):
        """GET /api/v1/courses/{id}/feedback?limit=15"""
        cid = random.choice(self.discovered_courses)
        self.client.get(f"/api/v1/courses/{cid}/feedback?limit=15", headers=self.headers, name="[Academic] GET /api/v1/courses/{id}/feedback")'''
    ),
    Endpoint(
        id="course_my_feedback",
        name="GET /api/v1/courses/{id}/feedback/mine",
        module_id="academic",
        module_name="5. Academic Help",
        method="GET",
        path="/api/v1/courses/{id}/feedback/mine",
        requires_auth=True,
        is_write=False,
        default_weight=4,
        description="User's submitted course feedback",
        code_template='''    @task({weight})
    def test_course_my_feedback(self):
        """GET /api/v1/courses/{id}/feedback/mine"""
        if not self.has_auth:
            return
        cid = random.choice(self.discovered_courses)
        with self.client.get(f"/api/v1/courses/{cid}/feedback/mine", headers=self.headers, name="[Academic] GET /api/v1/courses/{id}/feedback/mine", catch_response=True) as resp:
            if resp.status_code in (200, 404):
                resp.success()
            else:
                resp.failure(f"Feedback/mine returned {resp.status_code}")'''
    ),
    Endpoint(
        id="course_materials",
        name="GET /api/v1/courses/{id}/materials?limit=20",
        module_id="academic",
        module_name="5. Academic Help",
        method="GET",
        path="/api/v1/courses/{id}/materials",
        requires_auth=False,
        is_write=False,
        default_weight=4,
        description="Notes, PYQs, and lecture material links (paginated)",
        code_template='''    @task({weight})
    def test_course_materials(self):
        """GET /api/v1/courses/{id}/materials?limit=20"""
        cid = random.choice(self.discovered_courses)
        self.client.get(f"/api/v1/courses/{cid}/materials?limit=20", headers=self.headers, name="[Academic] GET /api/v1/courses/{id}/materials")'''
    ),
    Endpoint(
        id="course_survival_guide",
        name="GET /api/v1/courses/{id}/survival-guide",
        module_id="academic",
        module_name="5. Academic Help",
        method="GET",
        path="/api/v1/courses/{id}/survival-guide",
        requires_auth=False,
        is_write=False,
        default_weight=4,
        description="Course survival guide and sentiment tips",
        code_template='''    @task({weight})
    def test_course_survival_guide(self):
        """GET /api/v1/courses/{id}/survival-guide"""
        cid = random.choice(self.discovered_courses)
        self.client.get(f"/api/v1/courses/{cid}/survival-guide", headers=self.headers, name="[Academic] GET /api/v1/courses/{id}/survival-guide")'''
    ),
    Endpoint(
        id="course_forum",
        name="GET /api/v1/courses/{id}/forum?limit=15",
        module_id="academic",
        module_name="5. Academic Help",
        method="GET",
        path="/api/v1/courses/{id}/forum",
        requires_auth=False,
        is_write=False,
        default_weight=3,
        description="Course Q&A discussions (paginated)",
        code_template='''    @task({weight})
    def test_course_forum(self):
        """GET /api/v1/courses/{id}/forum?limit=15"""
        cid = random.choice(self.discovered_courses)
        self.client.get(f"/api/v1/courses/{cid}/forum?limit=15", headers=self.headers, name="[Academic] GET /api/v1/courses/{id}/forum")'''
    ),
    Endpoint(
        id="follow_course",
        name="PUT /api/v1/courses/{id}/follow",
        module_id="academic",
        module_name="5. Academic Help",
        method="PUT",
        path="/api/v1/courses/{id}/follow",
        requires_auth=True,
        is_write=True,
        default_weight=2,
        description="Subscribe to course updates",
        code_template='''    @task({weight})
    def test_follow_course(self):
        """PUT /api/v1/courses/{id}/follow"""
        if not self.has_auth:
            return
        cid = random.choice(self.discovered_courses)
        with self.client.put(f"/api/v1/courses/{cid}/follow", headers=self.headers, name="[Academic] PUT /api/v1/courses/{id}/follow", catch_response=True) as resp:
            if resp.status_code in (200, 204):
                resp.success()
            else:
                resp.failure(f"Course follow failed: {resp.status_code}")'''
    ),

    # -------------------------------------------------------------------------
    # 6. COMMUNITY EVENTS & MESS MENUS
    # -------------------------------------------------------------------------
    Endpoint(
        id="events_feed",
        name="GET /api/v1/events?limit=20",
        module_id="events_mess",
        module_name="6. Events & Mess Menus",
        method="GET",
        path="/api/v1/events?limit=20",
        requires_auth=False,
        is_write=False,
        default_weight=10,
        description="Campus events feed (paginated)",
        code_template='''    @task({weight})
    def test_events_feed(self):
        """GET /api/v1/events?limit=20 (Community Events)"""
        r = self.client.get("/api/v1/events?limit=20", headers=self.headers, name="[Events] GET /api/v1/events?limit=20")
        if r.status_code == 200:
            items = r.json().get("items", [])
            if items:
                self.discovered_events = [e["id"] for e in items[:5]]'''
    ),
    Endpoint(
        id="events_upcoming",
        name="GET /api/v1/events?when=upcoming&limit=15",
        module_id="events_mess",
        module_name="6. Events & Mess Menus",
        method="GET",
        path="/api/v1/events?when=upcoming&limit=15",
        requires_auth=False,
        is_write=False,
        default_weight=5,
        description="Upcoming events this week (paginated)",
        code_template='''    @task({weight})
    def test_events_upcoming(self):
        """GET /api/v1/events?when=upcoming&limit=15"""
        self.client.get("/api/v1/events?when=upcoming&limit=15", headers=self.headers, name="[Events] GET /api/v1/events?when=upcoming&limit=15")'''
    ),
    Endpoint(
        id="events_detail",
        name="GET /api/v1/events/{id}",
        module_id="events_mess",
        module_name="6. Events & Mess Menus",
        method="GET",
        path="/api/v1/events/{id}",
        requires_auth=False,
        is_write=False,
        default_weight=4,
        description="Event detail and schedule",
        code_template='''    @task({weight})
    def test_event_detail(self):
        """GET /api/v1/events/{id}"""
        if self.discovered_events:
            eid = random.choice(self.discovered_events)
            self.client.get(f"/api/v1/events/{eid}", headers=self.headers, name="[Events] GET /api/v1/events/{id}")'''
    ),
    Endpoint(
        id="events_updates",
        name="GET /api/v1/events/{id}/updates",
        module_id="events_mess",
        module_name="6. Events & Mess Menus",
        method="GET",
        path="/api/v1/events/{id}/updates",
        requires_auth=False,
        is_write=False,
        default_weight=3,
        description="Announcements from event organizers",
        code_template='''    @task({weight})
    def test_event_updates(self):
        """GET /api/v1/events/{id}/updates"""
        if self.discovered_events:
            eid = random.choice(self.discovered_events)
            self.client.get(f"/api/v1/events/{eid}/updates", headers=self.headers, name="[Events] GET /api/v1/events/{id}/updates")'''
    ),
    Endpoint(
        id="events_tags",
        name="GET /api/v1/event-tags",
        module_id="events_mess",
        module_name="6. Events & Mess Menus",
        method="GET",
        path="/api/v1/event-tags",
        requires_auth=False,
        is_write=False,
        default_weight=4,
        description="Directory of campus event tags",
        code_template='''    @task({weight})
    def test_event_tags(self):
        """GET /api/v1/event-tags"""
        self.client.get("/api/v1/event-tags", headers=self.headers, name="[Events] GET /api/v1/event-tags")'''
    ),
    Endpoint(
        id="messes_directory",
        name="GET /api/v1/messes",
        module_id="events_mess",
        module_name="6. Events & Mess Menus",
        method="GET",
        path="/api/v1/messes",
        requires_auth=False,
        is_write=False,
        default_weight=8,
        description="List all campus mess facilities",
        code_template='''    @task({weight})
    def test_messes_directory(self):
        """GET /api/v1/messes (Campus Messes)"""
        r = self.client.get("/api/v1/messes", headers=self.headers, name="[Mess] GET /api/v1/messes")
        if r.status_code == 200:
            items = r.json() if isinstance(r.json(), list) else r.json().get("items", [])
            if items:
                self.discovered_messes = [m["id"] for m in items[:5]]'''
    ),
    Endpoint(
        id="mess_menus",
        name="GET /api/v1/messes/{id}/menus",
        module_id="events_mess",
        module_name="6. Events & Mess Menus",
        method="GET",
        path="/api/v1/messes/{id}/menus",
        requires_auth=False,
        is_write=False,
        default_weight=6,
        description="Daily meal menus for mess",
        code_template='''    @task({weight})
    def test_mess_detail_menus(self):
        """GET /api/v1/messes/{id}/menus"""
        mid = random.choice(self.discovered_messes)
        self.client.get(f"/api/v1/messes/{mid}/menus", headers=self.headers, name="[Mess] GET /api/v1/messes/{id}/menus")'''
    ),
    Endpoint(
        id="follow_mess",
        name="PUT /api/v1/messes/{id}/follow",
        module_id="events_mess",
        module_name="6. Events & Mess Menus",
        method="PUT",
        path="/api/v1/messes/{id}/follow",
        requires_auth=True,
        is_write=True,
        default_weight=2,
        description="Follow mess facility for menu notifications",
        code_template='''    @task({weight})
    def test_follow_mess(self):
        """PUT /api/v1/messes/{id}/follow"""
        if not self.has_auth:
            return
        mid = random.choice(self.discovered_messes)
        with self.client.put(f"/api/v1/messes/{mid}/follow", headers=self.headers, name="[Mess] PUT /api/v1/messes/{id}/follow", catch_response=True) as resp:
            if resp.status_code in (200, 204):
                resp.success()
            else:
                resp.failure(f"Mess follow failed: {resp.status_code}")'''
    ),

    # -------------------------------------------------------------------------
    # 7. LOST & FOUND
    # -------------------------------------------------------------------------
    Endpoint(
        id="lost_reports",
        name="GET /api/v1/lost-reports?limit=20",
        module_id="lostfound",
        module_name="7. Lost & Found",
        method="GET",
        path="/api/v1/lost-reports?limit=20",
        requires_auth=False,
        is_write=False,
        default_weight=8,
        description="Browse recent lost item reports (paginated)",
        code_template='''    @task({weight})
    def test_lost_reports(self):
        """GET /api/v1/lost-reports?limit=20"""
        self.client.get("/api/v1/lost-reports?limit=20", headers=self.headers, name="[LostFound] GET /api/v1/lost-reports?limit=20")'''
    ),
    Endpoint(
        id="lost_reports_search",
        name="GET /api/v1/lost-reports?search=...&limit=20",
        module_id="lostfound",
        module_name="7. Lost & Found",
        method="GET",
        path="/api/v1/lost-reports?search=...&limit=20",
        requires_auth=False,
        is_write=False,
        default_weight=4,
        description="Search lost reports by keyword (paginated)",
        code_template='''    @task({weight})
    def test_lost_reports_search(self):
        """GET /api/v1/lost-reports?search=bottle&limit=20"""
        self.client.get("/api/v1/lost-reports?search=bottle&limit=20", headers=self.headers, name="[LostFound] GET /api/v1/lost-reports?search&limit=20")'''
    ),
    Endpoint(
        id="found_reports",
        name="GET /api/v1/found-reports?limit=20",
        module_id="lostfound",
        module_name="7. Lost & Found",
        method="GET",
        path="/api/v1/found-reports?limit=20",
        requires_auth=False,
        is_write=False,
        default_weight=6,
        description="Browse found item notices (paginated)",
        code_template='''    @task({weight})
    def test_found_reports(self):
        """GET /api/v1/found-reports?limit=20"""
        self.client.get("/api/v1/found-reports?limit=20", headers=self.headers, name="[LostFound] GET /api/v1/found-reports?limit=20")'''
    ),
    Endpoint(
        id="lost_found_categories",
        name="GET /api/v1/lost-found/categories",
        module_id="lostfound",
        module_name="7. Lost & Found",
        method="GET",
        path="/api/v1/lost-found/categories",
        requires_auth=False,
        is_write=False,
        default_weight=4,
        description="Item categories for lost & found",
        code_template='''    @task({weight})
    def test_lost_found_categories(self):
        """GET /api/v1/lost-found/categories"""
        self.client.get("/api/v1/lost-found/categories", headers=self.headers, name="[LostFound] GET /api/v1/lost-found/categories")'''
    ),
    Endpoint(
        id="lost_found_suggest",
        name="GET /api/v1/lost-found/categories/suggest",
        module_id="lostfound",
        module_name="7. Lost & Found",
        method="GET",
        path="/api/v1/lost-found/categories/suggest",
        requires_auth=False,
        is_write=False,
        default_weight=3,
        description="Suggest category from item description",
        code_template='''    @task({weight})
    def test_lost_found_suggest(self):
        """GET /api/v1/lost-found/categories/suggest?title=..."""
        self.client.get("/api/v1/lost-found/categories/suggest?title=Lost+blue+water+bottle+near+library", headers=self.headers, name="[LostFound] GET /api/v1/lost-found/categories/suggest")'''
    ),
    Endpoint(
        id="create_lost_report",
        name="POST /api/v1/lost-reports",
        module_id="lostfound",
        module_name="7. Lost & Found",
        method="POST",
        path="/api/v1/lost-reports",
        requires_auth=True,
        is_write=True,
        default_weight=2,
        description="Post [LOAD_TEST] lost item report",
        code_template='''    @task({weight})
    def test_create_lost_report(self):
        """POST /api/v1/lost-reports (Tagged [LOAD_TEST])"""
        if not self.has_auth:
            return
        payload = {
            "title": f"[LOAD_TEST] Lost ID Card {random.randint(1000, 9999)}",
            "category_id": 1,
            "description": "Locust test report [LOAD_TEST]",
            "location_lost": "Main Library",
            "date_lost": "2026-11-06",
            "photo_keys": []
        }
        self.client.post("/api/v1/lost-reports", json=payload, headers=self.headers, name="[LostFound] POST /api/v1/lost-reports")'''
    ),

    # -------------------------------------------------------------------------
    # 8. PLACEMENT HUB
    # -------------------------------------------------------------------------
    Endpoint(
        id="placement_companies",
        name="GET /api/v1/companies?limit=20",
        module_id="placement",
        module_name="8. Placement Hub",
        method="GET",
        path="/api/v1/companies?limit=20",
        requires_auth=False,
        is_write=False,
        default_weight=8,
        description="Participating companies directory (paginated & sorted)",
        code_template='''    @task({weight})
    def test_placement_companies(self):
        """GET /api/v1/companies?limit=20 (Company Directory)"""
        sort_mode = random.choice(["name", "most_hired", "highest_pay"])
        r = self.client.get(f"/api/v1/companies?limit=20&sort={sort_mode}", headers=self.headers, name="[Placement] GET /api/v1/companies?limit=20")
        if r.status_code == 200:
            data = r.json()
            items = data.get("items", []) if isinstance(data, dict) else (data if isinstance(data, list) else [])
            if items:
                self.discovered_companies = [c["id"] for c in items[:10]]'''
    ),
    Endpoint(
        id="company_detail",
        name="GET /api/v1/companies/{id}",
        module_id="placement",
        module_name="8. Placement Hub",
        method="GET",
        path="/api/v1/companies/{id}",
        requires_auth=False,
        is_write=False,
        default_weight=4,
        description="Company profile and JD requirements",
        code_template='''    @task({weight})
    def test_company_detail(self):
        """GET /api/v1/companies/{id}"""
        if self.discovered_companies:
            cid = random.choice(self.discovered_companies)
            self.client.get(f"/api/v1/companies/{cid}", headers=self.headers, name="[Placement] GET /api/v1/companies/{id}")'''
    ),
    Endpoint(
        id="company_hiring_stats",
        name="GET /api/v1/companies/{id}/hiring-stats",
        module_id="placement",
        module_name="8. Placement Hub",
        method="GET",
        path="/api/v1/companies/{id}/hiring-stats",
        requires_auth=False,
        is_write=False,
        default_weight=4,
        description="Annual hiring counts and packages",
        code_template='''    @task({weight})
    def test_company_hiring_stats(self):
        """GET /api/v1/companies/{id}/hiring-stats"""
        if self.discovered_companies:
            cid = random.choice(self.discovered_companies)
            self.client.get(f"/api/v1/companies/{cid}/hiring-stats", headers=self.headers, name="[Placement] GET /api/v1/companies/{id}/hiring-stats")'''
    ),
    Endpoint(
        id="company_seniors",
        name="GET /api/v1/companies/{id}/seniors?limit=20",
        module_id="placement",
        module_name="8. Placement Hub",
        method="GET",
        path="/api/v1/companies/{id}/seniors",
        requires_auth=False,
        is_write=False,
        default_weight=4,
        description="Placed IISc alumni for networking (paginated)",
        code_template='''    @task({weight})
    def test_company_seniors(self):
        """GET /api/v1/companies/{id}/seniors?limit=20"""
        if self.discovered_companies:
            cid = random.choice(self.discovered_companies)
            self.client.get(f"/api/v1/companies/{cid}/seniors?limit=20", headers=self.headers, name="[Placement] GET /api/v1/companies/{id}/seniors")'''
    ),
    Endpoint(
        id="company_forum",
        name="GET /api/v1/companies/{id}/forum?limit=15",
        module_id="placement",
        module_name="8. Placement Hub",
        method="GET",
        path="/api/v1/companies/{id}/forum",
        requires_auth=False,
        is_write=False,
        default_weight=3,
        description="Company interview discussions (paginated)",
        code_template='''    @task({weight})
    def test_company_forum(self):
        """GET /api/v1/companies/{id}/forum?limit=15"""
        if self.discovered_companies:
            cid = random.choice(self.discovered_companies)
            self.client.get(f"/api/v1/companies/{cid}/forum?limit=15", headers=self.headers, name="[Placement] GET /api/v1/companies/{id}/forum")'''
    ),
    Endpoint(
        id="placement_stats",
        name="GET /api/v1/placement/stats",
        module_id="placement",
        module_name="8. Placement Hub",
        method="GET",
        path="/api/v1/placement/stats",
        requires_auth=False,
        is_write=False,
        default_weight=5,
        description="Season hiring trends and top recruiters",
        code_template='''    @task({weight})
    def test_placement_stats(self):
        """GET /api/v1/placement/stats (Hiring insights)"""
        self.client.get("/api/v1/placement/stats", headers=self.headers, name="[Placement] GET /api/v1/placement/stats")'''
    ),
    Endpoint(
        id="placement_interviews",
        name="GET /api/v1/interviews?limit=15",
        module_id="placement",
        module_name="8. Placement Hub",
        method="GET",
        path="/api/v1/interviews?limit=15",
        requires_auth=False,
        is_write=False,
        default_weight=5,
        description="Student interview experience archive (paginated)",
        code_template='''    @task({weight})
    def test_placement_interviews(self):
        """GET /api/v1/interviews?limit=15 (Interview Experiences)"""
        r = self.client.get("/api/v1/interviews?limit=15", headers=self.headers, name="[Placement] GET /api/v1/interviews?limit=15")
        if r.status_code == 200:
            data = r.json()
            items = data.get("items", []) if isinstance(data, dict) else (data if isinstance(data, list) else [])
            if items:
                self.discovered_interviews = [i["id"] for i in items[:10]]'''
    ),
    Endpoint(
        id="interview_detail",
        name="GET /api/v1/interviews/{id}",
        module_id="placement",
        module_name="8. Placement Hub",
        method="GET",
        path="/api/v1/interviews/{id}",
        requires_auth=False,
        is_write=False,
        default_weight=3,
        description="Detailed interview questions and tips",
        code_template='''    @task({weight})
    def test_interview_detail(self):
        """GET /api/v1/interviews/{id}"""
        if self.discovered_interviews:
            iid = random.choice(self.discovered_interviews)
            self.client.get(f"/api/v1/interviews/{iid}", headers=self.headers, name="[Placement] GET /api/v1/interviews/{id}")'''
    ),
    Endpoint(
        id="placement_ppts",
        name="GET /api/v1/placement/ppts?limit=20",
        module_id="placement",
        module_name="8. Placement Hub",
        method="GET",
        path="/api/v1/placement/ppts?limit=20",
        requires_auth=False,
        is_write=False,
        default_weight=4,
        description="Pre-placement talks and test schedule (paginated)",
        code_template='''    @task({weight})
    def test_placement_ppts(self):
        """GET /api/v1/placement/ppts?limit=20 (Pre-placement talks)"""
        self.client.get("/api/v1/placement/ppts?limit=20", headers=self.headers, name="[Placement] GET /api/v1/placement/ppts?limit=20")'''
    ),
    Endpoint(
        id="create_interview",
        name="POST /api/v1/companies/{id}/interviews",
        module_id="placement",
        module_name="8. Placement Hub",
        method="POST",
        path="/api/v1/companies/{id}/interviews",
        requires_auth=True,
        is_write=True,
        default_weight=2,
        description="Post [LOAD_TEST] interview experience",
        code_template='''    @task({weight})
    def test_post_interview_experience(self):
        """POST /api/v1/companies/{id}/interviews (Tagged [LOAD_TEST])"""
        if not self.has_auth or not self.discovered_companies:
            return
        cid = random.choice(self.discovered_companies)
        payload = {
            "role_title": f"[LOAD_TEST] Software Engineer {random.randint(100, 999)}",
            "year": 2026,
            "rounds_count": 3,
            "difficulty": "medium",
            "outcome": "offered",
            "content": "Locust test interview questions and tips [LOAD_TEST]",
            "compensation": "32 LPA"
        }
        self.client.post(f"/api/v1/companies/{cid}/interviews", json=payload, headers=self.headers, name="[Placement] POST /api/v1/companies/{id}/interviews")'''
    ),

    # -------------------------------------------------------------------------
    # 9. MESSAGING & CHAT
    # -------------------------------------------------------------------------
    Endpoint(
        id="chat_conversations",
        name="GET /api/v1/chat/conversations?limit=20",
        module_id="chat",
        module_name="9. Messaging & Chat",
        method="GET",
        path="/api/v1/chat/conversations",
        requires_auth=True,
        is_write=False,
        default_weight=5,
        description="Direct message thread list (paginated)",
        code_template='''    @task({weight})
    def test_chat_conversations(self):
        """GET /api/v1/chat/conversations?limit=20"""
        if not self.has_auth:
            return
        r = self.client.get("/api/v1/chat/conversations?limit=20", headers=self.headers, name="[Chat] GET /api/v1/chat/conversations")
        if r.status_code == 200:
            items = r.json() if isinstance(r.json(), list) else r.json().get("items", [])
            if items:
                self.discovered_conversations = [c["id"] for c in items[:5]]'''
    ),
    Endpoint(
        id="chat_unread",
        name="GET /api/v1/chat/unread",
        module_id="chat",
        module_name="9. Messaging & Chat",
        method="GET",
        path="/api/v1/chat/unread",
        requires_auth=True,
        is_write=False,
        default_weight=5,
        description="Unread messages count badge",
        code_template='''    @task({weight})
    def test_chat_unread(self):
        """GET /api/v1/chat/unread"""
        if not self.has_auth:
            return
        self.client.get("/api/v1/chat/unread", headers=self.headers, name="[Chat] GET /api/v1/chat/unread")'''
    ),
    Endpoint(
        id="chat_blocks",
        name="GET /api/v1/chat/blocks",
        module_id="chat",
        module_name="9. Messaging & Chat",
        method="GET",
        path="/api/v1/chat/blocks",
        requires_auth=True,
        is_write=False,
        default_weight=2,
        description="Blocked users list",
        code_template='''    @task({weight})
    def test_chat_blocks(self):
        """GET /api/v1/chat/blocks"""
        if not self.has_auth:
            return
        self.client.get("/api/v1/chat/blocks", headers=self.headers, name="[Chat] GET /api/v1/chat/blocks")'''
    ),
    Endpoint(
        id="conversation_detail",
        name="GET /api/v1/chat/conversations/{id}",
        module_id="chat",
        module_name="9. Messaging & Chat",
        method="GET",
        path="/api/v1/chat/conversations/{id}",
        requires_auth=True,
        is_write=False,
        default_weight=3,
        description="Conversation participant metadata",
        code_template='''    @task({weight})
    def test_conversation_detail(self):
        """GET /api/v1/chat/conversations/{id}"""
        if not self.has_auth or not self.discovered_conversations:
            return
        cid = random.choice(self.discovered_conversations)
        self.client.get(f"/api/v1/chat/conversations/{cid}", headers=self.headers, name="[Chat] GET /api/v1/chat/conversations/{id}")'''
    ),
    Endpoint(
        id="conversation_messages",
        name="GET /api/v1/chat/conversations/{id}/messages?limit=25",
        module_id="chat",
        module_name="9. Messaging & Chat",
        method="GET",
        path="/api/v1/chat/conversations/{id}/messages",
        requires_auth=True,
        is_write=False,
        default_weight=3,
        description="Message history for thread (paginated)",
        code_template='''    @task({weight})
    def test_conversation_messages(self):
        """GET /api/v1/chat/conversations/{id}/messages?limit=25"""
        if not self.has_auth or not self.discovered_conversations:
            return
        cid = random.choice(self.discovered_conversations)
        self.client.get(f"/api/v1/chat/conversations/{cid}/messages?limit=25", headers=self.headers, name="[Chat] GET /api/v1/chat/conversations/{id}/messages")'''
    ),

    # -------------------------------------------------------------------------
    # 10. MODERATION & TRUST
    # -------------------------------------------------------------------------
    Endpoint(
        id="reports_queue",
        name="GET /api/v1/reports?limit=20",
        module_id="moderation",
        module_name="10. Moderation & Trust",
        method="GET",
        path="/api/v1/reports",
        requires_auth=True,
        is_write=False,
        default_weight=6,
        description="Moderator flagged reports queue (paginated)",
        code_template='''    @task({weight})
    def test_moderator_reports_queue(self):
        """GET /api/v1/reports?limit=20 (Moderation review queue)"""
        if not self.has_auth:
            return
        with self.client.get("/api/v1/reports?limit=20", headers=self.headers, name="[Moderation] GET /api/v1/reports", catch_response=True) as resp:
            if resp.status_code in (200, 403):
                resp.success()
            else:
                resp.failure(f"Unexpected status code: {resp.status_code}")'''
    ),
    Endpoint(
        id="my_submitted_reports",
        name="GET /api/v1/me/reports",
        module_id="moderation",
        module_name="10. Moderation & Trust",
        method="GET",
        path="/api/v1/me/reports",
        requires_auth=True,
        is_write=False,
        default_weight=3,
        description="Student's own submitted reports",
        code_template='''    @task({weight})
    def test_my_submitted_reports(self):
        """GET /api/v1/me/reports (Student submitted reports)"""
        if not self.has_auth:
            return
        self.client.get("/api/v1/me/reports", headers=self.headers, name="[Reports] GET /api/v1/me/reports")'''
    ),
    Endpoint(
        id="moderators_directory",
        name="GET /api/v1/moderators",
        module_id="moderation",
        module_name="10. Moderation & Trust",
        method="GET",
        path="/api/v1/moderators",
        requires_auth=True,
        is_write=False,
        default_weight=4,
        description="Active appointed student moderators",
        code_template='''    @task({weight})
    def test_moderators_directory(self):
        """GET /api/v1/moderators (Directory of appointed moderators)"""
        if not self.has_auth:
            return
        with self.client.get("/api/v1/moderators", headers=self.headers, name="[Moderation] GET /api/v1/moderators", catch_response=True) as resp:
            if resp.status_code in (200, 403):
                resp.success()
            else:
                resp.failure(f"Unexpected status code: {resp.status_code}")'''
    ),
    Endpoint(
        id="seller_strikes_queue",
        name="GET /api/v1/seller-strikes",
        module_id="moderation",
        module_name="10. Moderation & Trust",
        method="GET",
        path="/api/v1/seller-strikes",
        requires_auth=True,
        is_write=False,
        default_weight=4,
        description="Trust & safety strikes moderation review",
        code_template='''    @task({weight})
    def test_seller_strikes_queue(self):
        """GET /api/v1/seller-strikes (Trust & Safety violations queue)"""
        if not self.has_auth:
            return
        with self.client.get("/api/v1/seller-strikes", headers=self.headers, name="[Moderation] GET /api/v1/seller-strikes", catch_response=True) as resp:
            if resp.status_code in (200, 403):
                resp.success()
            else:
                resp.failure(f"Unexpected status code: {resp.status_code}")'''
    ),
    Endpoint(
        id="my_seller_strikes_summary",
        name="GET /api/v1/me/seller-strikes/summary",
        module_id="moderation",
        module_name="10. Moderation & Trust",
        method="GET",
        path="/api/v1/me/seller-strikes/summary",
        requires_auth=True,
        is_write=False,
        default_weight=3,
        description="Student seller reputation score",
        code_template='''    @task({weight})
    def test_my_seller_strikes_summary(self):
        """GET /api/v1/me/seller-strikes/summary (Student seller trust score)"""
        if not self.has_auth:
            return
        self.client.get("/api/v1/me/seller-strikes/summary", headers=self.headers, name="[Trust] GET /api/v1/me/seller-strikes/summary")'''
    ),
    Endpoint(
        id="my_seller_strikes",
        name="GET /api/v1/me/seller-strikes",
        module_id="moderation",
        module_name="10. Moderation & Trust",
        method="GET",
        path="/api/v1/me/seller-strikes",
        requires_auth=True,
        is_write=False,
        default_weight=2,
        description="Personal strike history",
        code_template='''    @task({weight})
    def test_my_seller_strikes(self):
        """GET /api/v1/me/seller-strikes (Student strike history)"""
        if not self.has_auth:
            return
        self.client.get("/api/v1/me/seller-strikes", headers=self.headers, name="[Trust] GET /api/v1/me/seller-strikes")'''
    ),
]

ENDPOINTS_MAP: Dict[str, Endpoint] = {ep.id: ep for ep in ENDPOINTS}
