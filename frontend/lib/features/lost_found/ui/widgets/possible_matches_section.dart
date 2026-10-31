import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/date_time_formatter.dart';
import '../../domain/lost_found_item.dart';
import '../../domain/possible_match.dart';
import '../../providers/lost_found_providers.dart';
import 'lost_found_detail_dialog.dart';

/// "Possible matches" for one of your own reports (FR-9, future plan §1.2): reports of the other
/// kind that may be the same item, ranked by description and photo, each with a strength badge
/// and why it matched. Show it only to the report's owner or an admin.
class PossibleMatchesSection extends ConsumerWidget {
  final LostFoundItem item;

  const PossibleMatchesSection({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final otherKind = item.kind == PostType.lost ? 'found' : 'lost';
    final result = ref.watch(possibleMatchesProvider((id: item.id, kind: item.kind)));
    if (result.hasError) return const SizedBox.shrink();
    final data = result.valueOrNull;
    final looking = data == null || data.isPending;
    final matches = data?.matches ?? const <PossibleMatch>[];

    final String note;
    if (looking && matches.isEmpty) {
      note = 'Looking for matching $otherKind reports…';
    } else if (data?.status == MatchStatus.unavailable) {
      note = 'Open $otherKind reports in "${item.category.name}". Tap one to see the details.';
    } else if (matches.isEmpty) {
      note = "No likely matches yet. If someone files a $otherKind report that looks like this item, "
          "${item.kind == PostType.lost ? "you'll get a notification" : "its owner will be notified"}.";
    } else {
      note = 'Ranked by how closely the description and photos match. Tap one to see the details.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? const Color(0xFF475569) : const Color(0xFFFDE68A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 18, color: Colors.amber.shade800),
                  const SizedBox(width: 8),
                  Text(
                    matches.isEmpty ? 'Possible Matches' : 'Possible Matches (${matches.length})',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                    ),
                  ),
                  if (looking) ...[
                    const SizedBox(width: 10),
                    const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(note, style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.brown.shade700)),
              if (matches.isNotEmpty) const SizedBox(height: 10),
              for (final match in matches) _MatchTile(match: match, isDark: isDark),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _MatchTile extends StatelessWidget {
  final PossibleMatch match;
  final bool isDark;

  const _MatchTile({required this.match, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final report = match.item;
    final strong = match.strength == MatchStrength.strong;
    final placeholder = Container(
      width: 42,
      height: 42,
      color: Colors.grey.shade200,
      child: const Icon(Icons.inventory_2_outlined, size: 18),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showDialog(context: context, builder: (_) => LostFoundDetailDialog(item: report)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: report.imageUrl.isNotEmpty
                  ? Image.network(report.imageUrl, width: 42, height: 42, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => placeholder)
                  : placeholder,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (report.location.isNotEmpty) report.location,
                      DateTimeFormatter.timeAgo(report.occurredAt),
                      if (match.reasons.isNotEmpty) match.reasons.join(' · '),
                    ].join(' • '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            if (match.strength != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: strong
                      ? (isDark ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5))
                      : (isDark ? const Color(0xFF422006) : const Color(0xFFFEF3C7)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  match.strength!.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: strong
                        ? (isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857))
                        : (isDark ? Colors.amber.shade200 : Colors.amber.shade900),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
