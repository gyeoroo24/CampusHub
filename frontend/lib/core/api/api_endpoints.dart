/// Backend API endpoint routes matching FastAPI routers (/api/v1).
class ApiEndpoints {
  ApiEndpoints._();

  static const String version = '/api/v1';

  // --- Health & Canary ---
  static const String health = '$version/health';

  // --- Profile & Users ---
  static const String me = '$version/me';
  static String user(String id) => '$version/users/$id';
  static String userMakeAdmin(String id) => '$version/users/$id/make-admin';

  // --- File Uploads (S3 Presigned URLs) ---
  static const String uploads = '$version/uploads';

  // --- Categories ---
  static const String buySellCategories = '$version/buy-sell/categories';
  static const String lostFoundCategories = '$version/lost-found/categories';

  // --- Buy & Sell (FR-4, FR-5, FR-6, FR-10) ---
  static const String listings = '$version/listings';
  static String listing(String id) => '$version/listings/$id';
  static String listingStatus(String id) => '$version/listings/$id/status';
  static String listingPhotos(String id) => '$version/listings/$id/photos';

  // --- Lost & Found (FR-7, FR-8, FR-9, FR-10) ---
  // Lost Reports
  static const String lostReports = '$version/lost-reports';
  static String lostReport(String id) => '$version/lost-reports/$id';
  static String lostReportStatus(String id) => '$version/lost-reports/$id/status';
  static String lostReportPhotos(String id) => '$version/lost-reports/$id/photos';

  // Found Reports
  static const String foundReports = '$version/found-reports';
  static String foundReport(String id) => '$version/found-reports/$id';
  static String foundReportStatus(String id) => '$version/found-reports/$id/status';
  static String foundReportPhotos(String id) => '$version/found-reports/$id/photos';

  // --- Moderators & Roles ---
  static const String moderators = '$version/moderators';
  static String moderator(String id) => '$version/moderators/$id';

  // --- Reports & Content Moderation ---
  static const String reports = '$version/reports';
  static const String myReports = '$version/me/reports';
  static String resolveReport(String id) => '$version/reports/$id/resolve';

  // --- Notifications & Devices ---
  static const String notifications = '$version/me/notifications';
  static String notificationRead(String id) => '$version/me/notifications/$id/read';
  static const String notificationsReadAll = '$version/me/notifications/read-all';
  static const String devices = '$version/me/devices';

  // --- Academic Help ---
  static const String departments = '$version/departments';
  static String department(String id) => '$version/departments/$id';
  static String departmentCourses(String deptId) => '$version/departments/$deptId/courses';
  static String course(String id) => '$version/courses/$id';
  static String courseMaterials(String courseId) => '$version/courses/$courseId/materials';
  static String courseFeedback(String courseId) => '$version/courses/$courseId/feedback';
  static String courseSurvivalGuide(String courseId) => '$version/courses/$courseId/survival-guide';

  // --- Saved Searches & Alerts (rev 6) ---
  static const String savedSearches = '$version/me/saved-searches';
  static String savedSearch(String id) => '$version/me/saved-searches/$id';
  static String savedSearchSeen(String id) => '$version/me/saved-searches/$id/seen';

  // --- Wanted Posts (rev 6) ---
  static const String wanted = '$version/wanted';
  static String wantedPost(String id) => '$version/wanted/$id';
  static String wantedStatus(String id) => '$version/wanted/$id/status';
  static String wantedMatches(String id) => '$version/wanted/$id/matches';

  // --- Campus Services (rev 6) ---
  static const String campusServices = '$version/campus-services';
  static String campusService(String id) => '$version/campus-services/$id';

  // --- Backwards-compatible aliases ---
  static const String authMe = me;
  static const String mediaPresign = uploads;
  static const String buySellListings = listings;
  static String buySellListing(String id) => listing(id);
  static String buySellStatus(String id) => listingStatus(id);
  static const String lostFoundReports = lostReports;
  static String lostFoundReport(String id) => lostReport(id);
  static String lostFoundResolve(String id) => lostReportStatus(id);
}
