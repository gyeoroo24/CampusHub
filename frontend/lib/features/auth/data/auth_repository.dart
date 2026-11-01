import 'dart:async';
import '../../../../core/api/api_client.dart';
import '../../../../core/api/api_endpoints.dart';
import '../../../../core/api/api_exception.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/storage/token_storage.dart';
import '../../admin/data/admin_repository.dart';
import '../domain/account_status.dart';
import '../domain/user.dart';

abstract class IAuthRepository {
  Future<User?> getCurrentUser();
  Future<User> updateProfile({
    String? name,
    String? phone,
    bool clearPhone = false,
    String? departmentId,
    String? programme,
    int? graduationYear,
  });
  /// Sends a code to [phone] (E.164); [verifyPhone] with that code puts it on my profile.
  Future<void> requestPhoneCode(String phone);
  Future<User> verifyPhone(String phone, String code);

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
    bool clearPhone = false,
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
    if (clearPhone) {
      // copyWith can't set a field to null, so rebuild without the phone.
      _currentUser = User.fromJson({..._currentUser!.toJson(), 'phone': null});
    }

    await tokenStorage.saveUser(_currentUser!.toJson());
    _controller.add(_currentUser);
    return _currentUser!;
  }

  @override
  Future<void> requestPhoneCode(String phone) async {}

  @override
  Future<User> verifyPhone(String phone, String code) async {
    if (code != '123456') throw Exception('Incorrect code.');
    return updateProfile(phone: phone);
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
    if (!isIiscEmail(trimmed)) {
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
    await tokenStorage.reload(); // another tab may have signed in or out
    final hasToken = await tokenStorage.hasToken();
    if (!hasToken) {
      if (_cachedUser != null) {
        _cachedUser = null;
        _controller.add(null); // signed out in another tab
      }
      return null;
    }

    try {
      final response = await apiClient.get(ApiEndpoints.me);
      if (response.data != null && response.data is Map<String, dynamic>) {
        // Roles and moderator grants come only from the server (`/me`): the database is the
        // single source of truth for who may moderate.
        _cachedUser = User.fromJson(response.data as Map<String, dynamic>);
        await tokenStorage.saveUser(_cachedUser!.toJson());
        _controller.add(_cachedUser);
        return _cachedUser;
      }
    } on ApiException catch (e) {
      // Only a rejected sign-in ends the session; a network blip or server error keeps the
      // last known user so the app doesn't sign people out while the server restarts.
      if (e.statusCode == 401 || e.statusCode == 403) {
        await tokenStorage.clearAll();
        _cachedUser = null;
        _controller.add(null);
        rethrow;
      }
      return _cachedUser;
    }
    return null;
  }

  @override
  Future<User> updateProfile({
    String? name,
    String? phone,
    bool clearPhone = false,
    String? departmentId,
    String? programme,
    int? graduationYear,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name;
    if (phone != null) payload['phone'] = phone;
    if (clearPhone) payload['phone'] = null; // null removes it
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
  Future<void> requestPhoneCode(String phone) async {
    await apiClient.post(ApiEndpoints.phoneCode, data: {'phone': phone});
  }

  @override
  Future<User> verifyPhone(String phone, String code) async {
    final response = await apiClient.post(ApiEndpoints.phoneVerify, data: {'phone': phone, 'code': code});
    _cachedUser = User.fromJson(response.data as Map<String, dynamic>);
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
    // In cloud deployment (auth_mode=cognito), Cognito emails and verifies its own code at
    // sign-up; this call 404s there and is skipped by the dialog. Locally, it emails a real code.
    final trimmed = email.trim().toLowerCase();
    if (!isIiscEmail(trimmed)) {
      throw Exception('Only valid IISc email addresses (ending in iisc.ac.in) are accepted.');
    }
    try {
      await apiClient.post(ApiEndpoints.otpRequest, data: {'email': trimmed});
    } on ApiException catch (e) {
      if (e.statusCode == 404) return; // not dev auth: nothing to send, Cognito owns this step
      rethrow;
    }
  }

  @override
  Future<User> verifyOtp(String email, String otp) async {
    // Local dev sign-in: check the code the user was emailed, then the email goes to the API in
    // the X-Dev-User header. The server creates the account on first sign-in and returns the
    // user's real roles from `/me`.
    final trimmedEmail = email.trim().toLowerCase();
    try {
      await apiClient.post(ApiEndpoints.otpVerify, data: {'email': trimmedEmail, 'otp': otp.trim()});
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow; // 404 = not dev auth; nothing to verify here
    }
    await tokenStorage.saveUser({'email': trimmedEmail, 'name': trimmedEmail.split('@').first});
    await tokenStorage.saveTokens(accessToken: 'dev_token_$trimmedEmail');

    final user = await getCurrentUser();
    if (user == null || user.email.toLowerCase() != trimmedEmail) {
      await tokenStorage.clearAll();
      _cachedUser = null;
      _controller.add(null);
      throw Exception("Couldn't reach the CampusHub server to sign you in. Check your connection and try again.");
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
    // Show the saved session straight away, then check it with the server: roles and moderator
    // grants may have changed since it was saved (e.g. a moderator was removed).
    if (_cachedUser != null) {
      unawaited(getCurrentUser().then((_) {}, onError: (_) {}));
    }
    yield* _controller.stream;
  }
}
