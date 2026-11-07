/// Backend API endpoint routes matching FastAPI routers (/api/v1).
class ApiEndpoints {
  ApiEndpoints._();

  static const String version = '/api/v1';

  // --- Health & Canary ---
  static const String health = '$version/health';

  // --- Dev sign-in OTP (local dev only; Cognito handles this in production) ---
  static const String otpRequest = '$version/auth/otp/request';
  static const String otpVerify = '$version/auth/otp/verify';

  // --- Profile & Users ---
  static const String me = '$version/me';
  static const String meDeactivate = '$version/me/deactivate';
  static const String meReactivate = '$version/me/reactivate';
  static const String phoneCode = '$version/me/phone/code';
  static const String phoneVerify = '$version/me/phone/verify';
  static const String myPosts = '$version/me/posts';
  static String user(String id) => '$version/users/$id';
  static const String users = '$version/users';
  static const String userLookup = '$version/users/lookup';
  static String userMakeAdmin(String id) => '$version/users/$id/make-admin';

  // --- File Uploads (S3 Presigned URLs) ---
  static const String uploads = '$version/uploads';

  // --- Categories ---
  static const String buySellCategories = '$version/buy-sell/categories';
  static const String lostFoundCategories = '$version/lost-found/categories';
  static const String buySellCategorySuggest = '$version/buy-sell/categories/suggest';
  static const String lostFoundCategorySuggest = '$version/lost-found/categories/suggest';

  // --- Buy & Sell (FR-4, FR-5, FR-6, FR-10) ---
  static const String listings = '$version/listings';
  static String listing(String id) => '$version/listings/$id';
  static String listingStatus(String id) => '$version/listings/$id/status';
  static String listingWatch(String id) => '$version/listings/$id/watch';
  static const String myWatchedListings = '$version/me/watched-listings';
  static String listingBookmark(String id) => '$version/listings/$id/bookmark';
  static const String listingsLookup = '$version/listings/lookup';
  static const String myBookmarkedListings = '$version/me/bookmarked-listings';
  static const String myBookmarkedListingIds = '$version/me/bookmarked-listing-ids';
  static String listingPhotos(String id) => '$version/listings/$id/photos';

  // --- Seller trust score (future plan §1.5) ---
  static const String mySellerStrikes = '$version/me/seller-strikes';
  static const String mySellerStrikeSummary = '$version/me/seller-strikes/summary';
  static String appealSellerStrike(String id) => '$version/me/seller-strikes/$id/appeal';
  static const String sellerStrikes = '$version/seller-strikes';
  static String overturnSellerStrike(String id) => '$version/seller-strikes/$id/overturn';
  static String rejectSellerStrikeAppeal(String id) => '$version/seller-strikes/$id/reject-appeal';
  static String liftListingSuspension(String sellerId) => '$version/users/$sellerId/lift-listing-suspension';
  static const String mySellerUnblockRequest = '$version/me/seller-unblock-request';
  static const String sellerUnblockRequests = '$version/seller-unblock-requests';
  static String approveUnblockRequest(String id) => '$version/seller-unblock-requests/$id/approve';
  static String rejectUnblockRequest(String id) => '$version/seller-unblock-requests/$id/reject';
  static const String blockedSellers = '$version/blocked-sellers';
  static String unblockSeller(String sellerId) => '$version/users/$sellerId/unblock';

  // --- Lost & Found (FR-7, FR-8, FR-9, FR-10) ---
  // Lost Reports
  static const String lostReports = '$version/lost-reports';
  static String lostReport(String id) => '$version/lost-reports/$id';
  static String lostReportStatus(String id) => '$version/lost-reports/$id/status';
  static String lostReportPhotos(String id) => '$version/lost-reports/$id/photos';
  static String lostReportMatches(String id) => '$version/lost-reports/$id/matches';

  // Found Reports
  static const String foundReports = '$version/found-reports';
  static String foundReport(String id) => '$version/found-reports/$id';
  static String foundReportStatus(String id) => '$version/found-reports/$id/status';
  static String foundReportPhotos(String id) => '$version/found-reports/$id/photos';
  static String foundReportMatches(String id) => '$version/found-reports/$id/matches';

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
  static String notification(String id) => '$version/me/notifications/$id';
  static const String notificationsDelete = '$version/me/notifications/delete';
  static const String devices = '$version/me/devices';
  static const String pushConfig = '$version/me/push-config';

  // --- Academic Help ---
  static const String departments = '$version/departments';
  static String department(String id) => '$version/departments/$id';
  static String departmentCourses(String deptId) => '$version/departments/$deptId/courses';
  static String course(String id) => '$version/courses/$id';
  static String courseMaterials(String courseId) => '$version/courses/$courseId/materials';
  static String courseForum(String courseId) => '$version/courses/$courseId/forum';
  static String courseFollow(String courseId) => '$version/courses/$courseId/follow';
  static String material(String id) => '$version/materials/$id';
  static String courseFeedback(String courseId) => '$version/courses/$courseId/feedback';
  static String courseSurvivalGuide(String courseId) => '$version/courses/$courseId/survival-guide';
  static String myCourseFeedback(String courseId) => '$version/courses/$courseId/feedback/mine';
  static String feedback(String id) => '$version/feedback/$id';

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

  // --- Messages (end-to-end encrypted, rev 8) ---
  static const String myChatKey = '$version/me/chat-key';
  static String userChatKey(String userId) => '$version/users/$userId/chat-key';
  static const String chatConversations = '$version/chat/conversations';
  static const String chatUnread = '$version/chat/unread';
  static String chatConversation(String id) => '$version/chat/conversations/$id';
  static String chatMessages(String conversationId) => '$version/chat/conversations/$conversationId/messages';
  static String chatRead(String conversationId) => '$version/chat/conversations/$conversationId/read';
  static String chatMessage(String messageId) => '$version/chat/messages/$messageId';
  static String chatOffer(String messageId) => '$version/chat/messages/$messageId/offer';
  static String chatMessageHide(String messageId) => '$version/chat/messages/$messageId/hide';
  static const String userSearch = '$version/users/search';
  static const String chatBlocks = '$version/chat/blocks';
  static String chatBlock(String userId) => '$version/chat/blocks/$userId';

  // --- Placement Hub ---
  static const String companies = '$version/companies';
  static String company(String id) => '$version/companies/$id';
  static String companyHiringStats(String id) => '$version/companies/$id/hiring-stats';
  static String companyJds(String id) => '$version/companies/$id/jds';
  static String companyPpts(String id) => '$version/companies/$id/ppts';
  static String companyInterviews(String id) => '$version/companies/$id/interviews';
  static String companyForum(String id) => '$version/companies/$id/forum';
  static String companySeniors(String id) => '$version/companies/$id/seniors';
  static String senior(String id) => '$version/seniors/$id';
  static String placementRecordContactHidden(String id) => '$version/placement/records/$id/contact-hidden';
  static const String messes = '$version/messes';
  static String mess(int id) => '$version/messes/$id';
  static String messFollow(int id) => '$version/messes/$id/follow';
  static String messMenus(int id) => '$version/messes/$id/menus';
  static String messMenu(String id) => '$version/mess-menus/$id';
  static const String messMenusByName = '$version/mess-menus';
  static const String messMenuExtract = '$version/mess-menus/extract';
  static String jd(String id) => '$version/jds/$id';
  static String ppt(String id) => '$version/ppts/$id';
  static const String interviews = '$version/interviews';
  static String interview(String id) => '$version/interviews/$id';
  static const String placementStats = '$version/placement/stats';
  static const String placementPpts = '$version/placement/ppts';
  static const String placementImports = '$version/placement/imports';
  static const String placementCompaniesImport = '$version/placement/companies/import';
  static const String similarCompanies = '$version/placement/companies/similar';
  static const String mergeCompanies = '$version/placement/companies/merge';
  static const String placementScheduleImport = '$version/placement/schedule/import';
  static const String placementRolesImport = '$version/placement/roles/import';

  // --- Forums ---
  static String forumThreads(String forumId) => '$version/forums/$forumId/threads';
  static String thread(String id) => '$version/threads/$id';
  static String threadComments(String threadId) => '$version/threads/$threadId/comments';
  static String comment(String id) => '$version/comments/$id';
  static String threadVote(String id) => '$version/threads/$id/vote';
  static String commentVote(String id) => '$version/comments/$id/vote';
  static String eventForum(String eventId) => '$version/events/$eventId/forum';

  // --- Community Events and bookmarks ---
  static const String events = '$version/events';
  static String event(String id) => '$version/events/$id';
  static const String eventTags = '$version/event-tags';
  static String eventUpdates(String eventId) => '$version/events/$eventId/updates';
  static String eventUpdate(String id) => '$version/event-updates/$id';
  static String followedTag(int tagId) => '$version/me/followed-tags/$tagId';
  static String bookmark(String targetType, String targetId) => '$version/me/bookmarks/$targetType/$targetId';
  static const String bookmarksImport = '$version/me/bookmarks/import';

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
