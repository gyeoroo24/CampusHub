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

/// What the admin typed in the User Accounts tab's search box.
final registeredUsersQueryProvider = StateProvider<String>((ref) => '');

/// The User Accounts tab's status filter: 'active', 'deactivated', or null for everyone.
final registeredUsersStatusProvider = StateProvider<String?>((ref) => null);

/// How many accounts are fetched at a time; the next page loads as the list scrolls near its end.
const registeredUsersPageSize = 50;

class RegisteredUsersState {
  final List<User> items;
  final bool hasMore;
  final bool loading;
  final Object? error;

  const RegisteredUsersState({this.items = const [], this.hasMore = true, this.loading = false, this.error});

  RegisteredUsersState copyWith({List<User>? items, bool? hasMore, bool? loading, Object? error}) =>
      RegisteredUsersState(
          items: items ?? this.items, hasMore: hasMore ?? this.hasMore, loading: loading ?? this.loading, error: error);
}

/// Every account, a page at a time, for the current search and status filter.
class RegisteredUsersController extends StateNotifier<RegisteredUsersState> {
  RegisteredUsersController(this._repo, this._query, this._status) : super(const RegisteredUsersState()) {
    loadMore();
  }

  final IAdminRepository _repo;
  final String _query;
  final String? _status;

  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;
    state = state.copyWith(loading: true);
    try {
      final page = await _repo.listRegisteredUsers(
          query: _query, status: _status, offset: state.items.length, limit: registeredUsersPageSize);
      if (!mounted) return;
      state = RegisteredUsersState(items: [...state.items, ...page.items], hasMore: page.hasMore);
    } catch (e) {
      if (mounted) state = state.copyWith(loading: false, error: e);
    }
  }
}

final registeredUsersProvider =
    StateNotifierProvider.autoDispose<RegisteredUsersController, RegisteredUsersState>((ref) {
  return RegisteredUsersController(ref.watch(adminRepositoryProvider), ref.watch(registeredUsersQueryProvider),
      ref.watch(registeredUsersStatusProvider));
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

