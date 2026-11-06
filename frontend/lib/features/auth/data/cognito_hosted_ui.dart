import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Tokens returned by Cognito. The API checks the ID token (its audience is the app client).
class CognitoTokens {
  final String idToken;
  final String? refreshToken;

  const CognitoTokens({required this.idToken, this.refreshToken});
}

/// Sign-in through Cognito's Hosted UI: the authorization code flow with PKCE, for a public web app
/// (no client secret). Sign-up, the emailed code and password reset all happen on the Hosted UI page.
///
/// The app's own address (with a trailing slash, no query) must be listed as a callback URL on the
/// Cognito app client, or Cognito refuses the redirect.
class CognitoHostedUi {
  CognitoHostedUi({required this.domain, required this.clientId, Dio? dio}) : _dio = dio ?? Dio();

  /// For example `campushub-dev-iisc.auth.ap-south-1.amazoncognito.com`.
  final String domain;
  final String clientId;
  final Dio _dio;

  static const _verifierKey = 'cognito_pkce_verifier';
  static const _stateKey = 'cognito_pkce_state';
  static const _charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  /// One exchange per authorization code, shared by every instance. The app can build several
  /// repositories at startup (the provider rebuilds when the server config loads), and the PKCE
  /// verifier may be spent only once; without this, a later instance found no verifier and reported
  /// the user as signed out while the first instance was still saving the tokens.
  static final Map<String, Future<CognitoTokens?>> _exchanges = {};

  /// The address the app was opened at, captured in main() before the router can rewrite it (the
  /// router turns `/?code=...` into `/buy`, which would drop the code).
  static Uri? launchUri;

  /// Sends the browser to the Hosted UI. [current] is the app's address, used to build the callback.
  Future<void> startSignIn({required Uri current, String? email, bool signUp = false}) async {
    final verifier = _random(64);
    final challenge = base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    final state = _random(32);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_verifierKey, verifier);
    await prefs.setString(_stateKey, state);

    final url = Uri.https(domain, signUp ? '/signup' : '/oauth2/authorize', {
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': _callback(current).toString(),
      'scope': 'openid email profile',
      'state': state,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      if (email != null && email.isNotEmpty) 'login_hint': email,
    });
    await launchUrl(url, webOnlyWindowName: '_self');
  }

  /// Ends the Hosted UI session, so the next sign-in asks for credentials again.
  Future<void> endSession({required Uri current}) async {
    final url = Uri.https(domain, '/logout', {
      'client_id': clientId,
      'logout_uri': _callback(current).toString(),
    });
    await launchUrl(url, webOnlyWindowName: '_self');
  }

  /// If the browser is back from the Hosted UI (it has `?code=` and `?state=`), exchanges the code for
  /// tokens. Returns null when there is nothing to complete. Throws if the code is rejected.
  Future<CognitoTokens?> completeSignIn(Uri current) async {
    final code = current.queryParameters['code'];
    final returnedState = current.queryParameters['state'];
    if (code == null || returnedState == null) return null;
    return _exchanges.putIfAbsent(code, () => _exchange(current, code, returnedState));
  }

  Future<CognitoTokens?> _exchange(Uri current, String code, String returnedState) async {
    final prefs = await SharedPreferences.getInstance();
    final verifier = prefs.getString(_verifierKey);
    final expectedState = prefs.getString(_stateKey);
    await prefs.remove(_verifierKey);
    await prefs.remove(_stateKey);
    if (verifier == null || expectedState != returnedState) return null;

    final response = await _dio.post<Map<String, dynamic>>(
      'https://$domain/oauth2/token',
      data: {
        'grant_type': 'authorization_code',
        'client_id': clientId,
        'code': code,
        'redirect_uri': _callback(current).toString(),
        'code_verifier': verifier,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    return _tokens(response.data!);
  }

  /// Gets a fresh ID token with the refresh token. Null if Cognito rejects it (the user must sign in again).
  Future<CognitoTokens?> refresh(String refreshToken) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'https://$domain/oauth2/token',
        data: {'grant_type': 'refresh_token', 'client_id': clientId, 'refresh_token': refreshToken},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      return _tokens(response.data!, fallbackRefresh: refreshToken);
    } on DioException {
      return null;
    }
  }

  CognitoTokens _tokens(Map<String, dynamic> body, {String? fallbackRefresh}) {
    return CognitoTokens(
      idToken: body['id_token'] as String,
      refreshToken: (body['refresh_token'] as String?) ?? fallbackRefresh,
    );
  }

  Uri _callback(Uri current) => Uri(scheme: current.scheme, host: current.host, port: current.hasPort ? current.port : null, path: '/');

  String _random(int length) {
    final rng = Random.secure();
    return List.generate(length, (_) => _charset[rng.nextInt(_charset.length)]).join();
  }
}
