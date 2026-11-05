import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/widgets/error_state.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/ui/auth_dialog.dart';
import '../mess_models.dart';
import 'menu_editor.dart';

const _mealIcons = {
  'breakfast': Icons.free_breakfast_outlined,
  'lunch': Icons.lunch_dining_outlined,
  'snacks': Icons.cookie_outlined,
  'dinner': Icons.dinner_dining_outlined,
};

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));

/// Confirms, then removes a mess with its menus and followers (Events moderator or admin). Shared by
/// the mess tag's delete button and the mess header's own delete button.
Future<void> deleteMess(BuildContext context, WidgetRef ref, Mess mess, {VoidCallback? onDeleted}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Delete “${mess.name}”?'),
      content: const Text('Its menus and anyone\'s meal alerts for it go with it. This can\'t be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await ref.read(apiClientProvider).delete(ApiEndpoints.mess(mess.id));
    ref.invalidate(messListProvider);
    onDeleted?.call();
  } catch (e) {
    if (context.mounted) _snack(context, errorText(e));
  }
}

/// `/mess`: each mess's menu for today and the week, and meal alerts. Events moderators post the menus.
class MessScreen extends ConsumerStatefulWidget {
  final int? initialMessId;

  const MessScreen({super.key, this.initialMessId});

  @override
  ConsumerState<MessScreen> createState() => _MessScreenState();
}

class _MessScreenState extends ConsumerState<MessScreen> {
  late int? _messId = widget.initialMessId;

  Future<void> _addMess() async {
    final saved = await showDialog<bool>(context: context, builder: (_) => const MessFormDialog());
    if (saved == true) ref.invalidate(messListProvider);
  }

  /// Upload a menu for any mess (a new name adds the mess); its meals are read from the file for review.
  Future<void> _upload(List<Mess> messes) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MenuEditorDialog(messes: messes),
    );
    if (saved == true) {
      ref.invalidate(messListProvider);
      for (final m in messes) {
        ref.invalidate(messMenusProvider(m.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(messListProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/events'),
        ),
        title: const Text('Mess menus'),
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(message: errorText(e), onRetry: () => ref.invalidate(messListProvider)),
        data: (list) {
          final messes = list.messes;
          if (messes.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.restaurant_menu_rounded, size: 48),
                    const SizedBox(height: 12),
                    const Text('No mess menus yet.', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(list.canManage ? 'Upload a mess\'s menu (PDF or photo): the meals are read in for you to check.'
                        : 'Events moderators post each mess\'s menu here.', textAlign: TextAlign.center),
                    if (list.canManage) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                          onPressed: () => _upload(const []),
                          icon: const Icon(Icons.upload_file_rounded),
                          label: const Text('Upload a mess menu')),
                    ],
                  ],
                ),
              ),
            );
          }
          final mess = messes.firstWhere((m) => m.id == _messId, orElse: () => messes.first);
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final m in messes)
                        InputChip(
                          showCheckmark: false,
                          avatar: Icon(Icons.restaurant_rounded, size: 16,
                              color: m.followingMeals != null ? Theme.of(context).colorScheme.primary : null),
                          label: Text(m.name),
                          selected: m.id == mess.id,
                          onSelected: (_) => setState(() => _messId = m.id),
                          deleteIcon: list.canManage ? const Icon(Icons.close_rounded, size: 16) : null,
                          onDeleted: list.canManage
                              ? () => deleteMess(context, ref, m, onDeleted: () => setState(() => _messId = null))
                              : null,
                        ),
                      // A mess's menu is posted from its own page ("Post a menu"); new messes start here.
                      if (list.canManage)
                        TextButton.icon(onPressed: _addMess, icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add a mess')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _MessHeader(mess: mess, canManage: list.canManage, onDeleted: () => setState(() => _messId = null)),
                  const SizedBox(height: 12),
                  _TodayCard(mess: mess),
                  const SizedBox(height: 12),
                  _Menus(mess: mess, canManage: list.canManage),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MessHeader extends ConsumerWidget {
  final Mess mess;
  final bool canManage;

  /// Called after the mess is deleted, so the screen can pick a different one to show.
  final VoidCallback? onDeleted;

  const _MessHeader({required this.mess, required this.canManage, this.onDeleted});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final following = mess.followingMeals;
    final times = [for (final m in meals) '${mealLabels[m]} ${formatClock(mess.mealTimes[m] ?? '00:00')}'].join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(mess.name, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              Text(times, style: TextStyle(fontSize: 12, color: theme.hintColor)),
            ],
          ),
        ),
        if (canManage)
          IconButton(
            tooltip: 'Edit mess',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final saved = await showDialog<bool>(context: context, builder: (_) => MessFormDialog(mess: mess));
              if (saved == true) ref.invalidate(messListProvider);
            },
          ),
        if (canManage)
          IconButton(
            tooltip: 'Delete mess',
            icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
            onPressed: () => deleteMess(context, ref, mess, onDeleted: onDeleted),
          ),
        const SizedBox(width: 4),
        following == null
            ? FilledButton.icon(
                onPressed: () => _alerts(context, ref),
                icon: const Icon(Icons.notifications_none_rounded, size: 18),
                label: const Text('Meal alerts'),
              )
            : OutlinedButton.icon(
                onPressed: () => _alerts(context, ref),
                icon: const Icon(Icons.notifications_active_rounded, size: 18),
                label: Text(following.length == 4 ? 'Alerts: every meal'
                    : 'Alerts: ${following.map((m) => mealLabels[m]).join(', ')}'),
              ),
      ],
    );
  }

  Future<void> _alerts(BuildContext context, WidgetRef ref) async {
    final ok = await AuthDialog.ensureSignedIn(context, ref, title: 'Sign in for meal alerts',
        message: 'Sign in to get what\'s on the menu shortly before each meal.');
    if (ok != true || !context.mounted) return;
    final chosen = await showDialog<List<String>>(context: context, builder: (_) => _AlertsDialog(mess: mess));
    if (chosen == null) return;
    try {
      await ref.read(apiClientProvider).put(ApiEndpoints.messFollow(mess.id), data: {'meals': chosen});
      ref.invalidate(messListProvider);
      if (context.mounted) {
        _snack(context, chosen.isEmpty ? 'Meal alerts for ${mess.name} are off.'
            : 'You\'ll get ${mess.name}\'s menu 30 minutes before ${chosen.map((m) => mealLabels[m]!.toLowerCase()).join(', ')}.');
      }
    } catch (e) {
      if (context.mounted) _snack(context, errorText(e));
    }
  }
}

class _AlertsDialog extends StatefulWidget {
  final Mess mess;

  const _AlertsDialog({required this.mess});

  @override
  State<_AlertsDialog> createState() => _AlertsDialogState();
}

class _AlertsDialogState extends State<_AlertsDialog> {
  late final Set<String> _meals = {...(widget.mess.followingMeals ?? meals)};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Meal alerts for ${widget.mess.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Get the day\'s dishes 30 minutes before the meals you pick.'),
          const SizedBox(height: 8),
          for (final m in meals)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _meals.contains(m),
              secondary: Icon(_mealIcons[m]),
              title: Text(mealLabels[m]!),
              subtitle: Text(formatClock(widget.mess.mealTimes[m] ?? '00:00')),
              onChanged: (v) => setState(() => v == true ? _meals.add(m) : _meals.remove(m)),
            ),
        ],
      ),
      actions: [
        if (widget.mess.followingMeals != null)
          TextButton(onPressed: () => Navigator.pop(context, <String>[]), child: const Text('Turn off')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _meals.isEmpty ? null : () => Navigator.pop(context, [for (final m in meals) if (_meals.contains(m)) m]),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _TodayCard extends StatelessWidget {
  final Mess mess;

  const _TodayCard({required this.mess});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    // The meal on now, or the next one: the first whose start is less than ~an hour ago.
    final highlight = mess.today.where((t) => now.isBefore(t.startsAt.add(const Duration(minutes: 75)))).firstOrNull;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Today, ${weekdayLabels[now.weekday - 1]} ${DateTimeFormatter.shortDate(now)}',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (mess.today.isEmpty && mess.currentMenuId != null)
              Text('This menu was posted as a file. Open it below to see today\'s meals.',
                  style: TextStyle(color: theme.hintColor))
            else if (mess.today.isEmpty)
              Text(mess.nextMenuFrom == null ? 'No menu posted for today.'
                  : 'No menu for today. The next one starts ${DateTimeFormatter.shortDate(mess.nextMenuFrom!)}.',
                  style: TextStyle(color: theme.hintColor))
            else
              LayoutBuilder(builder: (context, c) {
                final columns = c.maxWidth > 640 ? 4 : (c.maxWidth > 360 ? 2 : 1);
                final width = (c.maxWidth - 10 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final t in mess.today)
                      SizedBox(
                        width: width,
                        child: _MealBox(
                          meal: t.meal,
                          time: formatClock(mess.mealTimes[t.meal] ?? '00:00'),
                          items: t.items,
                          highlighted: identical(t, highlight),
                        ),
                      ),
                  ],
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _MealBox extends StatelessWidget {
  final String meal;
  final String time;
  final String items;
  final bool highlighted;

  const _MealBox({required this.meal, required this.time, required this.items, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: highlighted ? primary : theme.dividerColor.withValues(alpha: 0.4),
            width: highlighted ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_mealIcons[meal], size: 18, color: primary),
              const SizedBox(width: 6),
              Expanded(child: Text(mealLabels[meal]!, style: const TextStyle(fontWeight: FontWeight.bold))),
              Text(time, style: TextStyle(fontSize: 12, color: theme.hintColor)),
            ],
          ),
          if (highlighted)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Next up', style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w700)),
            ),
          const SizedBox(height: 6),
          Text(items, style: const TextStyle(fontSize: 13, height: 1.35)),
        ],
      ),
    );
  }
}

class _Menus extends ConsumerWidget {
  final Mess mess;
  final bool canManage;

  const _Menus({required this.mess, required this.canManage});

  Future<void> _edit(BuildContext context, WidgetRef ref, {MessMenu? menu, DateTime? from}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MenuEditorDialog(mess: mess, menu: menu, suggestedFrom: from),
    );
    if (saved == true) {
      ref.invalidate(messMenusProvider(mess.id));
      ref.invalidate(messListProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final menusAsync = ref.watch(messMenusProvider(mess.id));
    return menusAsync.when(
      loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
      error: (e, _) => Text(errorText(e), style: TextStyle(color: theme.colorScheme.error)),
      data: (menus) {
        final today = DateTime.now();
        final current = menus.where((m) => m.covers(today)).firstOrNull;
        final upcoming = menus.where((m) => m.validFrom.isAfter(today)).toList();
        final past = menus.where((m) => m.validTo.isBefore(DateTime(today.year, today.month, today.day))).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A new menu replaces the mess's menu from its first day (the API trims or removes the old one),
            // so it starts today by default rather than after the last menu.
            if (canManage)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () => _edit(context, ref),
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: Text(current == null ? 'Post a menu' : 'Post a new menu'),
                ),
              ),
            if (canManage && (current != null || upcoming.isNotEmpty))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('A new menu replaces this mess\'s menu from its first day.',
                    style: TextStyle(fontSize: 12, color: theme.hintColor)),
              ),
            if (canManage) const SizedBox(height: 12),
            if (current != null)
              _MenuCard(menu: current, title: 'This menu', canManage: canManage,
                  onEdit: () => _edit(context, ref, menu: current))
            else
              Text('No menu is in force today.', style: TextStyle(color: theme.hintColor)),
            for (final m in upcoming) ...[
              const SizedBox(height: 12),
              _MenuCard(menu: m, title: 'Next menu', canManage: canManage, onEdit: () => _edit(context, ref, menu: m)),
            ],
            if (past.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Earlier menus', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              for (final m in past)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history_rounded),
                  title: Text('${DateTimeFormatter.shortDate(m.validFrom)} – ${DateTimeFormatter.shortDate(m.validTo)}'),
                  trailing: m.fileUrl == null
                      ? null
                      : TextButton(onPressed: () => _openFile(context, m.fileUrl!), child: const Text('Open file')),
                ),
            ],
          ],
        );
      },
    );
  }
}

Future<void> _openFile(BuildContext context, String url) async {
  if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication) && context.mounted) {
    _snack(context, "Couldn't open the file.");
  }
}

class _MenuCard extends ConsumerStatefulWidget {
  final MessMenu menu;
  final String title;
  final bool canManage;
  final VoidCallback onEdit;

  const _MenuCard({required this.menu, required this.title, required this.canManage, required this.onEdit});

  @override
  ConsumerState<_MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends ConsumerState<_MenuCard> {
  late int _day = widget.menu.covers(DateTime.now()) ? DateTime.now().weekday : 1;

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove this menu?'),
        content: const Text('Meal alerts stop for these dates.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).delete(ApiEndpoints.messMenu(widget.menu.id));
      ref.invalidate(messMenusProvider(widget.menu.messId));
      ref.invalidate(messListProvider);
    } catch (e) {
      if (mounted) _snack(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final menu = widget.menu;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      Text('${DateTimeFormatter.shortDate(menu.validFrom)} – ${DateTimeFormatter.shortDate(menu.validTo)}'
                          ' · repeats every week', style: TextStyle(fontSize: 12, color: theme.hintColor)),
                    ],
                  ),
                ),
                if (menu.fileUrl != null)
                  TextButton.icon(
                    onPressed: () => _openFile(context, menu.fileUrl!),
                    icon: Icon(menu.fileType == 'pdf' ? Icons.picture_as_pdf_outlined : Icons.image_outlined, size: 18),
                    label: Text(menu.fileType == 'pdf' ? 'Menu PDF' : 'Menu photo'),
                  ),
                if (widget.canManage)
                  PopupMenuButton<String>(
                    onSelected: (v) => v == 'edit' ? widget.onEdit() : _delete(),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Remove')),
                    ],
                  ),
              ],
            ),
            if (menu.notes != null) ...[
              const SizedBox(height: 6),
              Text(menu.notes!, style: const TextStyle(fontSize: 13)),
            ],
            if (menu.items.isEmpty && menu.fileUrl != null) ...[
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: () => _openFile(context, menu.fileUrl!),
                icon: Icon(menu.fileType == 'pdf' ? Icons.picture_as_pdf_outlined : Icons.image_outlined),
                label: Text(menu.fileType == 'pdf' ? 'Open the menu (PDF)' : 'Open the menu (photo)'),
              ),
            ] else ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  for (var d = 1; d <= 7; d++) ButtonSegment(value: d, label: Text(weekdayLabels[d - 1].substring(0, 3))),
                ],
                selected: {_day},
                onSelectionChanged: (s) => setState(() => _day = s.first),
              ),
            ),
            const SizedBox(height: 10),
            for (final m in meals)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_mealIcons[m], size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    SizedBox(width: 80, child: Text(mealLabels[m]!, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Expanded(
                      child: Text(menu.items[(_day, m)] ?? '—',
                          style: TextStyle(color: menu.items[(_day, m)] == null ? theme.hintColor : null)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
