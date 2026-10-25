import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/server_config.dart';
import '../../auth/domain/user.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/admin_repository.dart';
import '../domain/content_report.dart';

final adminRepositoryProvider = Provider<IAdminRepository>((ref) {
  final serverConfig = ref.watch(serverConfigProvider);
  if (serverConfig.useMockData) {
    return MockAdminRepository();
  }
  return ApiAdminRepository(ref.watch(apiClientProvider));
});

final moderatorGrantsProvider = FutureProvider<List<ModeratorGrant>>((ref) async {
  final repo = ref.watch(adminRepositoryProvider);
  return repo.listModerators(includeRevoked: false);
});

final registeredUsersProvider = FutureProvider<List<User>>((ref) async {
  final repo = ref.watch(adminRepositoryProvider);
  return repo.listRegisteredUsers();
});

class ContentReportsFilter {
  final String status;
  final String module;

  const ContentReportsFilter({this.status = 'open', this.module = 'all'});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContentReportsFilter &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          module == other.module;

  @override
  int get hashCode => status.hashCode ^ module.hashCode;
}

final contentReportsFilterProvider =
    StateProvider<ContentReportsFilter>((ref) => const ContentReportsFilter());

final contentReportsProvider = FutureProvider<List<ContentReport>>((ref) async {
  final repo = ref.watch(adminRepositoryProvider);
  final filter = ref.watch(contentReportsFilterProvider);
  return repo.listReports(status: filter.status, module: filter.module);
});

final systemHealthProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(adminRepositoryProvider);
  return repo.getSystemHealth();
});
