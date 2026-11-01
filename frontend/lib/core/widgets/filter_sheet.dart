import 'package:flutter/material.dart';

/// The pieces of the Buy & Sell and Lost & Found filter UI: one "Filters" button in the toolbar,
/// the panel it opens (a bottom sheet on phones, a side panel on wider screens) where changes are
/// a draft until "Show results", and removable chips under the toolbar for whatever is active.

/// Opens the filter panel. [sections] builds the panel's content from the draft; [update] replaces
/// the draft. "Reset" goes back to [defaults]; "Show results" hands the draft to [onApply].
Future<void> showFilterSheet<T>(
  BuildContext context, {
  required String title,
  required T initial,
  required T defaults,
  required List<Widget> Function(BuildContext context, T draft, ValueChanged<T> update) sections,
  required ValueChanged<T> onApply,
}) {
  final narrow = MediaQuery.of(context).size.width < 750;
  final sheet = _FilterSheet<T>(
    fill: !narrow,
    title: title,
    initial: initial,
    defaults: defaults,
    sections: sections,
    onApply: onApply,
  );
  if (narrow) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      builder: (_) => sheet,
    );
  }
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close filters',
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, __) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surface,
        child: SizedBox(width: 400, height: double.infinity, child: SafeArea(child: sheet)),
      ),
    ),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

class _FilterSheet<T> extends StatefulWidget {
  /// Side panel: take the full height, with "Show results" at the bottom.
  final bool fill;
  final String title;
  final T initial;
  final T defaults;
  final List<Widget> Function(BuildContext context, T draft, ValueChanged<T> update) sections;
  final ValueChanged<T> onApply;

  const _FilterSheet({
    required this.fill,
    required this.title,
    required this.initial,
    required this.defaults,
    required this.sections,
    required this.onApply,
  });

  @override
  State<_FilterSheet<T>> createState() => _FilterSheetState<T>();
}

class _FilterSheetState<T> extends State<_FilterSheet<T>> {
  late T _draft = widget.initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
          child: Row(
            children: [
              Expanded(child: Text(widget.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
              TextButton(
                key: const Key('filter_sheet_reset'),
                onPressed: () => setState(() => _draft = widget.defaults),
                child: const Text('Reset'),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          fit: widget.fill ? FlexFit.tight : FlexFit.loose,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            children: widget.sections(context, _draft, (next) => setState(() => _draft = next)),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('filter_sheet_apply'),
              onPressed: () {
                widget.onApply(_draft);
                Navigator.pop(context);
              },
              child: const Text('Show results'),
            ),
          ),
        ),
      ],
    );
  }
}

/// A titled group in the filter panel.
class FilterSection extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const FilterSection({super.key, required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold, color: theme.hintColor)),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// Chips in a filter section; [onTap] decides whether that picks one or toggles one of several.
class FilterChoices<V> extends StatelessWidget {
  final List<({V value, String label, String? icon})> options;
  final Set<V> selected;
  final ValueChanged<V> onTap;

  const FilterChoices({super.key, required this.options, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          FilterChip(
            avatar: o.icon == null ? null : Text(o.icon!, style: const TextStyle(fontSize: 13)),
            label: Text(o.label),
            selected: selected.contains(o.value),
            showCheckmark: o.icon == null,
            onSelected: (_) => onTap(o.value),
          ),
      ],
    );
  }
}

/// The toolbar button that opens the panel, with how many filters are on. [compact] (phones) is
/// just the icon with a count badge.
class FiltersButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onPressed;
  final bool compact;

  const FiltersButton({super.key, required this.activeCount, required this.onPressed, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final on = activeCount > 0;
    if (compact) {
      return IconButton.outlined(
        key: const Key('filters_button'),
        tooltip: on ? 'Filters ($activeCount on)' : 'Filters',
        isSelected: on,
        onPressed: onPressed,
        icon: Badge(
          isLabelVisible: on,
          label: Text('$activeCount'),
          child: const Icon(Icons.tune_rounded, size: 20),
        ),
      );
    }
    final label = Text(on ? 'Filters ($activeCount)' : 'Filters');
    const icon = Icon(Icons.tune_rounded, size: 18);
    return on
        ? FilledButton.tonalIcon(key: const Key('filters_button'), onPressed: onPressed, icon: icon, label: label)
        : OutlinedButton.icon(key: const Key('filters_button'), onPressed: onPressed, icon: icon, label: label);
  }
}

/// One active filter under the toolbar; its × turns that filter off.
class ActiveFilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const ActiveFilterChip({super.key, required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InputChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        visualDensity: VisualDensity.compact,
        onDeleted: onRemove,
        deleteIcon: const Icon(Icons.close_rounded, size: 16),
        deleteButtonTooltipMessage: 'Remove filter',
      ),
    );
  }
}
