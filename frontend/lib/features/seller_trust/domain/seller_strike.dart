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
  /// Null once the seller deleted the listing (the title is a copy kept with the strike).
  final String? listingId;
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
      listingId: json['listing_id']?.toString(),
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

/// How many strikes I have against the limits (GET /me/seller-strikes/summary).
class StrikeSummary {
  final int strikes;
  final int severe;
  final int nonSevere;
  final int limit;
  final int negativeAt;
  final int severeLimit;
  final String? tag;
  final bool suspended;

  const StrikeSummary({
    this.strikes = 0,
    this.severe = 0,
    this.nonSevere = 0,
    this.limit = 3,
    this.negativeAt = 2,
    this.severeLimit = 1,
    this.tag,
    this.suspended = false,
  });

  factory StrikeSummary.fromJson(Map<String, dynamic> j) => StrikeSummary(
        strikes: (j['strikes'] as num?)?.toInt() ?? 0,
        severe: (j['severe'] as num?)?.toInt() ?? 0,
        nonSevere: (j['non_severe'] as num?)?.toInt() ?? 0,
        limit: (j['limit'] as num?)?.toInt() ?? 3,
        negativeAt: (j['negative_at'] as num?)?.toInt() ?? 2,
        severeLimit: (j['severe_limit'] as num?)?.toInt() ?? 1,
        tag: j['tag'] as String?,
        suspended: j['suspended'] == true,
      );
}
