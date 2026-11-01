import '../../../core/models/user_ref.dart';

/// 'none' (no appeal filed), 'pending' (needs a moderator), 'rejected' or 'overturned'.
enum AppealStatus {
  none,
  pending,
  rejected,
  overturned;

  static AppealStatus fromString(String val) {
    return AppealStatus.values.firstWhere((v) => v.name == val, orElse: () => AppealStatus.none);
  }
}

/// One moderator-confirmed listing removal against a seller (future plan §1.5). Never from a raw
/// report - only from a moderator resolving a report by removing the listing.
class SellerStrike {
  final String id;
  final UserRef seller;
  final String listingId;
  final String listingTitle;
  final bool listingHidden;
  final String severity; // 'severe' | 'non_severe'
  final String? moderatorNote;
  final bool excluded;
  final String? appealMessage;
  final DateTime? appealCreatedAt;
  final AppealStatus appealStatus;
  final DateTime createdAt;

  const SellerStrike({
    required this.id,
    required this.seller,
    required this.listingId,
    required this.listingTitle,
    required this.listingHidden,
    required this.severity,
    this.moderatorNote,
    required this.excluded,
    this.appealMessage,
    this.appealCreatedAt,
    required this.appealStatus,
    required this.createdAt,
  });

  bool get isSevere => severity == 'severe';
  bool get canAppeal => appealMessage == null && !excluded;

  factory SellerStrike.fromJson(Map<String, dynamic> json) {
    return SellerStrike(
      id: json['id'].toString(),
      seller: UserRef.fromJson(json['seller'] as Map<String, dynamic>),
      listingId: json['listing_id'].toString(),
      listingTitle: json['listing_title']?.toString() ?? '',
      listingHidden: json['listing_hidden'] as bool? ?? false,
      severity: json['severity']?.toString() ?? 'non_severe',
      moderatorNote: json['moderator_note']?.toString(),
      excluded: json['excluded'] as bool? ?? false,
      appealMessage: json['appeal_message']?.toString(),
      appealCreatedAt: json['appeal_created_at'] != null
          ? DateTime.tryParse(json['appeal_created_at'].toString())
          : null,
      appealStatus: AppealStatus.fromString(json['appeal_status']?.toString() ?? 'none'),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
