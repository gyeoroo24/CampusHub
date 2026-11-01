import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../domain/event_models.dart';

/// Community events, tags, followed tags and event bookmarks.
abstract class IEventsRepository {
  Future<List<EventTag>> fetchTags();

  /// [when] defaults to happening now + upcoming. [tagIds] = events carrying any of them.
  Future<List<CampusEvent>> fetchEvents(
      {Set<EventWhen> when = const {EventWhen.present, EventWhen.upcoming}, Set<int> tagIds = const {},
      String? query, bool bookmarkedOnly = false, int limit = 50});

  Future<CampusEvent> getEvent(String eventId);

  Future<CampusEvent> createEvent(EventDraft draft);

  Future<CampusEvent> updateEvent(String eventId, EventDraft draft);

  Future<void> deleteEvent(String eventId);

  Future<void> setBookmarked(String eventId, bool bookmarked);

  Future<void> setFollowing(int tagId, bool following);

  /// Saves bookmarks a guest kept on the device to the account; returns how many were added.
  Future<int> importBookmarks(List<String> eventIds);

  Future<EventTag> createTag(String name);
}

class ApiEventsRepository implements IEventsRepository {
  final ApiClient apiClient;

  ApiEventsRepository(this.apiClient);

  @override
  Future<List<EventTag>> fetchTags() async {
    final response = await apiClient.get(ApiEndpoints.eventTags);
    return (response.data as List<dynamic>).map((j) => EventTag.fromJson(j as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<CampusEvent>> fetchEvents(
      {Set<EventWhen> when = const {EventWhen.present, EventWhen.upcoming}, Set<int> tagIds = const {},
      String? query, bool bookmarkedOnly = false, int limit = 50}) async {
    final response = await apiClient.get(ApiEndpoints.events, queryParameters: {
      'when': when.map((w) => w.name).toList(),
      if (tagIds.isNotEmpty) 'tag_id': tagIds.toList(),
      if ((query ?? '').trim().isNotEmpty) 'q': query!.trim(),
      if (bookmarkedOnly) 'bookmarked': true,
      'limit': limit,
    });
    final items = (response.data as Map<String, dynamic>)['items'] as List<dynamic>? ?? [];
    return items.map((j) => CampusEvent.fromJson(j as Map<String, dynamic>)).toList();
  }

  @override
  Future<CampusEvent> getEvent(String eventId) async {
    final response = await apiClient.get(ApiEndpoints.event(eventId));
    return CampusEvent.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<CampusEvent> createEvent(EventDraft draft) async {
    final response = await apiClient.post(ApiEndpoints.events, data: draft.toJson());
    return CampusEvent.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<CampusEvent> updateEvent(String eventId, EventDraft draft) async {
    final response = await apiClient.patch(ApiEndpoints.event(eventId), data: draft.toJson());
    return CampusEvent.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    await apiClient.delete(ApiEndpoints.event(eventId));
  }

  @override
  Future<void> setBookmarked(String eventId, bool bookmarked) async {
    final path = ApiEndpoints.bookmark('event', eventId);
    if (bookmarked) {
      await apiClient.put(path);
    } else {
      await apiClient.delete(path);
    }
  }

  @override
  Future<void> setFollowing(int tagId, bool following) async {
    final path = ApiEndpoints.followedTag(tagId);
    if (following) {
      await apiClient.put(path);
    } else {
      await apiClient.delete(path);
    }
  }

  @override
  Future<int> importBookmarks(List<String> eventIds) async {
    if (eventIds.isEmpty) return 0;
    final response = await apiClient.post(ApiEndpoints.bookmarksImport, data: {
      'items': [for (final id in eventIds) {'target_type': 'event', 'target_id': id}],
    });
    return ((response.data as Map<String, dynamic>)['added'] as int?) ?? 0;
  }

  @override
  Future<EventTag> createTag(String name) async {
    final response = await apiClient.post(ApiEndpoints.eventTags, data: {'name': name});
    return EventTag.fromJson(response.data as Map<String, dynamic>);
  }
}

/// Guests' event bookmarks, kept on this device only (PRD §3.1). After sign-in they are
/// imported to the account and cleared here.
class GuestBookmarks {
  static const _key = 'guest_event_bookmarks';

  Future<Set<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_key) ?? const []).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> save(Set<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, ids.toList());
    } catch (_) {
      // Storage unavailable (e.g. private browsing): bookmarks last for this session only.
    }
  }
}

/// In-memory version for mock mode.
class MockEventsRepository implements IEventsRepository {
  static final _tags = <EventTag>[
    const EventTag(id: 1, name: 'Culture'),
    const EventTag(id: 2, name: 'Food/Mess'),
    const EventTag(id: 3, name: 'Nature'),
    const EventTag(id: 4, name: 'Photography'),
    const EventTag(id: 5, name: 'Sports'),
    const EventTag(id: 6, name: 'Tech Talks'),
  ];

  static final List<CampusEvent> _events = _seed();

  static List<CampusEvent> _seed() {
    final now = DateTime.now();
    CampusEvent e(String id, String title, int tag, Duration offset, int hours, String place, String desc) {
      final start = now.add(offset);
      final end = start.add(Duration(hours: hours));
      return CampusEvent(
        id: id, title: title, description: desc, location: place, startTime: start, endTime: end,
        when: now.isBefore(start) ? EventWhen.upcoming : (now.isAfter(end) ? EventWhen.past : EventWhen.present),
        tags: [_tags.firstWhere((t) => t.id == tag)], organizerId: 'u_1', organizerName: 'Ananya Rao',
        updatedAt: now,
      );
    }

    return [
      e('ev_1', 'Bird walk around the campus', 3, const Duration(days: 2), 2, 'Main gate',
          'Spot over 40 species on a 2-hour morning walk. Binoculars available.'),
      e('ev_2', 'Music club open jam', 1, const Duration(hours: -1), 3, "Students' Gymkhana",
          'Bring an instrument or just listen.'),
      e('ev_3', 'Inter-hostel cricket league', 5, const Duration(days: 6), 4, 'Gymkhana ground',
          'Teams of 11 from every hostel. Register by Friday.'),
      e('ev_4', 'Photography walk: heritage buildings', 4, const Duration(days: -8), 2, 'Main Building',
          'Golden-hour walk; phones welcome.'),
      e('ev_5', 'CDS seminar: serverless at scale', 6, const Duration(days: 12), 1, 'CDS seminar hall',
          'A talk on cold starts and cost at scale.'),
    ];
  }

  @override
  Future<List<EventTag>> fetchTags() async => [
        for (final t in _tags)
          EventTag(id: t.id, name: t.name, following: t.following,
              upcomingCount: _events.where((e) => e.when != EventWhen.past && e.tags.any((x) => x.id == t.id)).length),
      ];

  @override
  Future<List<CampusEvent>> fetchEvents(
      {Set<EventWhen> when = const {EventWhen.present, EventWhen.upcoming}, Set<int> tagIds = const {},
      String? query, bool bookmarkedOnly = false, int limit = 50}) async {
    final q = (query ?? '').trim().toLowerCase();
    final list = _events
        .where((e) => when.contains(e.when))
        .where((e) => tagIds.isEmpty || e.tags.any((t) => tagIds.contains(t.id)))
        .where((e) => q.isEmpty || e.title.toLowerCase().contains(q) || (e.description ?? '').toLowerCase().contains(q))
        .where((e) => !bookmarkedOnly || e.isBookmarked)
        .toList()
      ..sort((a, b) {
        if (a.when != b.when) return a.when.index.compareTo(b.when.index);
        return a.when == EventWhen.past ? b.startTime.compareTo(a.startTime) : a.startTime.compareTo(b.startTime);
      });
    return list.take(limit).toList();
  }

  @override
  Future<CampusEvent> getEvent(String eventId) async {
    final match = _events.where((e) => e.id == eventId);
    if (match.isEmpty) throw Exception('Event not found.');
    return match.first;
  }

  CampusEvent _fromDraft(String id, EventDraft d, {CampusEvent? old}) {
    final now = DateTime.now();
    return CampusEvent(
      id: id, title: d.title, description: d.description, location: d.location, startTime: d.startTime,
      endTime: d.endTime,
      when: now.isBefore(d.startTime) ? EventWhen.upcoming : (now.isAfter(d.endTime) ? EventWhen.past : EventWhen.present),
      tags: _tags.where((t) => d.tagIds.contains(t.id)).toList(), organizerId: 'me', organizerName: 'You',
      bookmarkCount: old?.bookmarkCount ?? 0, isBookmarked: old?.isBookmarked ?? false, canEdit: true, updatedAt: now,
    );
  }

  @override
  Future<CampusEvent> createEvent(EventDraft draft) async {
    final event = _fromDraft('ev_${DateTime.now().microsecondsSinceEpoch}', draft);
    _events.add(event);
    return event;
  }

  @override
  Future<CampusEvent> updateEvent(String eventId, EventDraft draft) async {
    final i = _events.indexWhere((e) => e.id == eventId);
    if (i < 0) throw Exception('Event not found.');
    _events[i] = _fromDraft(eventId, draft, old: _events[i]);
    return _events[i];
  }

  @override
  Future<void> deleteEvent(String eventId) async => _events.removeWhere((e) => e.id == eventId);

  @override
  Future<void> setBookmarked(String eventId, bool bookmarked) async {
    final i = _events.indexWhere((e) => e.id == eventId);
    if (i < 0 || _events[i].isBookmarked == bookmarked) return;
    _events[i] = _events[i].copyWith(
        isBookmarked: bookmarked, bookmarkCount: _events[i].bookmarkCount + (bookmarked ? 1 : -1));
  }

  @override
  Future<void> setFollowing(int tagId, bool following) async {
    final i = _tags.indexWhere((t) => t.id == tagId);
    if (i >= 0) _tags[i] = _tags[i].copyWith(following: following);
  }

  @override
  Future<int> importBookmarks(List<String> eventIds) async {
    for (final id in eventIds) {
      await setBookmarked(id, true);
    }
    return eventIds.length;
  }

  @override
  Future<EventTag> createTag(String name) async {
    final tag = EventTag(id: _tags.length + 1, name: name);
    _tags.add(tag);
    return tag;
  }
}
