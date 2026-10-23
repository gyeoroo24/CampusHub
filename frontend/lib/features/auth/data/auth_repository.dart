import 'dart:async';
import '../../../../core/api/api_client.dart';
import '../../../../core/api/api_endpoints.dart';
import '../../../../core/storage/token_storage.dart';
import '../domain/user.dart';

abstract class IAuthRepository {
  Future<User?> getCurrentUser();
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
      // Default initial mock user for development
      _currentUser = User(
        id: 'user_mock_001',
        email: 'kmukund@iisc.ac.in',
        roles: const [UserRole.signedIn],
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
      );
      // Persist the default mock session so user stays logged in
      await tokenStorage.saveUser(_currentUser!.toJson());
      await tokenStorage.saveTokens(accessToken: 'mock_token_001');
    }
  }

  @override
  Future<User?> getCurrentUser() async {
    await _init();
    return _currentUser;
  }

  @override
  Future<void> sendOtp(String email) async {
    await _init();
    final trimmed = email.trim().toLowerCase();
    if (!trimmed.endsWith('@iisc.ac.in')) {
      throw Exception('Only valid @iisc.ac.in email addresses are accepted.');
    }
    // In mock mode, any 6-digit code works
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
      roles: const [UserRole.signedIn],
      createdAt: DateTime.now(),
    );

    _currentUser = user;
    await tokenStorage.saveUser(user.toJson());
    await tokenStorage.saveTokens(accessToken: 'mock_token_${user.id}');
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

/// Real HTTP backend authentication repository using Cognito / FastAPI.
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
    if (!hasToken) {
      _cachedUser = null;
      return null;
    }

    try {
      final response = await apiClient.get(ApiEndpoints.authMe);
      if (response.data != null && response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final rolesRaw = (data['roles'] as List<dynamic>?) ?? ['signed_in'];
        final roles = rolesRaw.map((r) {
          switch (r.toString()) {
            case 'admin':
              return UserRole.admin;
            case 'moderator':
              return UserRole.moderator;
            default:
              return UserRole.signedIn;
          }
        }).toList();

        _cachedUser = User(
          id: data['id'] ?? data['sub'] ?? '',
          email: data['email'] ?? '',
          roles: roles,
          createdAt: data['created_at'] != null
              ? DateTime.parse(data['created_at'])
              : DateTime.now(),
        );
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
  Future<void> sendOtp(String email) async {
    await apiClient.post(
      ApiEndpoints.authSendOtp,
      data: {'email': email.trim().toLowerCase()},
    );
  }

  @override
  Future<User> verifyOtp(String email, String otp) async {
    final response = await apiClient.post(
      ApiEndpoints.authVerifyOtp,
      data: {
        'email': email.trim().toLowerCase(),
        'otp': otp.trim(),
      },
    );

    final data = response.data as Map<String, dynamic>;
    final token = data['access_token'] as String;
    final refreshToken = data['refresh_token'] as String?;
    await tokenStorage.saveTokens(accessToken: token, refreshToken: refreshToken);

    final user = await getCurrentUser();
    if (user == null) {
      throw Exception('Failed to load user profile after verification');
    }
    return user;
  }

  @override
  Future<User> signInWithEmail(String email) async {
    await sendOtp(email);
    throw UnimplementedError('Please use verifyOtp with user-entered OTP');
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
