import '../../../core/models/user_ref.dart';

/// Represents a flagged content report in the moderation queue (FR-10).
class ContentReport {
  final String id;
  final String module; // 'buy_sell', 'lost_found', 'academic_help', 'placement_hub'
  final String targetType; // 'listing', 'lost_report', 'found_report', etc.
  final String targetId;
  final String? targetTitle; // short title of the reported item, for the moderation queue
  final String source; // 'user', or 'system' for an automatic flag (future plan §1.6)
  final String reason;
  final String status; // 'open', 'actioned', 'dismissed'
  final UserRef? reporter;
  final DateTime createdAt;
  final DateTime? handledAt;
  final String? resolutionNote;

  const ContentReport({
    required this.id,
    required this.module,
    required this.targetType,
    required this.targetId,
    this.targetTitle,
    this.source = 'user',
    required this.reason,
    required this.status,
    this.reporter,
    required this.createdAt,
    this.handledAt,
    this.resolutionNote,
  });

  factory ContentReport.fromJson(Map<String, dynamic> json) {
    return ContentReport(
      id: json['id']?.toString() ?? '',
      module: json['module']?.toString() ?? '',
      targetType: json['target_type']?.toString() ?? '',
      targetId: json['target_id']?.toString() ?? '',
      targetTitle: json['target_title']?.toString(),
      source: json['source']?.toString() ?? 'user',
      reason: json['reason']?.toString() ?? '',
      status: json['status']?.toString() ?? 'open',
      reporter: json['reporter'] != null && json['reporter'] is Map<String, dynamic>
          ? UserRef.fromJson(json['reporter'] as Map<String, dynamic>)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      handledAt: json['handled_at'] != null
          ? DateTime.tryParse(json['handled_at'].toString())
          : null,
      resolutionNote: json['resolution_note']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'module': module,
      'target_type': targetType,
      'target_id': targetId,
      if (targetTitle != null) 'target_title': targetTitle,
      'source': source,
      'reason': reason,
      'status': status,
      if (reporter != null) 'reporter': reporter!.toJson(),
      'created_at': createdAt.toIso8601String(),
      if (handledAt != null) 'handled_at': handledAt!.toIso8601String(),
      if (resolutionNote != null) 'resolution_note': resolutionNote,
    };
  }

  ContentReport copyWith({
    String? status,
    DateTime? handledAt,
    String? resolutionNote,
  }) {
    return ContentReport(
      id: id,
      module: module,
      targetType: targetType,
      targetId: targetId,
      reason: reason,
      status: status ?? this.status,
      reporter: reporter,
      createdAt: createdAt,
      handledAt: handledAt ?? this.handledAt,
      resolutionNote: resolutionNote ?? this.resolutionNote,
    );
  }
}
