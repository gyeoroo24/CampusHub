import 'package:flutter/material.dart' show DateTimeRange;
import '../../../../core/enums/sort_option.dart';
import '../../../../core/models/category_ref.dart';
import '../../../../core/models/page.dart';
import '../domain/lost_found_item.dart';
import '../domain/possible_match.dart';

export 'api_lost_found_repository.dart';
export 'mock_lost_found_repository.dart';

/// Contract for Lost & Found data operations matching FastAPI endpoints.
abstract class ILostFoundRepository {
  /// Fetches reports with client/server filtering.
  Future<List<LostFoundItem>> fetchReports({
    PostType? type,
    String query = '',
    String category = 'All',
    int? categoryId,
    DateTimeRange? dateRange,
    SortOption sortOption = SortOption.newest,
    List<ReportStatus>? statusList,
    String? reporterId,
    int page = 1,
    int limit = 50,
    int offset = 0,
  });

  /// Standard paginated query returning `PaginatedResponse<LostFoundItem>` for `/lost-reports` or `/found-reports`.
  Future<PaginatedResponse<LostFoundItem>> fetchReportsPage({
    required PostType type,
    String query = '',
    int? categoryId,
    DateTimeRange? dateRange,
    SortOption sortOption = SortOption.newest,
    List<ReportStatus>? statusList,
    String? reporterId,
    int limit = 20,
    int offset = 0,
  });

  /// Retrieves a specific report by id and type.
  Future<LostFoundItem?> getReportById(String id, {PostType type = PostType.lost});

  /// Files a new lost or found report (FR-7, FR-8).
  /// On creating a report, returns the saved report and any [possibleMatches] found (FR-9).
  Future<LostFoundItem> submitReport(
    LostFoundItem report, {
    List<String> photoKeys = const [],
  });

  /// Edits report fields (reporter only).
  Future<LostFoundItem> updateReport(
    String id, {
    required PostType type,
    String? description,
    int? categoryId,
    DateTime? occurredAt,
    String? location,
  });

  /// Updates status to open, matched, or closed (reporter only).
  Future<void> updateStatus(String id, PostType type, ReportStatus status);

  /// Replaces photos with new ordered S3 keys.
  Future<void> replacePhotos(String id, PostType type, List<String> photoKeys);

  /// Removes report (reporter, Lost & Found moderator, or admin).
  Future<void> deleteReport(String id, PostType type, {String? reason});

  /// Lists all Lost & Found categories from `GET /api/v1/lost-found/categories`.
  Future<List<CategoryRef>> fetchCategories();

  /// Adds a category or retrieves existing one (`POST /api/v1/lost-found/categories`).
  Future<CategoryRef> createCategory(String name);

  /// Updates or renames an existing category.
  Future<CategoryRef> updateCategory(int id, String newName);

  /// Deletes a category (that module's moderators and the admin). If posts or saved searches use
  /// it, they are moved to [moveTo]; without one the server answers 409 saying how many use it.
  Future<void> deleteCategory(int id, {int? moveTo});

  /// Possible matches for one of the signed-in user's own reports, best first
  /// (`GET /{kind}-reports/{id}/matches`). Owners and admins only.
  Future<MatchResult> getPossibleMatches(String id, PostType kind);
}
