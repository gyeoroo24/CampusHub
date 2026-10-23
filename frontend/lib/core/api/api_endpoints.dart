/// Backend API endpoint routes matching FastAPI routers.
class ApiEndpoints {
  ApiEndpoints._();

  static const String version = '/api/v1';

  // --- Auth & User ---
  static const String authMe = '$version/auth/me';
  static const String authLogin = '$version/auth/login';
  static const String authSendOtp = '$version/auth/send-otp';
  static const String authVerifyOtp = '$version/auth/verify-otp';
  static const String authRefresh = '$version/auth/refresh';

  // --- Media & S3 ---
  static const String mediaPresign = '$version/media/presign-upload';

  // --- Buy & Sell ---
  static const String buySellListings = '$version/buy-sell/listings';
  static String buySellListing(String id) => '$version/buy-sell/listings/$id';
  static String buySellStatus(String id) => '$version/buy-sell/listings/$id/status';

  // --- Lost & Found ---
  static const String lostFoundReports = '$version/lost-found/reports';
  static String lostFoundReport(String id) => '$version/lost-found/reports/$id';
  static String lostFoundResolve(String id) => '$version/lost-found/reports/$id/resolve';
}
