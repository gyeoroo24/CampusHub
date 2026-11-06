import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/error_text.dart';
import '../domain/placement_models.dart';
import '../providers/placement_providers.dart';

/// Review companies that are probably one company under different names ("Accenture",
/// "Accenture [Mock Assessment]"). Each group can be merged under a common name, with the companies that
/// don't belong unticked, or kept apart. Nothing is merged until the moderator confirms.
class SimilarCompaniesReview extends ConsumerStatefulWidget {
  final List<SimilarCompanyGroup> groups;

  /// Called after merging (with how many groups were merged), or when the moderator skips.
  final ValueChanged<int> onDone;

  const SimilarCompaniesReview({super.key, required this.groups, required this.onDone});

  @override
  ConsumerState<SimilarCompaniesReview> createState() => _SimilarCompaniesReviewState();
}

class _SimilarCompaniesReviewState extends ConsumerState<SimilarCompaniesReview> {
  late final List<TextEditingController> _names =
      [for (final g in widget.groups) TextEditingController(text: g.suggestedName)];
  late final List<Set<String>> _picked = [for (final g in widget.groups) {for (final c in g.companies) c.id}];
  late final List<bool> _merge = [for (final _ in widget.groups) true];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _apply() async {
    final repo = ref.read(placementRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    var merged = 0;
    try {
      for (var i = 0; i < widget.groups.length; i++) {
        final name = _names[i].text.trim();
        if (!_merge[i] || _picked[i].length < 2) continue;
        if (name.isEmpty) throw 'Give "${widget.groups[i].suggestedName}" a name to merge under.';
        await repo.mergeCompanies(_picked[i].toList(), name);
        merged++;
        if (mounted) setState(() => _merge[i] = false);   // done; a retry after an error skips it
      }
      ref.read(companiesPaginationProvider.notifier).loadInitial();
      ref.invalidate(placementOverviewProvider);
      widget.onDone(merged);
    } catch (e) {
      if (mounted) setState(() => _error = e is String ? e : errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toMerge = [for (var i = 0; i < widget.groups.length; i++) if (_merge[i] && _picked[i].length >= 2) i];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('These look like the same company', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 4),
        Text(
          'Merging moves every record, role, date, interview and forum post to one company with the name you '
          'give. Untick any company that doesn\'t belong, or keep a group separate.',
          style: TextStyle(fontSize: 12, color: theme.hintColor),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < widget.groups.length; i++) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _merge[i] ? theme.colorScheme.primary.withValues(alpha: 0.5) : theme.dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _names[i],
                        enabled: _merge[i] && !_busy,
                        decoration: const InputDecoration(
                          labelText: 'Common name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Switch(
                      value: _merge[i],
                      onChanged: _busy ? null : (v) => setState(() => _merge[i] = v),
                    ),
                    Text(_merge[i] ? 'Merge' : 'Keep apart', style: const TextStyle(fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 6),
                for (final c in widget.groups[i].companies)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _picked[i].contains(c.id),
                    onChanged: !_merge[i] || _busy
                        ? null
                        : (v) => setState(() => v == true ? _picked[i].add(c.id) : _picked[i].remove(c.id)),
                    title: Text(c.name),
                    subtitle: Text('${c.records} placement record${c.records == 1 ? '' : 's'}'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: _busy ? null : () => widget.onDone(0), child: const Text('Skip')),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _busy || toMerge.isEmpty ? null : _apply,
              icon: _busy
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.merge_rounded, size: 16),
              label: Text(toMerge.isEmpty ? 'Nothing to merge' : 'Merge ${toMerge.length} group${toMerge.length == 1 ? '' : 's'}'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Manage → "Club duplicate companies": the same review for companies already in Placement Hub.
class SimilarCompaniesDialog extends ConsumerStatefulWidget {
  const SimilarCompaniesDialog({super.key});

  @override
  ConsumerState<SimilarCompaniesDialog> createState() => _SimilarCompaniesDialogState();
}

class _SimilarCompaniesDialogState extends ConsumerState<SimilarCompaniesDialog> {
  late final Future<List<SimilarCompanyGroup>> _groups = ref.read(placementRepositoryProvider).fetchSimilarCompanies();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Club duplicate companies'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: FutureBuilder<List<SimilarCompanyGroup>>(
            future: _groups,
            builder: (context, snap) {
              if (snap.hasError) return Text(errorText(snap.error!));
              if (!snap.hasData) {
                return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
              }
              final groups = snap.data!;
              if (groups.isEmpty) return const Text('No companies look like duplicates of each other.');
              return SimilarCompaniesReview(
                groups: groups,
                onDone: (merged) => Navigator.pop(context, merged > 0),
              );
            },
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close'))],
    );
  }
}
