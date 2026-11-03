import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/server_config.dart';
import '../../auth/domain/user.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/events_repository.dart';
import '../domain/event_models.dart';

final eventsRepositoryProvider = Provider<IEventsRepository>((ref) {
  if (ref.watch(serverConfigProvider).useMockData) {
    return MockEventsRepository();
  }
  return ApiEventsRepository(ref.watch(apiClientProvider));
});

/// Which part of the timeline the Events tab shows.
enum EventsView { now, past, saved }

class EventsFilter {
  final EventsView view;
  final Set<int> tagIds;
  final String query;

  const EventsFilter({this.view = EventsView.now, this.tagIds = const {}, this.query = ''});

  EventsFilter copyWith({EventsView? view, Set<int>? tagIds, String? query}) =>
      EventsFilter(view: view ?? this.view, tagIds: tagIds ?? this.tagIds, query: query ?? this.query);
}

final eventsFilterProvider = StateProvider<EventsFilter>((ref) => const EventsFilter());

final eventTagsProvider = FutureProvider<List<EventTag>>((ref) {
  ref.watch(currentUserProvider); // "following" depends on who is viewing
  return ref.watch(eventsRepositoryProvider).fetchTags();
});

// ---------------------------------------------------------------- guest bookmarks (on this device)
class GuestBookmarksNotifier extends StateNotifier<Set<String>> {
  final GuestBookmarks _store;

  GuestBookmarksNotifier(this._store) : super(const {}) {
    _store.load().then((ids) {
      if (mounted) state = ids;
    });
  }

  void toggle(String eventId) {
    state = state.contains(eventId) ? ({...state}..remove(eventId)) : {...state, eventId};
    _store.save(state);
  }

  void clear() {
    state = const {};
    _store.save(state);
  }
}

final guestBookmarksProvider = StateNotifierProvider<GuestBookmarksNotifier, Set<String>>(
  (ref) => GuestBookmarksNotifier(GuestBookmarks()),
);

bool _isGuest(User? user) => user == null || user.isGuest;

/// When someone signs in, the events they bookmarked as a guest move to their account.
/// Watched by the app shell so it runs whichever tab is open.
final guestBookmarkSyncProvider = Provider<void>((ref) {
  ref.listen<User?>(currentUserProvider, (previous, next) async {
    if (_isGuest(next) || !_isGuest(previous)) return;
    final ids = ref.read(guestBookmarksProvider).toList();
    if (ids.isEmpty) return;
    try {
      await ref.read(eventsRepositoryProvider).importBookmarks(ids);
      ref.read(guestBookmarksProvider.notifier).clear();
      ref.invalidate(eventsProvider);
    } catch (_) {
      // Keep them on the device and try again at the next sign-in.
    }
  });
});

// ---------------------------------------------------------------- events
final eventsProvider = FutureProvider<List<CampusEvent>>((ref) async {
  final filter = ref.watch(eventsFilterProvider);
  final guest = _isGuest(ref.watch(currentUserProvider));
  final guestSaved = guest ? ref.watch(guestBookmarksProvider) : const <String>{};
  final repo = ref.watch(eventsRepositoryProvider);
  final events = await repo.fetchEvents(
    when: switch (filter.view) {
      EventsView.now => {EventWhen.present, EventWhen.upcoming},
      EventsView.past => {EventWhen.past},
      EventsView.saved => EventWhen.values.toSet(),
    },
    tagIds: filter.tagIds,
    query: filter.query,
    bookmarkedOnly: filter.view == EventsView.saved && !guest,
  );
  if (!guest) return events;
  final marked = [for (final e in events) e.copyWith(isBookmarked: guestSaved.contains(e.id))];
  return filter.view == EventsView.saved ? marked.where((e) => e.isBookmarked).toList() : marked;
});

final eventProvider = FutureProvider.family<CampusEvent, String>((ref, eventId) async {
  final guest = _isGuest(ref.watch(currentUserProvider));
  final event = await ref.watch(eventsRepositoryProvider).getEvent(eventId);
  return guest ? event.copyWith(isBookmarked: ref.watch(guestBookmarksProvider).contains(eventId)) : event;
});

/// Bookmark or un-bookmark: on the account when signed in, on this device for guests.
Future<void> toggleEventBookmark(WidgetRef ref, CampusEvent event) async {
  if (_isGuest(ref.read(currentUserProvider))) {
    ref.read(guestBookmarksProvider.notifier).toggle(event.id);
    return;
  }
  await ref.read(eventsRepositoryProvider).setBookmarked(event.id, !event.isBookmarked);
  ref.invalidate(eventsProvider);
  ref.invalidate(eventProvider(event.id));
}

final eventUpdatesProvider = FutureProvider.autoDispose.family<List<EventUpdate>, String>((ref, eventId) {
  ref.watch(currentUserProvider); // can_delete depends on who is viewing
  return ref.watch(eventsRepositoryProvider).fetchUpdates(eventId);
});
