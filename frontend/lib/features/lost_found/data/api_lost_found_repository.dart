import 'package:flutter/material.dart' show DateTimeRange;
import '../../../../core/api/api_client.dart';
import '../../../../core/api/api_endpoints.dart';
import '../../../../core/enums/sort_option.dart';
import '../../../../core/models/category_ref.dart';
import '../../../../core/models/page.dart';
import '../domain/lost_found_item.dart';
import 'lost_found_dto.dart';
import 'lost_found_repository.dart';

/// HTTP/REST implementation of [ILostFoundRepository] calling FastAPI backend.
class ApiLostFoundRepository implements ILostFoundRepository {
  final ApiClient apiClient;

  ApiLostFoundRepository(this.apiClient);

  String _basePath(PostType type) =>
      type == PostType.lost ? ApiEndpoints.lostReports : ApiEndpoints.foundReports;

  String _itemPath(PostType type, String id) =>
      type == PostType.lost ? ApiEndpoints.lostReport(id) : ApiEndpoints.foundReport(id);

  String _statusPath(PostType type, String id) =>
      type == PostType.lost ? ApiEndpoints.lostReportStatus(id) : ApiEndpoints.foundReportStatus(id);

  String _photosPath(PostType type, String id) =>
      type == PostType.lost ? ApiEndpoints.lostReportPhotos(id) : ApiEndpoints.foundReportPhotos(id);

  @override
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
  }) async {
    final queryParams = <String, dynamic>{
      'limit': limit,
      'offset': offset,
    };

    if (query.trim().isNotEmpty) queryParams['q'] = query.trim();
    if (categoryId != null) queryParams['category_id'] = categoryId;
    if (reporterId != null && reporterId.isNotEmpty) queryParams['reporter_id'] = reporterId;
    if (dateRange != null) {
      queryParams['from_date'] = dateRange.start.toIso8601String();
      queryParams['to_date'] = dateRange.end.toIso8601String();
    }
    if (sortOption == SortOption.oldest) {
      queryParams['sort'] = 'oldest';
    } else {
      queryParams['sort'] = 'newest';
    }
    if (statusList != null && statusList.isNotEmpty) {
      queryParams['status'] = statusList.map((s) => s.name).toList();
    }

    final response = await apiClient.get(
      _basePath(type),
      queryParameters: queryParams,
    );

    if (response.data is Map<String, dynamic>) {
      return PaginatedResponse<LostFoundItem>.fromJson(
        response.data as Map<String, dynamic>,
        (itemJson) => LostFoundReportDto.fromJson(itemJson as Map<String, dynamic>).toDomain(),
      );
    }

    return const PaginatedResponse(items: [], limit: 20, offset: 0, hasMore: false);
  }

  @override
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
  }) async {
    final effectiveOffset = offset > 0 ? offset : (page > 1 ? (page - 1) * limit : 0);

    List<LostFoundItem> results = [];

    if (type != null) {
      final paged = await fetchReportsPage(
        type: type,
        query: query,
        categoryId: categoryId,
        statusList: statusList,
        reporterId: reporterId,
        limit: limit,
        offset: effectiveOffset,
      );
      results = paged.items;
    } else {
      // Both lost and found feeds requested: query both concurrently
      final halfLimit = (limit / 2).ceil();
      final responses = await Future.wait([
        fetchReportsPage(
          type: PostType.lost,
          query: query,
          categoryId: categoryId,
          statusList: statusList,
          reporterId: reporterId,
          limit: halfLimit,
          offset: effectiveOffset,
        ),
        fetchReportsPage(
          type: PostType.found,
          query: query,
          categoryId: categoryId,
          statusList: statusList,
          reporterId: reporterId,
          limit: halfLimit,
          offset: effectiveOffset,
        ),
      ]);
      results = [...responses[0].items, ...responses[1].items];
    }

    // Client-side dateRange filtering if supplied
    if (dateRange != null) {
      results = results
          .where(
            (r) =>
                r.occurredAt.isAfter(dateRange.start) &&
                r.occurredAt.isBefore(dateRange.end),
          )
          .toList();
    }

    // Client-side category string fallback if categoryId was null
    if (category != 'All' && categoryId == null) {
      results = results
          .where((r) => r.category.name.toLowerCase() == category.toLowerCase())
          .toList();
    }

    // Sorting
    if (sortOption == SortOption.oldest) {
      results.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    } else {
      results.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    }

    return results;
  }

  @override
  Future<LostFoundItem?> getReportById(String id, {PostType type = PostType.lost}) async {
    final response = await apiClient.get(_itemPath(type, id));
    if (response.data != null && response.data is Map<String, dynamic>) {
      return LostFoundReportDto.fromJson(response.data as Map<String, dynamic>).toDomain();
    }
    return null;
  }

  @override
  Future<LostFoundItem> submitReport(
    LostFoundItem report, {
    List<String> photoKeys = const [],
  }) async {
    final dto = LostFoundReportDto.fromDomain(report);
    final response = await apiClient.post(
      _basePath(report.kind),
      data: dto.toCreateJson(photoKeys: photoKeys),
    );

    if (response.data != null && response.data is Map<String, dynamic>) {
      return LostFoundReportDto.fromJson(response.data as Map<String, dynamic>).toDomain();
    }
    return report;
  }

  @override
  Future<LostFoundItem> updateReport(
    String id, {
    required PostType type,
    String? description,
    int? categoryId,
    DateTime? occurredAt,
    String? location,
  }) async {
    final payload = <String, dynamic>{};
    if (description != null) payload['description'] = description;
    if (categoryId != null) payload['category_id'] = categoryId;
    if (occurredAt != null) payload['occurred_at'] = occurredAt.toUtc().toIso8601String();
    if (location != null) payload['location'] = location;

    final response = await apiClient.patch(
      _itemPath(type, id),
      data: payload,
    );

    final data = response.data as Map<String, dynamic>;
    return LostFoundReportDto.fromJson(data).toDomain();
  }

  @override
  Future<void> updateStatus(String id, PostType type, ReportStatus status) async {
    await apiClient.patch(
      _statusPath(type, id),
      data: {'status': status.name},
    );
  }

  @override
  Future<void> replacePhotos(String id, PostType type, List<String> photoKeys) async {
    await apiClient.put(
      _photosPath(type, id),
      data: {'photo_keys': photoKeys},
    );
  }

  @override
  Future<void> deleteReport(String id, PostType type, {String? reason}) async {
    final queryParams = <String, dynamic>{};
    if (reason != null && reason.trim().isNotEmpty) {
      queryParams['reason'] = reason.trim();
    }

    await apiClient.delete(
      _itemPath(type, id),
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );
  }

  @override
  Future<List<CategoryRef>> fetchCategories() async {
    final response = await apiClient.get(ApiEndpoints.lostFoundCategories);
    if (response.data is List) {
      return (response.data as List<dynamic>)
          .map((item) => CategoryRef.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  @override
  Future<CategoryRef> createCategory(String name) async {
    final response = await apiClient.post(
      ApiEndpoints.lostFoundCategories,
      data: {'name': name.trim()},
    );

    return CategoryRef.fromJson(response.data as Map<String, dynamic>);
  }
}
