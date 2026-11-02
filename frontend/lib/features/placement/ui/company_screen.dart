import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/report_content_dialog.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/ui/auth_dialog.dart';
import '../domain/placement_models.dart';
import '../providers/placement_providers.dart';
import '../../forums/domain/forum_models.dart';
import '../../forums/ui/forum_board.dart';
import 'placement_dialogs.dart';
import 'placement_screen.dart' show CompanyAvatar, ScheduleTile;

const _tabs = ['overview', 'interviews', 'stats', 'forum'];

/// A company's page (FR-15, FR-16): details, JDs and its placement dates, interview experiences,
/// hiring statistics and its forum. [initialTab] is one of overview / interviews / stats / forum.
class CompanyScreen extends ConsumerWidget {
  final String companyId;
  final String? initialTab;

  const CompanyScreen({super.key, required this.companyId, this.initialTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companyAsync = ref.watch(companyProvider(companyId));
    final user = ref.watch(currentUserProvider);
    final isAdmin = user != null && !user.isGuest && user.isAdmin;

    return DefaultTabController(
      length: _tabs.length,
      initialIndex: _tabs.indexOf(initialTab ?? '').clamp(0, _tabs.length - 1),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back to Placement Hub',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.canPop() ? context.pop() : context.go('/placements'),
          ),
          title: Text(companyAsync.valueOrNull?.name ?? 'Company', overflow: TextOverflow.ellipsis),
          actions: [
            if (companyAsync.valueOrNull?.viewerCanManage ?? false)
              IconButton(
                tooltip: 'Edit company',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final saved = await showDialog<bool>(
                      context: context, builder: (_) => CompanyFormDialog(company: companyAsync.value));
                  if (saved == true) refreshCompany(ref, companyId);
                },
              ),
            if (isAdmin && companyAsync.hasValue)
              IconButton(
                tooltip: 'Delete company',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => _deleteCompany(context, ref, companyAsync.value!),
              ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Interview experiences'),
              Tab(text: 'Hiring stats'),
              Tab(text: 'Forum'),
            ],
          ),
        ),
        // A reload (sign-in, edits) keeps the tabs on screen: swapping them for a spinner would
        // dispose an open forum or form part-way through.
        body: companyAsync.when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(message: errorText(e), onRetry: () => ref.invalidate(companyProvider(companyId))),
          data: (company) => TabBarView(
            children: [
              _OverviewTab(company: company),
              _InterviewsTab(company: company),
              _StatsTab(companyId: companyId),
              ForumBoard(
                scope: ForumScope.company,
                scopeId: companyId,
                placeName: company.name,
                blurb: 'ask about ${company.name}\'s process, prep and offers',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteCompany(BuildContext context, WidgetRef ref, Company company) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${company.name}?'),
        content: const Text('This also deletes its JDs, pre-placement talks, hiring records, interview experiences '
            'and forum. It can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
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
      await ref.read(placementRepositoryProvider).deleteCompany(company.id);
      ref.invalidate(companiesProvider);
      ref.invalidate(placementOverviewProvider);
      if (context.mounted) context.go('/placements');
    } catch (e) {
      if (context.mounted) _snack(context, errorText(e));
    }
  }
}

void _snack(BuildContext context, String message) => ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));

Future<void> _open(BuildContext context, String url) async {
  final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!opened && context.mounted) _snack(context, "Couldn't open $url");
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? action;

  const _Section({required this.title, required this.child, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                ),
                if (action != null) action!,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;

  const _Empty(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
      );
}

Widget _centered(Widget child) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 860), child: child),
    );

// ---------------------------------------------------------------- overview
class _OverviewTab extends ConsumerWidget {
  final Company company;

  const _OverviewTab({required this.company});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final manage = company.viewerCanManage;
    Future<void> edit(Widget dialog) async {
      final saved = await showDialog<bool>(context: context, builder: (_) => dialog);
      if (saved == true) refreshCompany(ref, company.id);
    }

    Future<void> remove(String what, Future<void> Function() action) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Delete this $what?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await action();
        refreshCompany(ref, company.id);
      } catch (e) {
        if (context.mounted) _snack(context, errorText(e));
      }
    }

    final repo = ref.read(placementRepositoryProvider);
    return _centered(ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(
          title: 'About',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CompanyAvatar(name: company.name, initials: company.initials, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(company.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                        if (company.industry != null)
                          Text(company.industry!, style: TextStyle(color: theme.hintColor)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Stat(
                    label: company.latestYear == null ? 'Hiring data' : 'Selected in ${company.latestYear}',
                    value: company.latestYear == null ? '—' : '${company.latestYearSelected}',
                  ),
                  _Stat(label: 'Selected, all years', value: '${company.totalSelected}'),
                  _Stat(label: 'Interview experiences', value: '${company.interviewCount}'),
                ],
              ),
              if (company.description != null) ...[
                const SizedBox(height: 12),
                Text(company.description!),
              ],
              if (company.website != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () => _open(context, company.website!),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(company.website!, overflow: TextOverflow.ellipsis),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Job descriptions',
          action: manage
              ? TextButton.icon(
                  onPressed: () => edit(JobDescriptionFormDialog(companyId: company.id)),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add'),
                )
              : null,
          child: company.jobDescriptions.isEmpty
              ? const _Empty('No job description posted yet.')
              : Column(
                  children: [
                    for (final jd in company.jobDescriptions)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 12),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        title: Text(jd.roleTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: jd.compensation == null ? null : Text(jd.compensation!),
                        trailing: manage
                            ? PopupMenuButton<String>(
                                onSelected: (v) => v == 'edit'
                                    ? edit(JobDescriptionFormDialog(companyId: company.id, jd: jd))
                                    : remove('job description', () => repo.deleteJobDescription(jd.id)),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                                ],
                              )
                            : null,
                        children: [
                          SelectableText(jd.description ?? 'No details yet.'),
                          if (jd.fileUrl != null)
                            TextButton.icon(
                              style: TextButton.styleFrom(padding: EdgeInsets.zero),
                              onPressed: () => _open(context, jd.fileUrl!),
                              icon: const Icon(Icons.description_outlined, size: 16),
                              label: const Text('Open the JD file'),
                            ),
                        ],
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Placement dates',
          action: manage
              ? TextButton.icon(
                  onPressed: () => edit(PptFormDialog(companyId: company.id)),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add'),
                )
              : null,
          child: company.ppts.isEmpty
              ? const _Empty('No pre-placement talk, online test or interview announced yet.')
              : Column(
                  children: [
                    // Upcoming first (soonest first), then dates to be announced, then past ones.
                    for (final p in _scheduleOrder(company.ppts))
                      ScheduleTile(
                        date: p,
                        trailing: manage
                            ? PopupMenuButton<String>(
                                onSelected: (v) => v == 'edit'
                                    ? edit(PptFormDialog(companyId: company.id, ppt: p))
                                    : remove(p.kind.label.toLowerCase(), () => repo.deletePpt(p.id)),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                                ],
                              )
                            : null,
                      ),
                  ],
                ),
        ),
      ],
    ));
  }
}

List<Ppt> _scheduleOrder(List<Ppt> ppts) {
  int rank(Ppt p) => switch (p.when) { PptWhen.upcoming => 0, PptWhen.unscheduled => 1, PptWhen.past => 2 };
  return [...ppts]..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      if (a.scheduledAt == null || b.scheduledAt == null) return 0;
      return a.when == PptWhen.past ? b.scheduledAt!.compareTo(a.scheduledAt!) : a.scheduledAt!.compareTo(b.scheduledAt!);
    });
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(fontSize: 11, color: theme.hintColor)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- hiring statistics
class _StatsTab extends ConsumerStatefulWidget {
  final String companyId;

  const _StatsTab({required this.companyId});

  @override
  ConsumerState<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends ConsumerState<_StatsTab> {
  bool _allYears = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ref.watch(hiringStatsProvider(widget.companyId)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(
              message: errorText(e), onRetry: () => ref.invalidate(hiringStatsProvider(widget.companyId))),
          data: (stats) {
            if (stats.years.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No hiring data for this company yet. It appears once a placement sheet that '
                      'lists it is imported.', textAlign: TextAlign.center),
                ),
              );
            }
            final years = _allYears ? stats.years : stats.years.take(3).toList();
            final most = years.map((y) => y.studentsSelected).reduce((a, b) => a > b ? a : b);
            return _centered(ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Section(
                  title: _allYears ? 'Students selected, every year' : 'Students selected, last ${years.length} years',
                  action: stats.years.length > 3
                      ? TextButton(
                          onPressed: () => setState(() => _allYears = !_allYears),
                          child: Text(_allYears ? 'Last 3 years' : 'All ${stats.years.length} years'),
                        )
                      : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Totals from the placement office\'s sheets. Individual students are never shown.',
                          style: TextStyle(fontSize: 12, color: theme.hintColor)),
                      const SizedBox(height: 12),
                      for (final y in years) ...[
                        Row(
                          children: [
                            SizedBox(width: 48, child: Text('${y.year}', style: const TextStyle(fontWeight: FontWeight.bold))),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, c) => Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    height: 22,
                                    width: (c.maxWidth - 40) * y.studentsSelected / most + 4,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 36, child: Text('${y.studentsSelected}', textAlign: TextAlign.right,
                                style: const TextStyle(fontWeight: FontWeight.bold))),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 48, top: 4, bottom: 14),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final r in y.roles)
                                Chip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text('${r.roleTitle} · ${r.studentsSelected}', style: const TextStyle(fontSize: 12)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ));
          },
        );
  }
}

// ---------------------------------------------------------------- interview experiences
class _InterviewsTab extends ConsumerWidget {
  final Company company;

  const _InterviewsTab({required this.company});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    Future<void> write([InterviewExperience? existing]) async {
      final signedIn = await AuthDialog.ensureSignedIn(context, ref,
          title: 'Sign in to share', message: 'Sign in with your IISc email to share an interview experience.');
      if (!signedIn || !context.mounted) return;
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => InterviewFormDialog(companyId: company.id, companyName: company.name, interview: existing),
      );
      if (saved == true) refreshCompany(ref, company.id);
    }

    return ref.watch(companyInterviewsProvider(company.id)).when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              ErrorState(message: errorText(e), onRetry: () => ref.invalidate(companyInterviewsProvider(company.id))),
          data: (items) => _centered(ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      items.isEmpty
                          ? 'No interview experiences yet.'
                          : '${items.length} ${items.length == 1 ? 'experience' : 'experiences'}, newest first',
                      style: TextStyle(color: theme.hintColor),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => write(),
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: const Text('Share yours'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final item in items) ...[
                _InterviewCard(
                  item: item,
                  canModerate: company.viewerCanManage,
                  onEdit: () => write(item),
                  onDeleted: () => refreshCompany(ref, company.id),
                ),
                const SizedBox(height: 12),
              ],
            ],
          )),
        );
  }
}

class _InterviewCard extends ConsumerStatefulWidget {
  final InterviewExperience item;
  final bool canModerate;
  final VoidCallback onEdit;
  final VoidCallback onDeleted;

  const _InterviewCard({required this.item, required this.canModerate, required this.onEdit, required this.onDeleted});

  @override
  ConsumerState<_InterviewCard> createState() => _InterviewCardState();
}

class _InterviewCardState extends ConsumerState<_InterviewCard> {
  bool _expanded = false;

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove this interview experience?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(placementRepositoryProvider).deleteInterview(widget.item.id);
      widget.onDeleted();
    } catch (e) {
      if (mounted) _snack(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final long = item.content.length > 360 || '\n'.allMatches(item.content).length > 5;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text([item.roleTitle ?? 'Interview', if (item.placementYear != null) '${item.placementYear}'].join(' · '),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${item.displayAuthor} · ${DateTimeFormatter.timeAgo(item.createdAt)}',
                          style: TextStyle(fontSize: 12, color: theme.hintColor)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    switch (v) {
                      case 'edit':
                        widget.onEdit();
                      case 'delete':
                        _delete();
                      case 'report':
                        ReportContentDialog.show(context, ref,
                            targetType: 'interview_experience', targetId: item.id, itemLabel: 'this interview experience');
                    }
                  },
                  itemBuilder: (_) => [
                    if (item.isMine) const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    if (item.isMine || widget.canModerate) const PopupMenuItem(value: 'delete', child: Text('Remove')),
                    if (!item.isMine) const PopupMenuItem(value: 'report', child: Text('Report')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _expanded || !long
                  ? SelectableText(item.content)
                  : Text(item.content, maxLines: 6, overflow: TextOverflow.ellipsis),
            ),
            if (long)
              TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Show less' : 'Read more'),
              ),
          ],
        ),
      ),
    );
  }
}
