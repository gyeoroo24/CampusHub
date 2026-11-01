import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../auth/providers/auth_providers.dart';
import '../domain/placement_models.dart';
import '../providers/placement_providers.dart';
import 'placement_dialogs.dart';

/// Placements tab: seasons at a glance, upcoming pre-placement talks, the latest interview
/// experiences, and every company (FR-15, FR-16). Moderators add companies and import sheets here.
class PlacementScreen extends ConsumerWidget {
  const PlacementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = ref.watch(currentUserProvider);
    final canManage = user != null && !user.isGuest && user.canModerateModule('placement_hub');
    final companiesAsync = ref.watch(companiesProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(companiesProvider);
        ref.invalidate(placementOverviewProvider);
        ref.invalidate(upcomingPptsProvider);
        ref.invalidate(recentInterviewsProvider);
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              color: theme.cardColor,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Placement Hub', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        Text('Company pages, JDs, pre-placement talks, hiring numbers and seniors\' interview experiences.',
                            style: TextStyle(fontSize: 12, color: theme.hintColor)),
                      ],
                    ),
                  ),
                  if (canManage) ...[
                    const SizedBox(width: 8),
                    _ManageMenu(),
                  ],
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: _OverviewSection()),
          const SliverToBoxAdapter(child: _UpcomingPptsSection()),
          const SliverToBoxAdapter(child: _RecentInterviewsSection()),
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                border: Border.symmetric(
                  horizontal: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded, size: 18),
                        hintText: 'Search companies or industries',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => ref.read(companySearchProvider.notifier).state = v,
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: ref.watch(companySortProvider),
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'name', child: Text('A–Z')),
                      DropdownMenuItem(value: 'most_hired', child: Text('Most hires')),
                      DropdownMenuItem(value: 'upcoming_ppt', child: Text('Next PPT')),
                    ],
                    onChanged: (v) => ref.read(companySortProvider.notifier).state = v ?? 'name',
                  ),
                ],
              ),
            ),
          ),
          companiesAsync.when(
            loading: () => const SliverToBoxAdapter(child: SkeletonList(itemCount: 4)),
            error: (e, _) => SliverToBoxAdapter(
              child: ErrorState(message: errorText(e), onRetry: () => ref.invalidate(companiesProvider)),
            ),
            data: (companies) {
              if (companies.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        ref.read(companySearchProvider).trim().isEmpty
                            ? 'No companies yet. Placement moderators add them, or import a placement sheet.'
                            : 'No companies match.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.hintColor),
                      ),
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 400,
                    mainAxisExtent: 128,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => CompanyTile(company: companies[i]),
                    childCount: companies.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ManageMenu extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Manage Placement Hub',
      onSelected: (value) async {
        final saved = await showDialog<bool>(
          context: context,
          builder: (_) => value == 'company' ? const CompanyFormDialog() : const ImportSheetDialog(),
        );
        if (saved == true) {
          ref.invalidate(companiesProvider);
          ref.invalidate(placementOverviewProvider);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'company',
          child: ListTile(leading: Icon(Icons.add_business_rounded), title: Text('Add a company'),
              contentPadding: EdgeInsets.zero),
        ),
        PopupMenuItem(
          value: 'import',
          child: ListTile(leading: Icon(Icons.table_view_rounded), title: Text('Import placement sheet'),
              contentPadding: EdgeInsets.zero),
        ),
      ],
      child: const Chip(
        avatar: Icon(Icons.shield_outlined, size: 16),
        label: Text('Manage'),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// Square badge with the company's initials (no logos are stored).
class CompanyAvatar extends StatelessWidget {
  final String name;
  final String initials;
  final double size;

  const CompanyAvatar({super.key, required this.name, required this.initials, this.size = 44});

  static const _palette = [Color(0xFF2563EB), Color(0xFF0D9488), Color(0xFF7C3AED), Color(0xFFDB2777),
    Color(0xFFEA580C), Color(0xFF0891B2), Color(0xFF4F46E5), Color(0xFF65A30D)];

  @override
  Widget build(BuildContext context) {
    final color = _palette[name.codeUnits.fold<int>(0, (a, b) => a + b) % _palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(size / 4)),
      child: Text(initials, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: size * 0.36)),
    );
  }
}

class CompanyTile extends StatelessWidget {
  final Company company;

  const CompanyTile({super.key, required this.company});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hires = company.latestYear == null
        ? 'No hiring data yet'
        : '${company.latestYearSelected} selected in ${company.latestYear}';
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        onTap: () => context.go('/placements/${company.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CompanyAvatar(name: company.name, initials: company.initials),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(company.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    if (company.industry != null)
                      Text(company.industry!, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: theme.hintColor)),
                    const SizedBox(height: 6),
                    Text(hires, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${company.roleCount} ${company.roleCount == 1 ? 'role' : 'roles'} · '
                            '${company.interviewCount} ${company.interviewCount == 1 ? 'experience' : 'experiences'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: theme.hintColor),
                          ),
                        ),
                        if (company.nextPptAt != null)
                          Tooltip(
                            message: 'Pre-placement talk ${DateTimeFormatter.fullDateTime(company.nextPptAt!)}',
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('PPT ${_shortDate(company.nextPptAt!)}',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SectionTitle(this.title, {this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 12, color: theme.hintColor)),
        ],
      ),
    );
  }
}

/// Students selected and companies per season, and the top recruiters of the latest season.
class _OverviewSection extends ConsumerWidget {
  const _OverviewSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ref.watch(placementOverviewProvider).when(
          loading: () => const SizedBox(height: 8),
          error: (_, __) => const SizedBox.shrink(),
          data: (overview) {
            if (overview.seasons.isEmpty) return const SizedBox.shrink();
            final seasons = overview.seasons.take(4).toList().reversed.toList();
            final most = seasons.map((s) => s.studentsSelected).reduce((a, b) => a > b ? a : b);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionTitle('Seasons at a glance', subtitle: 'Students selected per placement season.'),
                SizedBox(
                  height: 128,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final s in seasons)
                          Expanded(
                            child: Tooltip(
                              message: '${s.studentsSelected} students, ${s.companies} companies',
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text('${s.studentsSelected}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Container(
                                      height: most == 0 ? 4.0 : 4.0 + 70 * s.studentsSelected / most,
                                      decoration: BoxDecoration(
                                        color: s == seasons.last
                                            ? theme.colorScheme.primary
                                            : theme.colorScheme.primary.withValues(alpha: 0.35),
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text('${s.year}', style: TextStyle(fontSize: 12, color: theme.hintColor)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (overview.topCompanies.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Top recruiters ${overview.year}:', style: TextStyle(fontSize: 12, color: theme.hintColor)),
                        for (final c in overview.topCompanies.take(6))
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            label: Text('${c.companyName} · ${c.studentsSelected}', style: const TextStyle(fontSize: 12)),
                            onPressed: () => context.go('/placements/${c.companyId}'),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        );
  }
}

class _UpcomingPptsSection extends ConsumerWidget {
  const _UpcomingPptsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ref.watch(upcomingPptsProvider).maybeWhen(
          data: (ppts) {
            if (ppts.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionTitle('Upcoming pre-placement talks'),
                SizedBox(
                  height: 92,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: ppts.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final p = ppts[i];
                      return SizedBox(
                        width: 240,
                        child: Card(
                          elevation: 0,
                          margin: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.amber.withValues(alpha: 0.5)),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => context.go('/placements/${p.companyId}'),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.companyName, maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text(DateTimeFormatter.fullDateTime(p.scheduledAt!),
                                      style: TextStyle(fontSize: 12, color: theme.colorScheme.primary)),
                                  if (p.venue != null)
                                    Text(p.venue!, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 12, color: theme.hintColor)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
          orElse: () => const SizedBox.shrink(),
        );
  }
}

class _RecentInterviewsSection extends ConsumerWidget {
  const _RecentInterviewsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ref.watch(recentInterviewsProvider).maybeWhen(
          data: (items) {
            if (items.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionTitle('Latest interview experiences'),
                for (final i in items.take(3))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.record_voice_over_outlined),
                    title: Text('${i.companyName} · ${i.roleTitle ?? 'Interview'}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      i.content.replaceAll('\n', ' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(DateTimeFormatter.timeAgo(i.createdAt),
                        style: TextStyle(fontSize: 11, color: theme.hintColor)),
                    onTap: () => context.go('/placements/${i.companyId}?tab=interviews'),
                  ),
              ],
            );
          },
          orElse: () => const SizedBox.shrink(),
        );
  }
}
