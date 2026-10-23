import 'package:dio/dio.dart';
import '../constants/app_config.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

/// Central HTTP Client built on Dio with token injection and error transformation.
class ApiClient {
  final Dio dio;
  final ITokenStorage tokenStorage;

  ApiClient({
    Dio? dioClient,
    ITokenStorage? storage,
  })  : dio = dioClient ??
            Dio(
              BaseOptions(
                baseUrl: AppConfig.apiBaseUrl,
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
          final token = await tokenStorage.getAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
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
