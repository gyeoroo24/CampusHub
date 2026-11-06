import 'package:dio/dio.dart';

/// Base exception class for API and network failures.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic details;

  const ApiException({
    required this.message,
    this.statusCode,
    this.details,
  });

  factory ApiException.fromDioException(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const NetworkTimeoutException(
          message: 'Connection timed out. Please check your network and try again.',
        );

      case DioExceptionType.connectionError:
        return const NetworkConnectionException(
          message: 'Unable to connect to CampusHub servers. Please verify your connection.',
        );

      case DioExceptionType.badResponse:
        final status = error.response?.statusCode;
        final data = error.response?.data;
        String extractedMsg = 'Server responded with status $status';

        if (data is Map<String, dynamic>) {
          extractedMsg = data['detail']?.toString() ??
              data['message']?.toString() ??
              extractedMsg;
        }

        if (status == 401) {
          return UnauthorizedException(message: extractedMsg, details: data);
        } else if (status == 403) {
          return ForbiddenException(message: extractedMsg, details: data);
        } else if (status == 404) {
          return NotFoundException(message: extractedMsg, details: data);
        } else if (status == 503) {
          return ServiceUnavailableException(message: extractedMsg, details: data);
        } else if (status != null && status >= 500) {
          return ServerException(message: extractedMsg, statusCode: status, details: data);
        }

        return ApiException(
          message: extractedMsg,
          statusCode: status,
          details: data,
        );

      case DioExceptionType.cancel:
        return const ApiException(message: 'Request was cancelled.');

      default:
        return ApiException(
          message: error.message ?? 'An unexpected network error occurred.',
          details: error.error,
        );
    }
  }

  @override
  String toString() => 'ApiException: $message (Status: $statusCode)';
}

class NetworkTimeoutException extends ApiException {
  const NetworkTimeoutException({required super.message}) : super(statusCode: 408);
}

class NetworkConnectionException extends ApiException {
  const NetworkConnectionException({required super.message});
}

class UnauthorizedException extends ApiException {
  const UnauthorizedException({required super.message, super.details})
      : super(statusCode: 401);
}

class ForbiddenException extends ApiException {
  const ForbiddenException({required super.message, super.details})
      : super(statusCode: 403);
}

class NotFoundException extends ApiException {
  const NotFoundException({required super.message, super.details})
      : super(statusCode: 404);
}

class ServerException extends ApiException {
  const ServerException({
    required super.message,
    super.statusCode,
    super.details,
  });
}

class ServiceUnavailableException extends ApiException {
  const ServiceUnavailableException({
    required super.message,
    super.details,
  }) : super(statusCode: 503);
}
