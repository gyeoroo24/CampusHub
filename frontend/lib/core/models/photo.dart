/// Attached photo metadata.
/// [url] is a presigned GET URL (expires in ~1 hour).
/// [s3Key] is the persistent key stored on S3.
class Photo {
  final String s3Key;
  final String url;
  final int sortOrder;

  const Photo({
    required this.s3Key,
    required this.url,
    required this.sortOrder,
  });

  factory Photo.fromJson(Map<String, dynamic> json) {
    return Photo(
      s3Key: json['s3_key']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      sortOrder: json['sort_order'] is int
          ? json['sort_order'] as int
          : int.tryParse(json['sort_order']?.toString() ?? '0') ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      's3_key': s3Key,
      'url': url,
      'sort_order': sortOrder,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Photo &&
          runtimeType == other.runtimeType &&
          s3Key == other.s3Key &&
          url == other.url &&
          sortOrder == other.sortOrder;

  @override
  int get hashCode => s3Key.hashCode ^ url.hashCode ^ sortOrder.hashCode;
}
