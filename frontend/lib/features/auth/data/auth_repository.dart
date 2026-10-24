import 'dart:async';
import '../../../../core/api/api_client.dart';
import '../../../../core/api/api_endpoints.dart';
import '../../../../core/storage/token_storage.dart';
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
  /// Admin endpoint: deactivate/reactivate account or change admin privileges (`PATCH /api/v1/users/{id}`).
  Future<AccountStatus> updateAccountStatus(
    String userId, {
    bool? isActive,
    bool? isAdmin,
  });
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
      _currentUser = User.fromJson(savedUser);
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
    bool? isActive,
    bool? isAdmin,
  }) async {
    await _init();
    if (_currentUser != null && _currentUser!.id == userId) {
      _currentUser = _currentUser!.copyWith(
        isActive: isActive ?? _currentUser!.isActive,
        isAdmin: isAdmin ?? _currentUser!.isAdmin,
      );
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
      isActive: isActive ?? true,
      isAdmin: isAdmin ?? false,
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

    final user = User(
      id: 'usr_${trimmedEmail.hashCode.abs()}',
      email: trimmedEmail,
      name: trimmedEmail.split('@').first,
      createdAt: DateTime.now(),
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
    // Allow checking user if token exists OR if dev user email header is active
    if (!hasToken && apiClient.devUserEmail == null) {
      _cachedUser = null;
      return null;
    }

    try {
      final response = await apiClient.get(ApiEndpoints.me);
      if (response.data != null && response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        _cachedUser = User.fromJson(data);
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
    bool? isActive,
    bool? isAdmin,
  }) async {
    final payload = <String, dynamic>{};
    if (isActive != null) payload['is_active'] = isActive;
    if (isAdmin != null) payload['is_admin'] = isAdmin;

    final response = await apiClient.patch(
      ApiEndpoints.user(userId),
      data: payload,
    );

    final data = response.data as Map<String, dynamic>;
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
    // In local dev, save dev user token and fetch /me
    await tokenStorage.saveTokens(accessToken: 'dev_token_$email');
    final user = await getCurrentUser();
    if (user == null) {
      // Create fallback profile if server not running
      final fallback = User(
        id: 'usr_${email.hashCode.abs()}',
        email: email,
        name: email.split('@').first,
        createdAt: DateTime.now(),
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
