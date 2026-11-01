import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/ui/auth_dialog.dart';
import '../domain/event_models.dart';
import '../providers/events_providers.dart';
import 'event_dialogs.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _time(DateTime t) => '${t.hour % 12 == 0 ? 12 : t.hour % 12}:${t.minute.toString().padLeft(2, '0')} '
    '${t.hour < 12 ? 'am' : 'pm'}';

/// "Sat 8 Nov, 5:30 – 7:30 pm", or with both dates when it spans days.
String eventTimeRange(CampusEvent e) {
  final s = e.startTime, end = e.endTime;
  final day = '${_weekdays[s.weekday - 1]} ${s.day} ${_months[s.month - 1]}';
  final sameDay = s.year == end.year && s.month == end.month && s.day == end.day;
  if (sameDay) return '$day, ${_time(s)} – ${_time(end)}';
  return '$day, ${_time(s)} – ${_weekdays[end.weekday - 1]} ${end.day} ${_months[end.month - 1]}, ${_time(end)}';
}

/// Events tab: a timeline of campus events, filtered by tag (FR-18), split into happening now /
/// upcoming and past (FR-19), with bookmarks and tag follows for alerts (FR-20).
class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final filter = ref.watch(eventsFilterProvider);
    final tagsAsync = ref.watch(eventTagsProvider);
    final eventsAsync = ref.watch(eventsProvider);
    final isGuest = ref.watch(isGuestUserProvider);

    void setFilter(EventsFilter f) => ref.read(eventsFilterProvider.notifier).state = f;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(eventsProvider);
        ref.invalidate(eventTagsProvider);
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              color: theme.cardColor,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Campus events',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            Text('Sports, culture, talks and more. Bookmark an event or follow a tag to get alerts.',
                                style: TextStyle(fontSize: 12, color: theme.hintColor)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => _create(context, ref),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add event'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<EventsView>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      segments: const [
                        ButtonSegment(value: EventsView.now, label: Text('Now & upcoming'), icon: Icon(Icons.upcoming_outlined)),
                        ButtonSegment(value: EventsView.past, label: Text('Past'), icon: Icon(Icons.history_rounded)),
                        ButtonSegment(value: EventsView.saved, label: Text('Saved'), icon: Icon(Icons.bookmark_outline_rounded)),
                      ],
                      selected: {filter.view},
                      onSelectionChanged: (s) => setFilter(filter.copyWith(view: s.first)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded, size: 18),
                      hintText: 'Search events, places…',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setFilter(ref.read(eventsFilterProvider).copyWith(query: v)),
                  ),
                  const SizedBox(height: 8),
                  tagsAsync.maybeWhen(
                    data: (tags) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final t in tags)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FilterChip(
                                visualDensity: VisualDensity.compact,
                                avatar: t.following ? const Icon(Icons.notifications_active_rounded, size: 14) : null,
                                label: Text(t.upcomingCount > 0 ? '${t.name} (${t.upcomingCount})' : t.name),
                                selected: filter.tagIds.contains(t.id),
                                onSelected: (on) => setFilter(filter.copyWith(
                                    tagIds: on ? {...filter.tagIds, t.id} : ({...filter.tagIds}..remove(t.id)))),
                              ),
                            ),
                          TextButton.icon(
                            onPressed: () => _followTags(context, ref),
                            icon: const Icon(Icons.notifications_none_rounded, size: 16),
                            label: const Text('Follow tags'),
                          ),
                        ],
                      ),
                    ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
          if (isGuest && filter.view == EventsView.saved)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text('Saved on this device. Sign in to keep them in your account and get alerts when they change.',
                    style: TextStyle(fontSize: 12, color: theme.hintColor)),
              ),
            ),
          eventsAsync.when(
            loading: () => const SliverToBoxAdapter(child: SkeletonList(itemCount: 4)),
            error: (e, _) => SliverToBoxAdapter(
              child: ErrorState(message: errorText(e), onRetry: () => ref.invalidate(eventsProvider)),
            ),
            data: (events) {
              if (events.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        switch (filter.view) {
                          EventsView.saved => 'No saved events. Tap the bookmark on an event to save it.',
                          EventsView.past => 'No past events here.',
                          EventsView.now => filter.tagIds.isEmpty && filter.query.trim().isEmpty
                              ? 'Nothing planned yet. Add the first event!'
                              : 'No events match these filters.',
                        },
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.hintColor),
                      ),
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final e = events[i];
                      final header = i == 0 || events[i - 1].when != e.when;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (header)
                            Padding(
                              padding: const EdgeInsets.only(top: 10, bottom: 6),
                              child: Text(e.when.label.toUpperCase(),
                                  style: TextStyle(
                                      fontSize: 11,
                                      letterSpacing: 0.8,
                                      fontWeight: FontWeight.bold,
                                      color: e.when == EventWhen.present ? Colors.green.shade700 : theme.hintColor)),
                            ),
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 860),
                              child: EventCard(event: e),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      );
                    },
                    childCount: events.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final signedIn = await AuthDialog.ensureSignedIn(context, ref,
        title: 'Sign in to add an event', message: 'Sign in with your IISc email to add a campus event.');
    if (!signedIn || !context.mounted) return;
    final created = await showDialog<CampusEvent>(context: context, builder: (_) => const EventFormDialog());
    if (created != null) {
      ref.invalidate(eventsProvider);
      ref.invalidate(eventTagsProvider);
    }
  }

  Future<void> _followTags(BuildContext context, WidgetRef ref) async {
    final signedIn = await AuthDialog.ensureSignedIn(context, ref,
        title: 'Sign in to follow tags', message: 'Sign in to get alerts when new events are posted under a tag.');
    if (!signedIn || !context.mounted) return;
    await showDialog(context: context, builder: (_) => const FollowTagsDialog());
    ref.invalidate(eventTagsProvider);
  }
}

class EventCard extends ConsumerWidget {
  final CampusEvent event;

  const EventCard({super.key, required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final e = event;
    final live = e.when == EventWhen.present;
    final past = e.when == EventWhen.past;
    final accent = live ? Colors.green.shade600 : theme.colorScheme.primary;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: live ? accent.withValues(alpha: 0.6) : theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        // The dialog refreshes the list itself after a bookmark, edit or cancellation.
        onTap: () => showDialog(context: context, builder: (_) => EventDetailDialog(eventId: e.id)),
        child: Opacity(
          opacity: past ? 0.75 : 1.0,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 54,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    children: [
                      Text(_months[e.startTime.month - 1].toUpperCase(),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accent)),
                      Text('${e.startTime.day}',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: accent, height: 1.1)),
                      Text(_weekdays[e.startTime.weekday - 1], style: TextStyle(fontSize: 11, color: accent)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (live)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4)),
                              child: const Text('LIVE',
                                  style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          Expanded(
                            child: Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(eventTimeRange(e), style: TextStyle(fontSize: 12, color: theme.hintColor)),
                      if (e.location != null)
                        Row(
                          children: [
                            Icon(Icons.place_outlined, size: 13, color: theme.hintColor),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Text(e.location!, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: theme.hintColor)),
                            ),
                          ],
                        ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final t in e.tags)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(t.name, style: const TextStyle(fontSize: 11)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                EventBookmarkButton(event: e),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EventBookmarkButton extends ConsumerWidget {
  final CampusEvent event;

  const EventBookmarkButton({super.key, required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: event.isBookmarked ? 'Remove bookmark' : 'Bookmark',
      icon: Icon(event.isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
          color: event.isBookmarked ? Theme.of(context).colorScheme.primary : null),
      onPressed: () async {
        try {
          await toggleEventBookmark(ref, event);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(errorText(e)), behavior: SnackBarBehavior.floating));
          }
        }
      },
    );
  }
}
