import 'package:dio/dio.dart';
import '../constants/app_config.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

/// Central HTTP Client built on Dio with token injection and error transformation.
class ApiClient {
  final Dio dio;
  final ITokenStorage tokenStorage;

  /// Optional development user email for local FastAPI dev auth (`X-Dev-User`)
  final String? devUserEmail;
  final String? devUserName;
  final String? devKey;

  ApiClient({
    Dio? dioClient,
    ITokenStorage? storage,
    this.devUserEmail,
    this.devUserName,
    this.devKey,
    String? baseUrl,
  })  : dio = dioClient ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl ?? AppConfig.apiBaseUrl,
                connectTimeout: AppConfig.connectTimeout,
                receiveTimeout: AppConfig.receiveTimeout,
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ),
            ),
        tokenStorage = storage ?? InMemoryTokenStorage() {
    _setupInterceptors();
  }

  void _setupInterceptors() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Do not attach backend auth headers if uploading directly to external S3 / storage URLs
          final isExternal = options.path.startsWith('http://') || options.path.startsWith('https://');
          final activeBase = dio.options.baseUrl;
          if (!isExternal || (activeBase.isNotEmpty && options.path.startsWith(activeBase))) {
            final activeDevKey = devKey ?? AppConfig.devKey;
            if (activeDevKey.isNotEmpty) {
              options.headers['X-Dev-Key'] = activeDevKey;
            }

            final token = await tokenStorage.getAccessToken();
            final savedUser = await tokenStorage.getSavedUser();
            final email = savedUser?['email'] as String? ?? devUserEmail;
            final name = savedUser?['name'] as String? ?? devUserName;

            if (token != null && token.isNotEmpty && !token.startsWith('dev_token_')) {
              options.headers['Authorization'] = 'Bearer $token';
            } else if (email != null && email.isNotEmpty) {
              // Local and LAN testing headers supported by CampusHub backend
              options.headers['X-Dev-User'] = email;
              if (name != null && name.isNotEmpty) {
                options.headers['X-Dev-Name'] = name;
              }
            }
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) {
          // Wrap with our typed ApiException
          final appError = ApiException.fromDioException(error);
          return handler.reject(
            DioException(
              requestOptions: error.requestOptions,
              response: error.response,
              type: error.type,
              error: appError,
              message: appError.message,
            ),
          );
        },
      ),
    );
  }

  /// Convenience GET request
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await dio.get<T>(path, queryParameters: queryParameters, options: options);
    } on DioException catch (e) {
      if (e.error is ApiException) {
        throw e.error as ApiException;
      }
      throw ApiException.fromDioException(e);
    }
  }

  /// Convenience POST request
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await dio.post<T>(path, data: data, queryParameters: queryParameters, options: options);
    } on DioException catch (e) {
      if (e.error is ApiException) {
        throw e.error as ApiException;
      }
      throw ApiException.fromDioException(e);
    }
  }

  /// Convenience PUT request (used for photo list replacement and direct S3 uploads)
  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    ProgressCallback? onSendProgress,
  }) async {
    try {
      return await dio.put<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        onSendProgress: onSendProgress,
      );
    } on DioException catch (e) {
      if (e.error is ApiException) {
        throw e.error as ApiException;
      }
      throw ApiException.fromDioException(e);
    }
  }

  /// Convenience PATCH request
  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await dio.patch<T>(path, data: data, queryParameters: queryParameters, options: options);
    } on DioException catch (e) {
      if (e.error is ApiException) {
        throw e.error as ApiException;
      }
      throw ApiException.fromDioException(e);
    }
  }

  /// Convenience DELETE request
  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await dio.delete<T>(path, data: data, queryParameters: queryParameters, options: options);
    } on DioException catch (e) {
      if (e.error is ApiException) {
        throw e.error as ApiException;
      }
      throw ApiException.fromDioException(e);
    }
  }
}
