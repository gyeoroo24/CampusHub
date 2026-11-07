import 'dart:async';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../auth/domain/account_status.dart';
import '../../auth/domain/user.dart';
import '../domain/content_report.dart';

abstract class IAdminRepository {
  Future<List<ModeratorGrant>> listModerators({bool includeRevoked = false});
  Future<ModeratorGrant> grantModerator({
    required String email,
    required String module,
    String scopeType = 'module',
    String? departmentId,
    String? courseId,
  });
  Future<void> revokeModerator(String grantId);
  Future<AccountStatus> transferAdminRole(String targetEmail);
  Future<AccountStatus> updateUserStatus({required String email, required bool isActive});
  Future<List<ContentReport>> listReports({String? status, String? module});

  /// Flags a listing or lost/found report for moderator review (FR-10). Any signed-in user may
  /// file one open report per item; the backend rejects a second with 409.
  Future<void> createReport({
    required String targetType, // 'listing' | 'lost_report' | 'found_report'
    required String targetId,
    required String reason,
  });

  Future<void> resolveReport(
    String reportId, {
    required String action, // 'actioned' or 'dismissed'
    String? note,
    bool removeContent = false,
    /// Required when removing a listing: 'severe' (illegal item) blocks the seller immediately;
    /// 'non_severe' counts toward the strike ladder. Seller trust score, future plan §1.5.
    String? severity,
  });
  Future<Map<String, dynamic>> getSystemHealth();
  /// Accounts for the admin's User Accounts tab (admin only): the admin first, then by name.
  /// [query] narrows to names or emails containing it; at most [limit] are returned.
  Future<List<User>> listRegisteredUsers({String query = '', int limit = 50});

  /// Finds an account by email (admin only); throws if nobody with that email has signed in yet.
  Future<AccountStatus> lookupUser(String email);
}

/// In-memory mock admin repository for local UI development and testing.
class MockAdminRepository implements IAdminRepository {
  static void setAdmin(String email, bool isAdmin) {
    final clean = email.trim().toLowerCase();
    final idx = _mockUsers.indexWhere((u) => u.email.toLowerCase() == clean);
    if (idx != -1) {
      _mockUsers[idx] = _mockUsers[idx].copyWith(isAdmin: isAdmin);
    }
  }

  static void resetMockData() {
    _mockGrants
      ..clear()
      ..addAll(_buildInitialGrants());
    _mockUsers
      ..clear()
      ..addAll(_buildInitialUsers());
  }

  static List<ModeratorGrant> _buildInitialGrants() => [
    ModeratorGrant(
      id: 'grant_101',
      userId: 'usr_mod_1',
      userEmail: 'cadithya@iisc.ac.in',
      userName: 'Adithya Chippa',
      module: 'buy_sell',
      scopeType: 'module',
      grantedAt: DateTime.now().subtract(const Duration(days: 14)),
    ),
    ModeratorGrant(
      id: 'grant_102',
      userId: 'usr_mod_2',
      userEmail: 'dinkylakhani@iisc.ac.in',
      userName: 'Dinky Lakhani',
      module: 'lost_found',
      scopeType: 'module',
      grantedAt: DateTime.now().subtract(const Duration(days: 10)),
    ),
    ModeratorGrant(
      id: 'grant_103',
      userId: 'usr_mod_3',
      userEmail: 'mohammadazam@iisc.ac.in',
      userName: 'Mohammad Sufyan Azam',
      module: 'academic_help',
      scopeType: 'department',
      grantedAt: DateTime.now().subtract(const Duration(days: 5)),
    ),
  ];

  static List<User> _buildInitialUsers() => [
    User(
      id: 'usr_mock_001',
      email: 'kmukund@iisc.ac.in',
      name: 'Mukund Kukreja',
      phone: '+919876543210',
      programme: 'MTech CSA',
      graduationYear: 2026,
      isAdmin: true,
      isActive: true,
      moderatorGrants: [
        ModeratorGrant(
          id: 'grant_001',
          module: 'buy_sell',
          scopeType: 'all',
          grantedAt: DateTime.now().subtract(const Duration(days: 30)),
        ),
        ModeratorGrant(
          id: 'grant_002',
          module: 'lost_found',
          scopeType: 'all',
          grantedAt: DateTime.now().subtract(const Duration(days: 30)),
        ),
      ],
      createdAt: DateTime.now().subtract(const Duration(days: 60)),
    ),
    User(
      id: 'usr_mock_002',
      email: 'cadithya@iisc.ac.in',
      name: 'Adithya Chippa',
      phone: '+919812345678',
      programme: 'MTech CSA',
      graduationYear: 2026,
      isAdmin: false,
      isActive: true,
      moderatorGrants: [
        ModeratorGrant(
          id: 'grant_101',
          userId: 'usr_mock_002',
          userEmail: 'cadithya@iisc.ac.in',
          userName: 'Adithya Chippa',
          module: 'buy_sell',
          scopeType: 'module',
          grantedAt: DateTime.now().subtract(const Duration(days: 14)),
        ),
      ],
      createdAt: DateTime.now().subtract(const Duration(days: 45)),
    ),
    User(
      id: 'usr_mock_003',
      email: 'dinkylakhani@iisc.ac.in',
      name: 'Dinky Lakhani',
      phone: '+919823456789',
      programme: 'MTech CSA',
      graduationYear: 2026,
      isAdmin: false,
      isActive: true,
      moderatorGrants: [
        ModeratorGrant(
          id: 'grant_102',
          userId: 'usr_mock_003',
          userEmail: 'dinkylakhani@iisc.ac.in',
          userName: 'Dinky Lakhani',
          module: 'lost_found',
          scopeType: 'module',
          grantedAt: DateTime.now().subtract(const Duration(days: 10)),
        ),
      ],
      createdAt: DateTime.now().subtract(const Duration(days: 40)),
    ),
    User(
      id: 'usr_mock_004',
      email: 'mohammadazam@iisc.ac.in',
      name: 'Mohammad Sufyan Azam',
      phone: '+919834567890',
      programme: 'MTech CSA',
      graduationYear: 2026,
      isAdmin: false,
      isActive: true,
      moderatorGrants: [
        ModeratorGrant(
          id: 'grant_103',
          userId: 'usr_mock_004',
          userEmail: 'mohammadazam@iisc.ac.in',
          userName: 'Mohammad Sufyan Azam',
          module: 'academic_help',
          scopeType: 'department',
          grantedAt: DateTime.now().subtract(const Duration(days: 5)),
        ),
      ],
      createdAt: DateTime.now().subtract(const Duration(days: 35)),
    ),
    User(
      id: 'usr_mock_005',
      email: 'student@iisc.ac.in',
      name: 'Aarav Sharma',
      phone: '+919876543211',
      programme: 'PhD EECS',
      graduationYear: 2027,
      isAdmin: false,
      isActive: true,
      createdAt: DateTime.now().subtract(const Duration(days: 20)),
    ),
  ];

  static final List<ModeratorGrant> _mockGrants = _buildInitialGrants();
  static final List<User> _mockUsers = _buildInitialUsers();

  static final List<ContentReport> _mockReports = [
    ContentReport(
      id: 'rep_001',
      module: 'buy_sell',
      targetType: 'listing',
      targetId: 'l1',
      reason: 'Suspiciously high price for used laboratory equipment; user might be reselling department inventory.',
      status: 'open',
      createdAt: DateTime.now().subtract(const Duration(hours: 4)),
    ),
    ContentReport(
      id: 'rep_002',
      module: 'lost_found',
      targetType: 'lost_report',
      targetId: 'r1',
      reason: 'Duplicate lost report filed multiple times in the same hour.',
      status: 'open',
      createdAt: DateTime.now().subtract(const Duration(hours: 12)),
    ),
    ContentReport(
      id: 'rep_003',
      module: 'buy_sell',
      targetType: 'listing',
      targetId: 'l4',
      reason: 'Prohibited electronic surveillance item not permitted on campus.',
      status: 'open',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ];

  static List<ModeratorGrant> getActiveGrantsForEmail(String email) {
    final clean = email.trim().toLowerCase();
    return _mockGrants
        .where((g) => g.userEmail?.toLowerCase() == clean && g.revokedAt == null)
        .toList();
  }

  static User? findRegisteredUser(String email) {
    final clean = email.trim().toLowerCase();
    final idx = _mockUsers.indexWhere((u) => u.email.toLowerCase() == clean);
    if (idx != -1) return _mockUsers[idx];
    return null;
  }

  @override
  Future<List<ModeratorGrant>> listModerators({bool includeRevoked = false}) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (includeRevoked) return List.unmodifiable(_mockGrants);
    return _mockGrants.where((g) => g.revokedAt == null).toList();
  }

  @override
  Future<ModeratorGrant> grantModerator({
    required String email,
    required String module,
    String scopeType = 'module',
    String? departmentId,
    String? courseId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final trimmed = email.trim().toLowerCase();
    if (!trimmed.endsWith('@iisc.ac.in') && !trimmed.contains('.iisc.ac.in')) {
      throw Exception('Only valid IISc email addresses can be granted moderator roles.');
    }

    final existingUser = _mockUsers.firstWhere(
      (u) => u.email.toLowerCase() == trimmed,
      orElse: () {
        final newUser = User(
          id: 'usr_${trimmed.hashCode.abs()}',
          email: trimmed,
          name: trimmed.split('@').first,
          createdAt: DateTime.now(),
        );
        _mockUsers.add(newUser);
        return newUser;
      },
    );

    // Check if already active grant for this module
    final duplicate = _mockGrants.any((g) =>
        g.userEmail?.toLowerCase() == trimmed &&
        g.module == module &&
        g.revokedAt == null);
    if (duplicate) {
      throw Exception('$trimmed already holds an active moderator assignment in $module.');
    }

    final newGrant = ModeratorGrant(
      id: 'grant_${DateTime.now().millisecondsSinceEpoch}',
      userId: existingUser.id,
      userEmail: existingUser.email,
      userName: existingUser.name,
      module: module,
      scopeType: scopeType,
      departmentId: departmentId,
      courseId: courseId,
      grantedAt: DateTime.now(),
    );

    _mockGrants.insert(0, newGrant);

    final uIdx = _mockUsers.indexWhere((u) => u.email.toLowerCase() == trimmed);
    if (uIdx != -1) {
      final u = _mockUsers[uIdx];
      _mockUsers[uIdx] = u.copyWith(moderatorGrants: [newGrant, ...u.moderatorGrants]);
    }
    return newGrant;
  }

  @override
  Future<void> revokeModerator(String grantId) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final idx = _mockGrants.indexWhere((g) => g.id == grantId);
    if (idx != -1) {
      final old = _mockGrants[idx];
      _mockGrants[idx] = ModeratorGrant(
        id: old.id,
        userId: old.userId,
        userEmail: old.userEmail,
        userName: old.userName,
        module: old.module,
        scopeType: old.scopeType,
        departmentId: old.departmentId,
        courseId: old.courseId,
        grantedAt: old.grantedAt,
        revokedAt: DateTime.now(),
      );

      if (old.userEmail != null) {
        final email = old.userEmail!.toLowerCase();
        final uIdx = _mockUsers.indexWhere((u) => u.email.toLowerCase() == email);
        if (uIdx != -1) {
          final u = _mockUsers[uIdx];
          _mockUsers[uIdx] = u.copyWith(
            moderatorGrants: u.moderatorGrants.where((g) => g.id != grantId).toList(),
          );
        }
      }
    }
  }

  @override
  Future<AccountStatus> transferAdminRole(String targetEmail) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final trimmed = targetEmail.trim().toLowerCase();
    final idx = _mockUsers.indexWhere((u) => u.email.toLowerCase() == trimmed);
    if (idx == -1) {
      throw Exception('No campus user found with email "$trimmed".');
    }
    final target = _mockUsers[idx];
    if (!target.isActive) {
      throw Exception('Cannot transfer admin role to a deactivated account.');
    }

    // Downgrade existing admin
    for (int i = 0; i < _mockUsers.length; i++) {
      if (_mockUsers[i].isAdmin) {
        _mockUsers[i] = _mockUsers[i].copyWith(isAdmin: false);
      }
    }

    // Promote successor
    _mockUsers[idx] = target.copyWith(isAdmin: true);

    return AccountStatus(
      id: target.id,
      email: target.email,
      name: target.name,
      isActive: target.isActive,
      isAdmin: true,
    );
  }

  @override
  Future<AccountStatus> updateUserStatus({required String email, required bool isActive}) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final trimmed = email.trim().toLowerCase();
    final idx = _mockUsers.indexWhere((u) => u.email.toLowerCase() == trimmed);
    if (idx == -1) {
      throw Exception('No campus user found with email "$trimmed".');
    }
    final target = _mockUsers[idx];
    if (target.isAdmin && !isActive) {
      throw Exception('Cannot deactivate the active Administrator. Transfer the role first.');
    }

    _mockUsers[idx] = target.copyWith(isActive: isActive);

    return AccountStatus(
      id: target.id,
      email: target.email,
      name: target.name,
      isActive: isActive,
      isAdmin: target.isAdmin,
    );
  }

  @override
  Future<List<ContentReport>> listReports({String? status, String? module}) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return _mockReports.where((r) {
      if (status != null && status != 'all' && r.status != status) return false;
      if (module != null && module != 'all' && r.module != module) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)); // newest first, as the API does
  }

  static const _fixedModule = {
    'listing': 'buy_sell',
    'lost_report': 'lost_found',
    'found_report': 'lost_found',
  };

  @override
  Future<void> createReport({
    required String targetType,
    required String targetId,
    required String reason,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final alreadyOpen = _mockReports.any((r) =>
        r.targetType == targetType && r.targetId == targetId && r.status == 'open');
    if (alreadyOpen) {
      throw Exception('You already have an open report on this item.');
    }
    _mockReports.insert(
      0,
      ContentReport(
        id: 'rep_${DateTime.now().millisecondsSinceEpoch}',
        module: _fixedModule[targetType] ?? 'buy_sell',
        targetType: targetType,
        targetId: targetId,
        reason: reason,
        status: 'open',
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> resolveReport(
    String reportId, {
    required String action,
    String? note,
    bool removeContent = false,
    String? severity,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final idx = _mockReports.indexWhere((r) => r.id == reportId);
    if (idx != -1) {
      _mockReports[idx] = _mockReports[idx].copyWith(
        status: action,
        handledAt: DateTime.now(),
        resolutionNote: note,
      );
    }
  }

  @override
  Future<Map<String, dynamic>> getSystemHealth() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return {
      'status': 'healthy',
      'services': {
        'database': 'PostgreSQL RDS Multi-AZ (Cluster Operational)',
        'compute': 'AWS Lambda Serverless (ap-south-1)',
        'storage': 'Amazon S3 Media Bucket (Private OAC)',
        'auth': 'AWS Cognito User Pool (IISc Domain Enforced)',
      },
      'activeModerators': _mockGrants.where((g) => g.revokedAt == null).length,
      'openReports': _mockReports.where((r) => r.status == 'open').length,
      'registeredUsers': _mockUsers.length,
    };
  }

  @override
  Future<AccountStatus> lookupUser(String email) async {
    final match = _mockUsers.where((u) => u.email.toLowerCase() == email.trim().toLowerCase());
    if (match.isEmpty) throw Exception('No account with that email. The person needs to sign in once first.');
    final u = match.first;
    return AccountStatus(id: u.id, email: u.email, name: u.name, isActive: u.isActive, isAdmin: u.isAdmin);
  }

  @override
  Future<List<User>> listRegisteredUsers({String query = '', int limit = 50}) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final q = query.trim().toLowerCase();
    return List.unmodifiable(_mockUsers
        .where((u) => q.isEmpty || u.name.toLowerCase().contains(q) || u.email.toLowerCase().contains(q))
        .take(limit));
  }
}

/// Real API implementation talking to FastAPI backend routers.
class ApiAdminRepository implements IAdminRepository {
  final ApiClient apiClient;

  ApiAdminRepository(this.apiClient);

  @override
  Future<List<ModeratorGrant>> listModerators({bool includeRevoked = false}) async {
    final response = await apiClient.get(
      ApiEndpoints.moderators,
      queryParameters: {'include_revoked': includeRevoked},
    );
    if (response.data is List) {
      return (response.data as List<dynamic>)
          .map((g) => ModeratorGrant.fromJson(g as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  @override
  Future<ModeratorGrant> grantModerator({
    required String email,
    required String module,
    String scopeType = 'module',
    String? departmentId,
    String? courseId,
  }) async {
    final payload = <String, dynamic>{
      'email': email.trim(),
      'module': module,
      'scope_type': scopeType,
      if (departmentId != null) 'department_id': departmentId,
      if (courseId != null) 'course_id': courseId,
    };

    final response = await apiClient.post(
      ApiEndpoints.moderators,
      data: payload,
    );

    return ModeratorGrant.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<void> revokeModerator(String grantId) async {
    await apiClient.delete(ApiEndpoints.moderator(grantId));
  }

  @override
  Future<AccountStatus> lookupUser(String email) async {
    final response = await apiClient.get(ApiEndpoints.userLookup, queryParameters: {'email': email.trim()});
    return AccountStatus.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<AccountStatus> transferAdminRole(String targetEmail) async {
    final target = await lookupUser(targetEmail);
    final response = await apiClient.post(
      ApiEndpoints.userMakeAdmin(target.id),
    );
    return AccountStatus.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<AccountStatus> updateUserStatus({required String email, required bool isActive}) async {
    final target = await lookupUser(email);
    final response = await apiClient.patch(
      ApiEndpoints.user(target.id),
      data: {'is_active': isActive},
    );
    return AccountStatus.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<List<ContentReport>> listReports({String? status, String? module}) async {
    final params = <String, dynamic>{};
    if (status != null) params['status'] = status; // 'all' is understood by the API
    if (module != null && module != 'all') params['module'] = module;

    final response = await apiClient.get(
      ApiEndpoints.reports,
      queryParameters: params.isNotEmpty ? params : null,
    );

    if (response.data is Map<String, dynamic> && response.data['items'] is List) {
      return (response.data['items'] as List<dynamic>)
          .map((r) => ContentReport.fromJson(r as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  @override
  Future<void> createReport({
    required String targetType,
    required String targetId,
    required String reason,
  }) async {
    await apiClient.post(
      ApiEndpoints.reports,
      data: {
        'target_type': targetType,
        'target_id': targetId,
        'reason': reason,
      },
    );
  }

  @override
  Future<void> resolveReport(
    String reportId, {
    required String action,
    String? note,
    bool removeContent = false,
    String? severity,
  }) async {
    await apiClient.post(
      ApiEndpoints.resolveReport(reportId),
      data: {
        'action': action,
        if (note != null && note.isNotEmpty) 'note': note,
        'remove_content': removeContent,
        if (severity != null) 'severity': severity,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> getSystemHealth() async {
    try {
      final response = await apiClient.get(ApiEndpoints.health);
      return {
        'status': response.data?['status'] == 'ok' ? 'healthy' : 'operational',
        'raw': response.data,
      };
    } catch (e) {
      return {'status': 'degraded', 'error': e.toString()};
    }
  }

  @override
  Future<List<User>> listRegisteredUsers({String query = '', int limit = 50}) async {
    final response = await apiClient.get(ApiEndpoints.users, queryParameters: {
      if (query.trim().isNotEmpty) 'q': query.trim(),
      'limit': limit,
    });
    final items = (response.data as Map<String, dynamic>)['items'] as List<dynamic>? ?? const [];
    return items.map((u) => User.fromJson(u as Map<String, dynamic>)).toList();
  }
}
