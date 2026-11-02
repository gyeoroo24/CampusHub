import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/widgets/photo_picker_field.dart';
import '../../forums/domain/forum_models.dart';
import '../../forums/ui/forum_board.dart';
import '../domain/event_models.dart';
import '../providers/events_providers.dart';
import 'events_screen.dart' show EventBookmarkButton, EventPoster, eventTimeRange;

void _snack(BuildContext context, String message) => ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));

/// An event's details with bookmark, and edit / cancel for its organizer (or an admin).
class _EventDetails extends ConsumerWidget {
  final CampusEvent event;

  /// Called after the event is cancelled (closes the dialog or leaves the page).
  final VoidCallback onRemoved;

  const _EventDetails({required this.event, required this.onRemoved});

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Cancel “${event.title}”?'),
        content: const Text('The event is removed, and people who bookmarked it are told it was cancelled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel event'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(eventsRepositoryProvider).deleteEvent(event.id);
      ref.invalidate(eventsProvider);
      ref.invalidate(eventTagsProvider);
      onRemoved();
    } catch (e) {
      if (context.mounted) _snack(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final e = event;
    final live = e.when == EventWhen.present;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (live ? Colors.green : (e.when == EventWhen.past ? Colors.grey : theme.colorScheme.primary))
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(e.when.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),
                  Text(e.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            EventBookmarkButton(event: e),
          ],
        ),
        const SizedBox(height: 12),
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule_rounded),
          title: Text(eventTimeRange(e)),
        ),
        if (e.location != null)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.place_outlined),
            title: Text(e.location!),
          ),
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline_rounded),
          title: Text('Posted by ${e.organizerName}'),
          subtitle: Text([
            if (e.bookmarkCount > 0) '${e.bookmarkCount} ${e.bookmarkCount == 1 ? 'person' : 'people'} saved this',
            'updated ${DateTimeFormatter.timeAgo(e.updatedAt)}',
          ].join(' · ')),
        ),
        if (e.tags.isNotEmpty)
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in e.tags) Chip(visualDensity: VisualDensity.compact, label: Text(t.name)),
          ]),
        if (e.description != null) ...[
          const SizedBox(height: 12),
          SelectableText(e.description!),
        ],
        if (e.canEdit) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final saved =
                      await showDialog<CampusEvent>(context: context, builder: (_) => EventFormDialog(event: e));
                  if (saved != null) {
                    ref.invalidate(eventProvider(e.id));
                    ref.invalidate(eventsProvider);
                  }
                },
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                onPressed: () => _cancel(context, ref),
                icon: const Icon(Icons.event_busy_outlined, size: 16),
                label: const Text('Cancel event'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class EventDetailDialog extends ConsumerWidget {
  final String eventId;

  const EventDetailDialog({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: ref.watch(eventProvider(eventId)).when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text(errorText(e)),
                data: (event) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (event.posterUrl != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(height: 260, child: EventPoster(event: event, fit: BoxFit.contain)),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _EventDetails(event: event, onRemoved: () => Navigator.pop(context)),
                  ],
                ),
              ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

/// /events/:id: the poster, the details, and the event's discussion forum. Opened from the Events
/// page, a notification or a shared link.
class EventDetailScreen extends ConsumerWidget {
  final String eventId;

  const EventDetailScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to events',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/events'),
        ),
        title: const Text('Event'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ref.watch(eventProvider(eventId)).when(
                  skipLoadingOnReload: true,
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text(errorText(e)),
                  data: (event) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          color: Colors.black,
                          height: event.posterUrl == null ? 220 : 420,
                          child: EventPoster(event: event, fit: BoxFit.contain),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _EventDetails(event: event, onRemoved: () => context.go('/events')),
                      if (event.messId != null) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            onPressed: () => context.push('/mess?mess=${event.messId}'),
                            icon: const Icon(Icons.restaurant_menu_rounded, size: 18),
                            label: const Text('Full weekly menu and meal alerts'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          const Icon(Icons.forum_outlined, size: 20),
                          const SizedBox(width: 8),
                          Text('Discussion', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ForumBoard(
                        scope: ForumScope.event,
                        scopeId: event.id,
                        placeName: event.title,
                        blurb: 'ask about it, find people to go with, share photos after',
                        embedded: true,
                      ),
                    ],
                  ),
                ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- create / edit
class EventFormDialog extends ConsumerStatefulWidget {
  final CampusEvent? event;

  const EventFormDialog({super.key, this.event});

  @override
  ConsumerState<EventFormDialog> createState() => _EventFormDialogState();
}

class _EventFormDialogState extends ConsumerState<EventFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.event?.title);
  late final _location = TextEditingController(text: widget.event?.location);
  late final _description = TextEditingController(text: widget.event?.description);
  late DateTime _start = widget.event?.startTime ?? _nextHour();
  late DateTime _end = widget.event?.endTime ?? _nextHour().add(const Duration(hours: 2));
  late final Set<int> _tags = {...?widget.event?.tags.map((t) => t.id)};
  List<PickedPhoto> _poster = const [];
  late bool _keepPoster = widget.event?.posterUrl != null;
  bool _busy = false;
  String? _error;

  static DateTime _nextHour() {
    final now = DateTime.now().add(const Duration(days: 1));
    return DateTime(now.year, now.month, now.day, 17);
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime initial) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: now.add(const Duration(days: 395)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_tags.isEmpty) {
      setState(() => _error = 'Pick at least one tag.');
      return;
    }
    if (!_end.isAfter(_start)) {
      setState(() => _error = 'The event must end after it starts.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(eventsRepositoryProvider);
      String? posterKey;
      if (_poster.isNotEmpty) {
        final uploaded = await uploadPickedPhotos(ref, _poster, kind: 'event_poster');
        posterKey = uploaded.first.s3Key.isEmpty ? null : uploaded.first.s3Key;
      }
      final draft = EventDraft(
        title: _title.text.trim(),
        description: _description.text,
        location: _location.text,
        startTime: _start,
        endTime: _end,
        tagIds: _tags.toList(),
        posterKey: posterKey,
        removePoster: widget.event?.posterUrl != null && !_keepPoster && _poster.isEmpty,
      );
      final saved = widget.event == null ? await repo.createEvent(draft) : await repo.updateEvent(widget.event!.id, draft);
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tags = ref.watch(eventTagsProvider).valueOrNull ?? const <EventTag>[];
    Widget timeRow(String label, DateTime value, ValueChanged<DateTime> onPicked) => Row(
          children: [
            SizedBox(width: 56, child: Text(label, style: TextStyle(color: theme.hintColor))),
            Expanded(child: Text(DateTimeFormatter.fullDateTime(value), style: const TextStyle(fontWeight: FontWeight.w600))),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      final picked = await _pick(value);
                      if (picked != null) onPicked(picked);
                    },
              child: const Text('Change'),
            ),
          ],
        );

    return AlertDialog(
      title: Text(widget.event == null ? 'Add an event' : 'Edit event'),
      content: SizedBox(
        width: 540,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _title,
                  maxLength: 150,
                  decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 4),
                timeRow('Starts', _start, (t) => setState(() {
                      final length = _end.difference(_start);
                      _start = t;
                      if (!_end.isAfter(_start)) _end = _start.add(length.isNegative ? const Duration(hours: 2) : length);
                    })),
                timeRow('Ends', _end, (t) => setState(() => _end = t)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _location,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Where', hintText: "e.g. Students' Gymkhana",
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 4),
                Text('Tags (up to 5)', style: TextStyle(color: theme.hintColor, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in tags)
                      FilterChip(
                        label: Text(t.name),
                        selected: _tags.contains(t.id),
                        onSelected: (on) => setState(() {
                          if (on && _tags.length < 5) {
                            _tags.add(t.id);
                          } else {
                            _tags.remove(t.id);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_keepPoster && _poster.isEmpty) ...[
                  Text('Poster', style: TextStyle(color: theme.hintColor, fontSize: 12)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(width: 72, height: 96, child: EventPoster(event: widget.event!)),
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        onPressed: _busy ? null : () => setState(() => _keepPoster = false),
                        icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                        label: const Text('Replace or remove'),
                      ),
                    ],
                  ),
                ] else
                  PhotoPickerField(
                    photos: _poster,
                    maxPhotos: 1,
                    enabled: !_busy,
                    label: 'Poster (optional). Without one, a poster is made from the title and tag.',
                    onChanged: (p) => setState(() => _poster = p),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 5000,
                  decoration: const InputDecoration(labelText: 'Details', hintText: 'What, who it is for, how to join…',
                      border: OutlineInputBorder()),
                ),
                if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.event == null ? 'Post event' : 'Save'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- follow tags
class FollowTagsDialog extends ConsumerStatefulWidget {
  const FollowTagsDialog({super.key});

  @override
  ConsumerState<FollowTagsDialog> createState() => _FollowTagsDialogState();
}

class _FollowTagsDialogState extends ConsumerState<FollowTagsDialog> {
  final Set<int> _busy = {};

  Future<void> _toggle(EventTag tag, bool follow) async {
    setState(() => _busy.add(tag.id));
    try {
      await ref.read(eventsRepositoryProvider).setFollowing(tag.id, follow);
      ref.invalidate(eventTagsProvider);
      await ref.read(eventTagsProvider.future);
    } catch (e) {
      if (mounted) _snack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy.remove(tag.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Follow tags'),
      content: SizedBox(
        width: 400,
        child: ref.watch(eventTagsProvider).when(
              loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Text(errorText(e)),
              data: (tags) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Get a notification when a new event is posted under these tags.',
                      style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final t in tags)
                          SwitchListTile(
                            dense: true,
                            title: Text(t.name),
                            value: t.following,
                            onChanged: _busy.contains(t.id) ? null : (v) => _toggle(t, v),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
    );
  }
}
