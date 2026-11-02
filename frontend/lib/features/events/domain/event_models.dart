/// Community Events read models (FR-18, FR-19, FR-20).
library;

/// Worked out by the server from the current time (FR-19).
enum EventWhen {
  present('Happening now'),
  upcoming('Upcoming'),
  past('Past');

  final String label;

  const EventWhen(this.label);

  static EventWhen parse(dynamic v) => EventWhen.values.firstWhere((w) => w.name == v, orElse: () => EventWhen.upcoming);
}

class EventTag {
  final int id;
  final String name;

  /// Events with this tag that haven't ended.
  final int upcomingCount;
  final bool following;

  const EventTag({required this.id, required this.name, this.upcomingCount = 0, this.following = false});

  factory EventTag.fromJson(Map<String, dynamic> json) => EventTag(
        id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id']}') ?? 0,
        name: json['name']?.toString() ?? '',
        upcomingCount: json['upcoming_count'] is int ? json['upcoming_count'] as int : 0,
        following: json['following'] == true,
      );

  EventTag copyWith({bool? following}) =>
      EventTag(id: id, name: name, upcomingCount: upcomingCount, following: following ?? this.following);
}

class CampusEvent {
  final String id;
  final String title;
  final String? description;
  final String? location;
  final DateTime startTime;
  final DateTime endTime;
  final EventWhen when;
  final List<EventTag> tags;

  /// Short-lived link to the poster image, if the event has one.
  final String? posterUrl;
  final String organizerId;
  final String organizerName;
  final int bookmarkCount;

  /// From the server for signed-in users; from the device for guests (see GuestBookmarks).
  final bool isBookmarked;
  final bool canEdit;

  /// A mess's card: kept in step with its menu (open the mess page for the full menu).
  final int? messId;
  final DateTime updatedAt;

  const CampusEvent({
    required this.id,
    required this.title,
    this.description,
    this.location,
    required this.startTime,
    required this.endTime,
    required this.when,
    this.tags = const [],
    this.posterUrl,
    required this.organizerId,
    required this.organizerName,
    this.bookmarkCount = 0,
    this.isBookmarked = false,
    this.canEdit = false,
    this.messId,
    required this.updatedAt,
  });

  factory CampusEvent.fromJson(Map<String, dynamic> json) => CampusEvent(
        id: '${json['id']}',
        title: json['title']?.toString() ?? '',
        description: json['description']?.toString(),
        location: json['location']?.toString(),
        startTime: DateTime.parse('${json['start_time']}').toLocal(),
        endTime: DateTime.parse('${json['end_time']}').toLocal(),
        when: EventWhen.parse(json['when']),
        tags: (json['tags'] as List<dynamic>? ?? [])
            .map((t) => EventTag.fromJson(t as Map<String, dynamic>))
            .toList(),
        posterUrl: json['poster_url'] == null || '${json['poster_url']}'.isEmpty ? null : '${json['poster_url']}',
        organizerId: '${(json['organizer'] as Map?)?['id'] ?? ''}',
        organizerName: '${(json['organizer'] as Map?)?['name'] ?? ''}',
        bookmarkCount: json['bookmark_count'] is int ? json['bookmark_count'] as int : 0,
        isBookmarked: json['is_bookmarked'] == true,
        canEdit: json['can_edit'] == true,
        messId: (json['mess_id'] as num?)?.toInt(),
        updatedAt: DateTime.tryParse('${json['updated_at']}')?.toLocal() ?? DateTime.now(),
      );

  CampusEvent copyWith({bool? isBookmarked, int? bookmarkCount}) => CampusEvent(
        id: id,
        title: title,
        description: description,
        location: location,
        startTime: startTime,
        endTime: endTime,
        when: when,
        tags: tags,
        posterUrl: posterUrl,
        organizerId: organizerId,
        organizerName: organizerName,
        bookmarkCount: bookmarkCount ?? this.bookmarkCount,
        isBookmarked: isBookmarked ?? this.isBookmarked,
        messId: messId,
        canEdit: canEdit,
        updatedAt: updatedAt,
      );
}

/// What an event form sends to create or edit an event.
class EventDraft {
  final String title;
  final String? description;
  final String? location;
  final DateTime startTime;
  final DateTime endTime;
  final List<int> tagIds;

  /// A newly uploaded poster (s3_key), or null to leave the poster as it is.
  final String? posterKey;

  /// Take the current poster off (when editing).
  final bool removePoster;

  const EventDraft({
    required this.title,
    this.description,
    this.location,
    required this.startTime,
    required this.endTime,
    required this.tagIds,
    this.posterKey,
    this.removePoster = false,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': (description ?? '').trim().isEmpty ? null : description!.trim(),
        'location': (location ?? '').trim().isEmpty ? null : location!.trim(),
        'start_time': startTime.toUtc().toIso8601String(),
        'end_time': endTime.toUtc().toIso8601String(),
        'tag_ids': tagIds,
        if (posterKey != null) 'poster_s3_key': posterKey else if (removePoster) 'poster_s3_key': null,
      };
}
