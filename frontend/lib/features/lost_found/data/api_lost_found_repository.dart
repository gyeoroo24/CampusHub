import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/enums/sort_option.dart';
import '../domain/lost_found_item.dart';
import 'lost_found_dto.dart';
import 'lost_found_repository.dart';

/// HTTP/REST implementation of [ILostFoundRepository] calling FastAPI backend.
class ApiLostFoundRepository implements ILostFoundRepository {
  final ApiClient apiClient;

  ApiLostFoundRepository(this.apiClient);

  @override
  Future<List<LostFoundItem>> fetchReports({
    PostType? type,
    String query = '',
    String category = 'All',
    DateTimeRange? dateRange,
    SortOption sortOption = SortOption.newest,
    int page = 1,
    int limit = 50,
  }) async {
    final queryParams = <String, dynamic>{
      'page': page,
      'limit': limit,
      'sort_by': sortOption == SortOption.oldest ? 'date_asc' : 'date_desc',
    };

    if (type != null) queryParams['type'] = type.name;
    if (query.isNotEmpty) queryParams['query'] = query;
    if (category != 'All') queryParams['category'] = category;
    if (dateRange != null) {
      queryParams['from_date'] = dateRange.start.toIso8601String();
      queryParams['to_date'] = dateRange.end.toIso8601String();
    }

    final response = await apiClient.get(
      ApiEndpoints.lostFoundReports,
      queryParameters: queryParams,
    );

    final rawData = response.data;
    List<dynamic> itemsList = [];

    if (rawData is List) {
      itemsList = rawData;
    } else if (rawData is Map<String, dynamic>) {
      itemsList = (rawData['items'] as List<dynamic>?) ?? [];
    }

    return itemsList
        .map((item) => LostFoundReportDto.fromJson(item as Map<String, dynamic>).toDomain())
        .toList();
  }

  @override
  Future<LostFoundItem?> getReportById(String id) async {
    final response = await apiClient.get(ApiEndpoints.lostFoundReport(id));
    if (response.data != null && response.data is Map<String, dynamic>) {
      return LostFoundReportDto.fromJson(response.data as Map<String, dynamic>).toDomain();
    }
    return null;
  }

  @override
  Future<LostFoundItem> submitReport(LostFoundItem report) async {
    final dto = LostFoundReportDto.fromDomain(report);
    final response = await apiClient.post(
      ApiEndpoints.lostFoundReports,
      data: dto.toJson(),
    );

    if (response.data != null && response.data is Map<String, dynamic>) {
      return LostFoundReportDto.fromJson(response.data as Map<String, dynamic>).toDomain();
    }
    return report;
  }

  @override
  Future<void> resolveReport(String id) async {
    await apiClient.patch(ApiEndpoints.lostFoundResolve(id));
  }

  @override
  Future<void> deleteReport(String id) async {
    await apiClient.delete(ApiEndpoints.lostFoundReport(id));
  }
}
