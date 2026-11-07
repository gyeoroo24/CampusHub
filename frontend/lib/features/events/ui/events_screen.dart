import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

/// Events tab: campus events as posters, filtered by tag (FR-18), split into happening now /
/// upcoming and past (FR-19), with bookmarks and tag follows for alerts (FR-20). Opening an event
/// shows its page, with the poster, details and a discussion forum.
class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The search box starts empty on every visit (e.g. back from an event), so the filter must too.
    Future.microtask(() {
      if (!mounted) return;
      final filter = ref.read(eventsFilterProvider);
      if (filter.query.isNotEmpty) ref.read(eventsFilterProvider.notifier).state = filter.copyWith(query: '');
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final filter = ref.watch(eventsFilterProvider);
    final tagsAsync = ref.watch(eventTagsProvider);
    // Events moderators and the admin can delete a tag from its chip (move or delete its events).
    final canManageTags = ref.watch(currentUserProvider)?.canModerateModule('events') ?? false;
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
                  LayoutBuilder(builder: (context, constraints) {
                    final title = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Campus events',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        Text('Sports, culture, talks and more, posted by the Events team. Bookmark an event or follow a tag to get alerts.',
                            style: TextStyle(fontSize: 12, color: theme.hintColor)),
                      ],
                    );
                    final actions = Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => context.push('/mess'),
                          icon: const Icon(Icons.restaurant_menu_rounded, size: 18),
                          label: const Text('Mess menu'),
                        ),
                        IconButton.outlined(
                          tooltip: 'Follow tags: get alerts for new events',
                          onPressed: () => _followTags(context, ref),
                          icon: const Icon(Icons.notifications_none_rounded),
                        ),
                        // Only Events moderators and the admin add events.
                        if (ref.watch(currentUserProvider)?.canModerateModule('events') ?? false)
                          FilledButton.icon(
                            onPressed: () => _create(context, ref),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add event'),
                          ),
                      ],
                    );
                    // Below ~560px the buttons don't fit beside the title without squeezing it to
                    // nothing (letter-by-letter wrapping) -- stack them instead.
                    if (constraints.maxWidth < 560) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [title, const SizedBox(height: 10), actions],
                      );
                    }
                    return Row(
                      children: [Expanded(child: title), const SizedBox(width: 8), actions],
                    );
                  }),
                  const SizedBox(height: 10),
                  // On a phone the full labels with icons are wider than the screen, and a mouse can't
                  // drag a horizontal scroll on the web, so "Saved" was unreachable: drop the icons and
                  // shorten the first label instead, so all three always fit.
                  LayoutBuilder(builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 440;
                    return SegmentedButton<EventsView>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      segments: [
                        ButtonSegment(
                            value: EventsView.now,
                            label: Text(narrow ? 'Upcoming' : 'Now & upcoming'),
                            icon: narrow ? null : const Icon(Icons.upcoming_outlined)),
                        ButtonSegment(
                            value: EventsView.past,
                            label: const Text('Past'),
                            icon: narrow ? null : const Icon(Icons.history_rounded)),
                        ButtonSegment(
                            value: EventsView.saved,
                            label: const Text('Saved'),
                            icon: narrow ? null : const Icon(Icons.bookmark_outline_rounded)),
                      ],
                      selected: {filter.view},
                      onSelectionChanged: (s) => setFilter(filter.copyWith(view: s.first)),
                    );
                  }),
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
                    controller: _search,
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
                          // One tag at a time, like a category tab. "All" clears it; tapping the
                          // selected tag again goes back to All too.
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              visualDensity: VisualDensity.compact,
                              showCheckmark: false,
                              avatar: const Icon(Icons.apps_rounded, size: 16),
                              label: const Text('All'),
                              selected: filter.tagIds.isEmpty,
                              onSelected: (_) => setFilter(filter.copyWith(tagIds: const {})),
                            ),
                          ),
                          for (final t in tags)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              // InputChip: selectable like the others, plus its own ✕ (delete) target.
                              child: InputChip(
                                visualDensity: VisualDensity.compact,
                                showCheckmark: false,
                                onDeleted: canManageTags ? () => confirmDeleteEventTag(context, ref, t, tags) : null,
                                deleteIcon: const Icon(Icons.close_rounded, size: 14),
                                deleteButtonTooltipMessage: 'Delete "${t.name}"',
                                avatar: Icon(eventTagIcon(t.name), size: 16),
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(t.upcomingCount > 0 ? '${t.name} · ${t.upcomingCount}' : t.name),
                                    if (t.following) ...[
                                      const SizedBox(width: 4),
                                      const Icon(Icons.notifications_active_rounded, size: 13),
                                    ],
                                  ],
                                ),
                                selected: filter.tagIds.length == 1 && filter.tagIds.contains(t.id),
                                onSelected: (_) => setFilter(filter.copyWith(
                                    tagIds: filter.tagIds.length == 1 && filter.tagIds.contains(t.id) ? const {} : {t.id})),
                              ),
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
              final groups = <EventWhen, List<CampusEvent>>{};
              for (final e in events) {
                groups.putIfAbsent(e.when, () => []).add(e);
              }
              return SliverMainAxisGroup(
                slivers: [
                  for (final entry in groups.entries) ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      sliver: SliverToBoxAdapter(
                        child: Text('${entry.key.label.toUpperCase()} · ${entry.value.length}',
                            style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.bold,
                                color: entry.key == EventWhen.present ? Colors.green.shade700 : theme.hintColor)),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 300,
                          childAspectRatio: 0.66,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => EventPosterCard(event: entry.value[i]),
                          childCount: entry.value.length,
                        ),
                      ),
                    ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
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

IconData eventTagIcon(String? tag) => switch ((tag ?? '').toLowerCase()) {
      'sports' => Icons.sports_soccer_rounded,
      'food/mess' => Icons.restaurant_rounded,
      'nature' => Icons.park_rounded,
      'photography' => Icons.photo_camera_rounded,
      'culture' => Icons.theater_comedy_rounded,
      'music' => Icons.music_note_rounded,
      'tech talks' => Icons.mic_rounded,
      'workshops' => Icons.construction_rounded,
      _ => Icons.celebration_rounded,
    };

const _posterGradients = [
  [Color(0xFF4F46E5), Color(0xFF7C3AED)],
  [Color(0xFF0EA5E9), Color(0xFF14B8A6)],
  [Color(0xFFF97316), Color(0xFFDB2777)],
  [Color(0xFF16A34A), Color(0xFF65A30D)],
  [Color(0xFFDC2626), Color(0xFFF59E0B)],
  [Color(0xFF0F766E), Color(0xFF1D4ED8)],
];

/// The event's poster, or a generated one (its first tag's icon, date and title on a gradient)
/// when it has none.
class EventPoster extends StatelessWidget {
  final CampusEvent event;
  final BoxFit fit;

  /// Print the date on a generated poster (off on cards, which show a date badge instead).
  final bool showDate;

  const EventPoster({super.key, required this.event, this.fit = BoxFit.cover, this.showDate = true});

  @override
  Widget build(BuildContext context) {
    final e = event;
    final generated = _GeneratedPoster(event: e, showDate: showDate);
    if (e.posterUrl == null) return generated;
    return Image.network(e.posterUrl!, fit: fit, gaplessPlayback: true, errorBuilder: (_, __, ___) => generated);
  }
}

class _GeneratedPoster extends StatelessWidget {
  final CampusEvent event;
  final bool showDate;

  const _GeneratedPoster({required this.event, required this.showDate});

  @override
  Widget build(BuildContext context) {
    final e = event;
    final colors = _posterGradients[e.title.codeUnits.fold<int>(0, (a, b) => a + b) % _posterGradients.length];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -24,
            bottom: -24,
            child: Icon(eventTagIcon(e.tags.isEmpty ? null : e.tags.first.name),
                size: 150, color: Colors.white.withValues(alpha: 0.16)),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, showDate ? 28 : 72, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showDate)
                  Text('${_weekdays[e.startTime.weekday - 1]} ${e.startTime.day} ${_months[e.startTime.month - 1]}'.toUpperCase(),
                    style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 1)),
                if (showDate) const SizedBox(height: 6),
                Text(e.title,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22, height: 1.15)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// An event as a poster card: the poster with the date and bookmark on it, then the title, time,
/// place and tags. Opens the event's page.
class EventPosterCard extends StatefulWidget {
  final CampusEvent event;

  const EventPosterCard({super.key, required this.event});

  @override
  State<EventPosterCard> createState() => _EventPosterCardState();
}

class _EventPosterCardState extends State<EventPosterCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final e = widget.event;
    final live = e.when == EventWhen.present;
    final past = e.when == EventWhen.past;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: live
                ? Colors.green.shade500
                : (_hovered
                    ? theme.colorScheme.primary.withValues(alpha: 0.6)
                    : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))),
            width: live || _hovered ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? (_hovered ? 0.4 : 0.2) : (_hovered ? 0.08 : 0.03)),
              blurRadius: _hovered ? 16 : 8,
              offset: Offset(0, _hovered ? 6 : 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go('/events/${e.id}'),
          child: Opacity(
            opacity: past ? 0.7 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 13,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      EventPoster(event: e, showDate: false),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.center,
                              colors: [Colors.black.withValues(alpha: 0.35), Colors.transparent],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          width: 46,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4)],
                          ),
                          child: Column(
                            children: [
                              Text(_months[e.startTime.month - 1].toUpperCase(),
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
                              Text('${e.startTime.day}',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87, height: 1.1)),
                            ],
                          ),
                        ),
                      ),
                      if (live)
                        Positioned(
                          top: 12,
                          left: 64,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: Colors.green.shade600, borderRadius: BorderRadius.circular(6)),
                            child: const Text('LIVE',
                                style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 0.6)),
                          ),
                        ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                          child: IconTheme(
                            data: const IconThemeData(color: Colors.white),
                            child: EventBookmarkButton(event: e, onDark: true),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 7,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, height: 1.2)),
                        const SizedBox(height: 4),
                        Row(children: [
                          Icon(Icons.schedule_rounded, size: 13, color: theme.hintColor),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(eventTimeRange(e), maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: theme.hintColor)),
                          ),
                        ]),
                        if (e.location != null)
                          Row(children: [
                            Icon(Icons.place_outlined, size: 13, color: theme.hintColor),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(e.location!, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: theme.hintColor)),
                            ),
                          ]),
                        const Spacer(),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final t in e.tags.take(3))
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
                ),
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

  /// Drawn over a poster: white icons.
  final bool onDark;

  const EventBookmarkButton({super.key, required this.event, this.onDark = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarked = ref.watch(isEventBookmarkedProvider(event));
    return IconButton(
      tooltip: bookmarked ? 'Remove bookmark' : 'Bookmark',
      icon: Icon(bookmarked ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
          color: onDark ? Colors.white : (bookmarked ? Theme.of(context).colorScheme.primary : null)),
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
