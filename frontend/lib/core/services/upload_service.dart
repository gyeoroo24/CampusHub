import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../api/api_exception.dart';
import '../../features/auth/providers/auth_providers.dart';

final uploadServiceProvider = Provider<UploadService>((ref) {
  return UploadService(apiClient: ref.watch(apiClientProvider));
});

/// Presigned upload ticket returned by `POST /api/v1/uploads`.
class UploadTicket {
  final String s3Key;
  final String uploadUrl;
  final String method;
  final Map<String, String> headers;
  final int expiresIn;

  const UploadTicket({
    required this.s3Key,
    required this.uploadUrl,
    required this.method,
    required this.headers,
    required this.expiresIn,
  });

  factory UploadTicket.fromJson(Map<String, dynamic> json) {
    return UploadTicket(
      s3Key: json['s3_key']?.toString() ?? '',
      uploadUrl: json['upload_url']?.toString() ?? '',
      method: json['method']?.toString() ?? 'PUT',
      headers: (json['headers'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v.toString()),
          ) ??
          {},
      expiresIn: json['expires_in'] is int
          ? json['expires_in'] as int
          : int.tryParse(json['expires_in']?.toString() ?? '900') ?? 900,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      's3_key': s3Key,
      'upload_url': uploadUrl,
      'method': method,
      'headers': headers,
      'expires_in': expiresIn,
    };
  }
}

/// Service handling the 3-step direct S3 file upload workflow (PRD NFR-8).
///
/// 1. Request upload ticket from FastAPI with SHA-256 base64 digest.
/// 2. PUT binary bytes directly to the presigned S3 URL with required checksum headers.
/// 3. Returns the resulting [s3Key] to be attached to listing or report creations.
class UploadService {
  final ApiClient apiClient;
  final Dio _rawDio;

  UploadService({
    required this.apiClient,
    Dio? rawDio,
  }) : _rawDio = rawDio ?? Dio();

  /// Computes the base64-encoded SHA-256 digest of file bytes (required by FastAPI/S3).
  static String computeSha256Base64(Uint8List bytes) {
    final digest = sha256.convert(bytes);
    return base64.encode(digest.bytes);
  }

  /// Step 1: Request an upload ticket from `/api/v1/uploads`.
  Future<UploadTicket> getUploadTicket({
    required String kind,
    required String contentType,
    required int sizeBytes,
    required String checksumSha256,
    String? courseId,
  }) async {
    final response = await apiClient.post(
      ApiEndpoints.uploads,
      data: {
        'kind': kind,
        'content_type': contentType,
        'size_bytes': sizeBytes,
        'checksum_sha256': checksumSha256,
        if (courseId != null) 'course_id': courseId,
      },
    );

    if (response.data is Map<String, dynamic>) {
      return UploadTicket.fromJson(response.data as Map<String, dynamic>);
    }
    throw ApiException(
      message: 'Unexpected response from upload ticket endpoint',
      statusCode: response.statusCode,
    );
  }

  /// Step 2: PUT raw binary bytes to the presigned S3 [ticket.uploadUrl].
  Future<void> uploadToS3(
    UploadTicket ticket,
    Uint8List fileBytes, {
    ProgressCallback? onProgress,
  }) async {
    try {
      await _rawDio.put(
        ticket.uploadUrl,
        // Raw bytes, not a stream, so the browser adapter can send them. The browser sets
        // Content-Length itself (scripts may not); the signed headers come from the ticket.
        data: fileBytes,
        options: Options(
          headers: ticket.headers,
          sendTimeout: const Duration(minutes: 5),
        ),
        onSendProgress: onProgress,
      );
    } on DioException catch (e) {
      throw ApiException(
        message: 'Failed to upload file to S3: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Convenience full upload workflow: computes checksum -> requests ticket -> PUTs to S3 -> returns s3_key.
  Future<String> uploadPhoto({
    required Uint8List bytes,
    required String kind, // 'listing_photo', 'lost_report_photo', 'found_report_photo'
    String contentType = 'image/jpeg',
    ProgressCallback? onProgress,
  }) async {
    final checksum = computeSha256Base64(bytes);
    final ticket = await getUploadTicket(
      kind: kind,
      contentType: contentType,
      sizeBytes: bytes.length,
      checksumSha256: checksum,
    );

    await uploadToS3(ticket, bytes, onProgress: onProgress);
    return ticket.s3Key;
  }

  /// Convenience batch upload workflow for multiple photos.
  Future<List<String>> uploadMultiplePhotos({
    required List<Uint8List> photos,
    required String kind,
    String contentType = 'image/jpeg',
  }) async {
    final List<String> s3Keys = [];
    for (final photoBytes in photos) {
      final key = await uploadPhoto(
        bytes: photoBytes,
        kind: kind,
        contentType: contentType,
      );
      s3Keys.add(key);
    }
    return s3Keys;
  }
}
