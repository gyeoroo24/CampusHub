import 'package:flutter/material.dart';
import '../../../core/enums/sort_option.dart';
import '../domain/lost_found_item.dart';
import 'mock_lost_found_repository.dart';

export 'mock_lost_found_repository.dart';
export 'api_lost_found_repository.dart';

/// Contract for Lost & Found data operations.
abstract class ILostFoundRepository {
  Future<List<LostFoundItem>> fetchReports({
    PostType? type,
    String query = '',
    String category = 'All',
    DateTimeRange? dateRange,
    SortOption sortOption = SortOption.newest,
    int page = 1,
    int limit = 50,
  });

  Future<LostFoundItem?> getReportById(String id);

  Future<LostFoundItem> submitReport(LostFoundItem report);

  Future<void> resolveReport(String id);

  Future<void> deleteReport(String id);
}

/// Backward compatibility alias for existing code
typedef ClientSideLostFoundRepository = MockLostFoundRepository;
