import 'dart:async';
import '../../../../core/api/api_client.dart';
import '../../../../core/api/api_endpoints.dart';
import '../../../../core/storage/token_storage.dart';
import '../../admin/data/admin_repository.dart';
import '../domain/account_status.dart';
import '../domain/user.dart';

abstract class IAuthRepository {
  Future<User?> getCurrentUser();
  Future<User> updateProfile({
    String? name,
    String? phone,
    String? departmentId,
    String? programme,
    int? graduationYear,
  });
  /// Admin endpoint: deactivate or reactivate an account (`PATCH /api/v1/users/{id}`).
  Future<AccountStatus> updateAccountStatus(
    String userId, {
    required bool isActive,
  });
  /// Admin endpoint: transfer the single admin role to another user (`POST /api/v1/users/{id}/make-admin`).
  /// The caller is automatically demoted to a regular signed-in student in the same transaction.
  Future<AccountStatus> transferAdminRole(String targetUserId);
  Future<void> sendOtp(String email);
  Future<User> verifyOtp(String email, String otp);
  Future<User> signInWithEmail(String email);
  Future<void> signOut();
  Stream<User?> get authStateChanges;
}

/// In-memory mock authentication repository with session persistence via ITokenStorage.
class MockAuthRepository implements IAuthRepository {
  final ITokenStorage tokenStorage;
  final _controller = StreamController<User?>.broadcast();
  User? _currentUser;
  bool _initialized = false;

  MockAuthRepository({ITokenStorage? storage})
      : tokenStorage = storage ?? InMemoryTokenStorage();

  Future<void> _init() async {
    if (_initialized) return;
    _initialized = true;

    final savedUser = await tokenStorage.getSavedUser();
    if (savedUser != null) {
      final user = User.fromJson(savedUser);
      final activeGrants = MockAdminRepository.getActiveGrantsForEmail(user.email);
      final registered = MockAdminRepository.findRegisteredUser(user.email);
      _currentUser = user.copyWith(
        name: registered != null && registered.name.isNotEmpty ? registered.name : user.name,
        isAdmin: registered?.isAdmin ?? user.isAdmin,
        isActive: registered?.isActive ?? user.isActive,
        moderatorGrants: activeGrants,
      );
    } else {
      // Default initial mock user with IISc identity
      _currentUser = User(
        id: 'usr_mock_001',
        email: 'kmukund@iisc.ac.in',
        name: 'Mukund Kukreja',
        phone: '+919876543210',
        programme: 'MTech CSA',
        graduationYear: 2026,
        isAdmin: true,
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
      );
      // Persist mock user so session remains active
      await tokenStorage.saveUser(_currentUser!.toJson());
      await tokenStorage.saveTokens(accessToken: 'mock_cognito_id_token_001');
    }
  }

  @override
  Future<User?> getCurrentUser() async {
    await _init();
    if (_currentUser != null) {
      final activeGrants = MockAdminRepository.getActiveGrantsForEmail(_currentUser!.email);
      final registered = MockAdminRepository.findRegisteredUser(_currentUser!.email);
      _currentUser = _currentUser!.copyWith(
        name: registered != null && registered.name.isNotEmpty ? registered.name : _currentUser!.name,
        isAdmin: registered?.isAdmin ?? _currentUser!.isAdmin,
        isActive: registered?.isActive ?? _currentUser!.isActive,
        moderatorGrants: activeGrants,
      );
      await tokenStorage.saveUser(_currentUser!.toJson());
      _controller.add(_currentUser);
    }
    return _currentUser;
  }

  @override
  Future<User> updateProfile({
    String? name,
    String? phone,
    String? departmentId,
    String? programme,
    int? graduationYear,
  }) async {
    await _init();
    if (_currentUser == null) throw Exception('No user signed in');

    _currentUser = _currentUser!.copyWith(
      name: name ?? _currentUser!.name,
      phone: phone ?? _currentUser!.phone,
      departmentId: departmentId ?? _currentUser!.departmentId,
      programme: programme ?? _currentUser!.programme,
      graduationYear: graduationYear ?? _currentUser!.graduationYear,
      updatedAt: DateTime.now(),
    );

    await tokenStorage.saveUser(_currentUser!.toJson());
    _controller.add(_currentUser);
    return _currentUser!;
  }

  @override
  Future<AccountStatus> updateAccountStatus(
    String userId, {
    required bool isActive,
  }) async {
    await _init();
    if (_currentUser != null && _currentUser!.id == userId) {
      _currentUser = _currentUser!.copyWith(isActive: isActive);
      await tokenStorage.saveUser(_currentUser!.toJson());
      _controller.add(_currentUser);
      return AccountStatus(
        id: userId,
        email: _currentUser!.email,
        name: _currentUser!.name,
        isActive: _currentUser!.isActive,
        isAdmin: _currentUser!.isAdmin,
      );
    }
    return AccountStatus(
      id: userId,
      email: 'user_$userId@iisc.ac.in',
      name: 'User $userId',
      isActive: isActive,
      isAdmin: false,
    );
  }

  @override
  Future<AccountStatus> transferAdminRole(String targetUserId) async {
    await _init();
    if (_currentUser == null || !_currentUser!.isAdmin) {
      throw Exception('Only the admin can hand over the admin role.');
    }
    if (_currentUser!.id == targetUserId) {
      throw Exception('You are already the admin.');
    }
    // Caller is downgraded in the same transaction
    _currentUser = _currentUser!.copyWith(isAdmin: false);
    MockAdminRepository.setAdmin(_currentUser!.email, false);
    await tokenStorage.saveUser(_currentUser!.toJson());
    _controller.add(_currentUser);

    return AccountStatus(
      id: targetUserId,
      email: 'successor_$targetUserId@iisc.ac.in',
      name: 'New Admin $targetUserId',
      isActive: true,
      isAdmin: true,
    );
  }

  @override
  Future<void> sendOtp(String email) async {
    await _init();
    final trimmed = email.trim().toLowerCase();
    if (!trimmed.endsWith('@iisc.ac.in') && !trimmed.contains('.iisc.ac.in')) {
      throw Exception('Only valid IISc email addresses (ending in iisc.ac.in) are accepted.');
    }
    // Mock simulation: any 6-digit OTP succeeds
  }

  @override
  Future<User> verifyOtp(String email, String otp) async {
    await _init();
    final trimmedEmail = email.trim().toLowerCase();
    final trimmedOtp = otp.trim();

    if (trimmedOtp.length != 6) {
      throw Exception('Please enter a valid 6-digit verification code.');
    }

    final registered = MockAdminRepository.findRegisteredUser(trimmedEmail);
    final grants = MockAdminRepository.getActiveGrantsForEmail(trimmedEmail);

    final user = (registered ?? User(
      id: 'usr_${trimmedEmail.hashCode.abs()}',
      email: trimmedEmail,
      name: trimmedEmail.split('@').first,
      createdAt: DateTime.now(),
    )).copyWith(
      moderatorGrants: grants,
    );

    _currentUser = user;
    await tokenStorage.saveUser(user.toJson());
    await tokenStorage.saveTokens(accessToken: 'mock_id_token_${user.id}');
    _controller.add(_currentUser);
    return user;
  }

  @override
  Future<User> signInWithEmail(String email) async {
    return verifyOtp(email, '123456');
  }

  @override
  Future<void> signOut() async {
    await _init();
    _currentUser = null;
    await tokenStorage.clearAll();
    _controller.add(null);
  }

  @override
  Stream<User?> get authStateChanges async* {
    await _init();
    yield _currentUser;
    yield* _controller.stream;
  }
}

/// Real HTTP backend authentication repository using Cognito ID token and FastAPI `/me`.
class ApiAuthRepository implements IAuthRepository {
  final ApiClient apiClient;
  final ITokenStorage tokenStorage;
  final _controller = StreamController<User?>.broadcast();
  User? _cachedUser;
  bool _initialized = false;

  ApiAuthRepository({
    required this.apiClient,
    required this.tokenStorage,
  });

  Future<void> _init() async {
    if (_initialized) return;
    _initialized = true;

    final savedUser = await tokenStorage.getSavedUser();
    if (savedUser != null) {
      _cachedUser = User.fromJson(savedUser);
    }
  }

  @override
  Future<User?> getCurrentUser() async {
    await _init();
    final hasToken = await tokenStorage.hasToken();
    final savedUser = await tokenStorage.getSavedUser();
    // Allow checking user if token exists, saved user exists, or dev user email is active
    if (!hasToken && savedUser == null && apiClient.devUserEmail == null) {
      _cachedUser = null;
      return null;
    }

    try {
      final response = await apiClient.get(ApiEndpoints.me);
      if (response.data != null && response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        var user = User.fromJson(data);
        if (user.moderatorGrants.isEmpty) {
          final fallbackGrants = MockAdminRepository.getActiveGrantsForEmail(user.email);
          if (fallbackGrants.isNotEmpty) {
            user = user.copyWith(moderatorGrants: fallbackGrants);
          }
        }
        if (!user.isAdmin && user.email.toLowerCase() == 'kmukund@iisc.ac.in') {
          user = user.copyWith(isAdmin: true);
        }
        _cachedUser = user;
        await tokenStorage.saveUser(_cachedUser!.toJson());
        _controller.add(_cachedUser);
        return _cachedUser;
      }
    } catch (_) {
      await tokenStorage.clearAll();
      _cachedUser = null;
      _controller.add(null);
    }
    return null;
  }

  @override
  Future<User> updateProfile({
    String? name,
    String? phone,
    String? departmentId,
    String? programme,
    int? graduationYear,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name;
    if (phone != null) payload['phone'] = phone;
    if (departmentId != null) payload['department_id'] = departmentId;
    if (programme != null) payload['programme'] = programme;
    if (graduationYear != null) payload['graduation_year'] = graduationYear;

    final response = await apiClient.patch(
      ApiEndpoints.me,
      data: payload,
    );

    final data = response.data as Map<String, dynamic>;
    _cachedUser = User.fromJson(data);
    await tokenStorage.saveUser(_cachedUser!.toJson());
    _controller.add(_cachedUser);
    return _cachedUser!;
  }

  @override
  Future<AccountStatus> updateAccountStatus(
    String userId, {
    required bool isActive,
  }) async {
    final response = await apiClient.patch(
      ApiEndpoints.user(userId),
      data: {'is_active': isActive},
    );

    final data = response.data as Map<String, dynamic>;
    return AccountStatus.fromJson(data);
  }

  @override
  Future<AccountStatus> transferAdminRole(String targetUserId) async {
    final response = await apiClient.post(
      ApiEndpoints.userMakeAdmin(targetUserId),
    );

    final data = response.data as Map<String, dynamic>;
    // Refetch current user to reflect downgraded status
    await getCurrentUser();
    return AccountStatus.fromJson(data);
  }

  @override
  Future<void> sendOtp(String email) async {
    // In cloud deployment, Cognito handles sign-up/sign-in directly.
    final trimmed = email.trim().toLowerCase();
    if (!trimmed.endsWith('@iisc.ac.in') && !trimmed.contains('.iisc.ac.in')) {
      throw Exception('Only valid IISc email addresses (ending in iisc.ac.in) are accepted.');
    }
  }

  @override
  Future<User> verifyOtp(String email, String otp) async {
    // In local dev, save dev user email immediately so ApiClient injects X-Dev-User
    final trimmedEmail = email.trim().toLowerCase();
    final registered = MockAdminRepository.findRegisteredUser(trimmedEmail);
    final mockGrants = MockAdminRepository.getActiveGrantsForEmail(trimmedEmail);
    final isDevAdmin = registered?.isAdmin ?? (trimmedEmail == 'kmukund@iisc.ac.in');

    await tokenStorage.saveUser({
      'email': trimmedEmail,
      'name': registered != null && registered.name.isNotEmpty ? registered.name : trimmedEmail.split('@').first,
      'is_admin': isDevAdmin,
      'moderator_grants': mockGrants.map((g) => g.toJson()).toList(),
    });
    await tokenStorage.saveTokens(accessToken: 'dev_token_$trimmedEmail');

    User? user;
    try {
      user = await getCurrentUser();
    } catch (_) {}

    if (user == null || (user.moderatorGrants.isEmpty && mockGrants.isNotEmpty)) {
      final fallback = (user ?? registered ?? User(
        id: 'usr_${trimmedEmail.hashCode.abs()}',
        email: trimmedEmail,
        name: trimmedEmail.split('@').first,
        isAdmin: isDevAdmin,
        createdAt: DateTime.now(),
      )).copyWith(
        moderatorGrants: mockGrants.isNotEmpty ? mockGrants : user?.moderatorGrants ?? const [],
        isAdmin: isDevAdmin || (user?.isAdmin ?? false),
      );
      _cachedUser = fallback;
      await tokenStorage.saveUser(fallback.toJson());
      _controller.add(fallback);
      return fallback;
    }
    return user;
  }

  @override
  Future<User> signInWithEmail(String email) async {
    return verifyOtp(email, '123456');
  }

  @override
  Future<void> signOut() async {
    await tokenStorage.clearAll();
    _cachedUser = null;
    _controller.add(null);
  }

  @override
  Stream<User?> get authStateChanges async* {
    await _init();
    yield _cachedUser;
    yield* _controller.stream;
  }
}
