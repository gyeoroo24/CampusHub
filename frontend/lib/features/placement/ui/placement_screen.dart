import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/ui/auth_dialog.dart';
import '../domain/placement_models.dart';
import '../providers/placement_providers.dart';
import 'placement_dialogs.dart';

/// Placement Hub page (FR-15, FR-16, FR-17), in tabs:
///   Companies   what's coming up next, then every company (search, sort); a company's page has its
///               JDs, schedule, hiring numbers, interview experiences and forum
///   Schedule    every upcoming pre-placement talk, online test and interview, by day
///   Statistics  students selected per season and the top recruiters
///   Manage      (Placement Hub moderators and admins) add companies and dates, import CSV files
class PlacementScreen extends ConsumerStatefulWidget {
  const PlacementScreen({super.key});

  @override
  ConsumerState<PlacementScreen> createState() => _PlacementScreenState();
}

class _PlacementScreenState extends ConsumerState<PlacementScreen> with TickerProviderStateMixin {
  final _search = TextEditingController();
  TabController? _tabs;

  @override
  void initState() {
    super.initState();
    // Start every visit with the full company list, e.g. when coming back from a company's page.
    Future.microtask(() {
      if (mounted) ref.read(companySearchProvider.notifier).state = '';
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _tabs?.dispose();
    super.dispose();
  }

  TabController _controllerFor(int length) {
    if (_tabs?.length != length) {
      final index = (_tabs?.index ?? 0).clamp(0, length - 1);
      _tabs?.dispose();
      _tabs = TabController(length: length, vsync: this, initialIndex: index);
    }
    return _tabs!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final canManage = user != null && !user.isGuest && user.canModerateModule('placement_hub');
    final tabs = _controllerFor(canManage ? 4 : 3);

    return Column(
      children: [
        Container(
          color: theme.cardColor,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Placement Hub', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        Text('Find a company for its JDs, dates, hiring numbers, interview experiences and forum.',
                            style: TextStyle(fontSize: 12, color: theme.hintColor)),
                      ],
                    ),
                  ),
                ],
              ),
              TabBar(
                controller: tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  const Tab(icon: Icon(Icons.business_rounded, size: 18), text: 'Companies', iconMargin: EdgeInsets.zero),
                  const Tab(icon: Icon(Icons.event_note_rounded, size: 18), text: 'Schedule', iconMargin: EdgeInsets.zero),
                  const Tab(icon: Icon(Icons.bar_chart_rounded, size: 18), text: 'Statistics', iconMargin: EdgeInsets.zero),
                  if (canManage)
                    const Tab(icon: Icon(Icons.shield_outlined, size: 18), text: 'Manage', iconMargin: EdgeInsets.zero),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: tabs,
            children: [
              _CompaniesTab(search: _search, onSeeSchedule: () => tabs.animateTo(1)),
              const _ScheduleTab(),
              const _StatisticsTab(),
              if (canManage) const _ManageTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- manage (moderators)
Future<void> _runManageAction(BuildContext context, WidgetRef ref, String action) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => switch (action) {
      'company' => const AddOrImportDialog(kind: CsvImportKind.companies),
      'date' => const AddOrImportDialog(kind: CsvImportKind.schedule),
      _ => const ImportSheetDialog(),
    },
  );
  if (saved == true) {
    container.invalidate(companiesProvider);
    container.invalidate(placementOverviewProvider);
    container.invalidate(upcomingPptsProvider);
    container.invalidate(scheduleProvider);
  }
}

const _manageActions = [
  ('company', Icons.add_business_rounded, 'Add companies', 'One by one, or many from a spreadsheet file.'),
  ('date', Icons.event_available_rounded, 'Add placement dates',
      'Pre-placement talks, online tests and interviews, by hand or from a schedule file.'),
  ('sheet', Icons.table_view_rounded, 'Import placement sheet',
      'Selected students (hiring numbers, seniors), or roles with their compensation and skills.'),
];

class _ManageTab extends ConsumerWidget {
  const _ManageTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return _centered(ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('You moderate Placement Hub', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text('Add companies and dates one by one, or upload a CSV file exported from a spreadsheet. '
            'On a company\'s page you can also edit it, add JDs and dates, and remove interview experiences or '
            'forum posts.', style: TextStyle(fontSize: 12, color: theme.hintColor)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (value, icon, title, subtitle) in _manageActions)
              SizedBox(
                width: 260,
                child: Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _runManageAction(context, ref, value),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon, color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(subtitle, style: TextStyle(fontSize: 12, color: theme.hintColor)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ));
  }
}

Widget _centered(Widget child) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 980), child: child),
    );

/// Shown to guests in place of company records and detailed stats: a reason, and a way to sign in
/// right there instead of hunting for the button in the app bar.
class SignInForPlacementRecords extends StatelessWidget {
  final String message;

  const SignInForPlacementRecords({super.key, this.message = 'Sign in to see company records, hiring numbers and pay.'});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 40, color: theme.hintColor),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: theme.hintColor)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => showDialog(context: context, builder: (_) => const AuthDialog()),
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- shared pieces
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

Color scheduleKindColor(PptKind kind) => switch (kind) {
      PptKind.ppt => const Color(0xFFD97706),
      PptKind.oa => const Color(0xFF7C3AED),
      PptKind.interview => const Color(0xFF0D9488),
      PptKind.other => const Color(0xFF64748B),
    };

IconData scheduleKindIcon(PptKind kind) => switch (kind) {
      PptKind.ppt => Icons.campaign_outlined,
      PptKind.oa => Icons.computer_rounded,
      PptKind.interview => Icons.groups_2_outlined,
      PptKind.other => Icons.event_outlined,
    };

/// "PPT", "OA", "Interview" in the kind's colour.
class ScheduleKindBadge extends StatelessWidget {
  final PptKind kind;
  final bool long;

  const ScheduleKindBadge({super.key, required this.kind, this.long = false});

  @override
  Widget build(BuildContext context) {
    final color = scheduleKindColor(kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(scheduleKindIcon(kind), size: 12, color: color),
          const SizedBox(width: 3),
          Text(long ? kind.label : kind.short,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
String _shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';
String _time(DateTime t) =>
    '${t.hour % 12 == 0 ? 12 : t.hour % 12}:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'am' : 'pm'}';

/// "Today", "Tomorrow", "In 3 days".
String _countdown(DateTime at) {
  final now = DateTime.now();
  final days = DateTime(at.year, at.month, at.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  return switch (days) { <= 0 => 'Today', 1 => 'Tomorrow', _ => 'In $days days' };
}

// ---------------------------------------------------------------- companies (landing)
class _CompaniesTab extends ConsumerWidget {
  final TextEditingController search;
  final VoidCallback onSeeSchedule;

  const _CompaniesTab({required this.search, required this.onSeeSchedule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    if (ref.watch(isGuestUserProvider)) {
      return const SignInForPlacementRecords(
        message: 'Sign in to browse companies, their hiring numbers and pay.');
    }
    final companiesAsync = ref.watch(companiesProvider);
    final query = ref.watch(companySearchProvider);
    // Keep the box and the filter in step (the filter is cleared whenever the page opens).
    if (search.text != query) search.text = query;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(companiesProvider);
        ref.invalidate(upcomingPptsProvider);
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _ComingUp(onSeeAll: onSeeSchedule)),
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.only(top: 8),
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
                      controller: search,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        hintText: 'Search companies or industries',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () => ref.read(companySearchProvider.notifier).state = '',
                              ),
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
                      DropdownMenuItem(value: 'upcoming_ppt', child: Text('Coming up')),
                      DropdownMenuItem(value: 'highest_pay', child: Text('Highest pay')),
                    ],
                    onChanged: (v) => ref.read(companySortProvider.notifier).state = v ?? 'name',
                  ),
                ],
              ),
            ),
          ),
          companiesAsync.when(
            skipLoadingOnReload: true,
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
                        query.trim().isEmpty
                            ? 'No companies yet. Placement moderators add them, or import a CSV.'
                            : 'No companies match “${query.trim()}”.',
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

/// The next few placement dates, as a horizontal strip.
class _ComingUp extends ConsumerWidget {
  final VoidCallback onSeeAll;

  const _ComingUp({required this.onSeeAll});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ref.watch(upcomingPptsProvider).maybeWhen(
          skipLoadingOnReload: true,
          data: (dates) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Coming up',
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                      TextButton(onPressed: onSeeAll, child: const Text('Full schedule')),
                    ],
                  ),
                ),
                if (dates.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text('No talks, tests or interviews announced yet.',
                        style: TextStyle(fontSize: 13, color: theme.hintColor)),
                  )
                else
                  SizedBox(
                    height: 112,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: dates.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, i) => SizedBox(width: 250, child: _ComingUpCard(date: dates[i])),
                    ),
                  ),
              ],
            );
          },
          orElse: () => const SizedBox(height: 8),
        );
  }
}

class _ComingUpCard extends StatelessWidget {
  final Ppt date;

  const _ComingUpCard({required this.date});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = scheduleKindColor(date.kind);
    final at = date.scheduledAt!;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.45)),
      ),
      child: InkWell(
        onTap: () => context.go('/placements/${date.companyId}'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 56,
              color: color.withValues(alpha: 0.1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_months[at.month - 1].toUpperCase(),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
                  Text('${at.day}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color, height: 1.1)),
                  Text(_weekdays[at.weekday - 1], style: TextStyle(fontSize: 11, color: color)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ScheduleKindBadge(kind: date.kind),
                        const SizedBox(width: 6),
                        Text(_countdown(at), style: TextStyle(fontSize: 11, color: theme.hintColor)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(date.companyName, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text([date.timeTbd ? 'Time TBA' : _time(at), if (date.venue != null) date.venue!].join(' · '),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: theme.hintColor)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CompanyTile extends StatelessWidget {
  final Company company;

  const CompanyTile({super.key, required this.company});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pay = company.ctcMin == null ? null : formatCtc(company.ctcMin, company.ctcMax);
    final hires = [
      if (company.latestYear != null) '${company.latestYearSelected} selected in ${company.latestYear}',
      if (pay != null) pay,
    ].join(' · ');
    final next = company.nextDateAt;
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
                    Text(hires.isEmpty ? 'No hiring data yet' : hires,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
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
                        if (next != null)
                          Tooltip(
                            message: '${(company.nextDateKind ?? PptKind.ppt).label} '
                                '${DateTimeFormatter.fullDateTime(next)}',
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: scheduleKindColor(company.nextDateKind ?? PptKind.ppt).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('${(company.nextDateKind ?? PptKind.ppt).short} ${_shortDate(next)}',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: scheduleKindColor(company.nextDateKind ?? PptKind.ppt))),
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

// ---------------------------------------------------------------- schedule
class _ScheduleTab extends ConsumerWidget {
  const _ScheduleTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final kinds = ref.watch(scheduleKindsProvider);
    final past = ref.watch(schedulePastProvider);
    void setKinds(Set<PptKind> k) => ref.read(scheduleKindsProvider.notifier).state = k;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(scheduleProvider),
      child: _centered(ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // One type at a time; tapping the selected one again goes back to All.
              ChoiceChip(
                  showCheckmark: false,
                  label: const Text('All'),
                  selected: kinds.isEmpty,
                  onSelected: (_) => setKinds(const {})),
              for (final k in PptKind.values)
                ChoiceChip(
                  showCheckmark: false,
                  avatar: Icon(scheduleKindIcon(k), size: 16, color: scheduleKindColor(k)),
                  label: Text(k.label),
                  selected: kinds.length == 1 && kinds.contains(k),
                  onSelected: (_) => setKinds(kinds.length == 1 && kinds.contains(k) ? const {} : {k}),
                ),
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: false, label: Text('Upcoming')),
                  ButtonSegment(value: true, label: Text('Past')),
                ],
                selected: {past},
                onSelectionChanged: (v) => ref.read(schedulePastProvider.notifier).state = v.first,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...ref.watch(scheduleProvider).when<List<Widget>>(
                skipLoadingOnReload: true,
                loading: () => [const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))],
                error: (e, _) => [ErrorState(message: errorText(e), onRetry: () => ref.invalidate(scheduleProvider))],
                data: (dates) {
                  if (dates.isEmpty) {
                    return [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(past ? 'Nothing in the past yet.' : 'Nothing coming up. Earlier dates are under Past.',
                            textAlign: TextAlign.center, style: TextStyle(color: theme.hintColor)),
                      ),
                    ];
                  }
                  final out = <Widget>[];
                  DateTime? day;
                  for (final d in dates) {
                    final at = d.scheduledAt!;
                    final thisDay = DateTime(at.year, at.month, at.day);
                    if (day != thisDay) {
                      day = thisDay;
                      out.add(Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 6),
                        child: Text(
                          (past ? '${_weekdays[at.weekday - 1]} ${at.day} ${_months[at.month - 1]} ${at.year}'
                              : '${_weekdays[at.weekday - 1]} ${at.day} ${_months[at.month - 1]} · ${_countdown(at)}').toUpperCase(),
                          style: TextStyle(fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.bold, color: theme.hintColor),
                        ),
                      ));
                    }
                    out.add(ScheduleTile(date: d, showCompany: true));
                  }
                  return out;
                },
              ),
        ],
      )),
    );
  }
}

/// One date on the schedule: time, kind, company, venue and details.
class ScheduleTile extends StatelessWidget {
  final Ppt date;
  final bool showCompany;
  final Widget? trailing;

  const ScheduleTile({super.key, required this.date, this.showCompany = false, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final at = date.scheduledAt;
    final past = date.when == PptWhen.past;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: showCompany ? () => context.go('/placements/${date.companyId}') : null,
        child: Opacity(
          opacity: past ? 0.6 : 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 70,
                  child: at == null
                      ? const Text('Date TBA', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // On a company's page the day matters as much as the time.
                            if (!showCompany)
                              Text(_shortDate(at), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                            Text(date.timeTbd ? 'Time TBA' : _time(at),
                                style: TextStyle(
                                    fontWeight: showCompany ? FontWeight.w700 : FontWeight.w500,
                                    fontSize: showCompany ? 13 : 12,
                                    color: showCompany ? null : theme.hintColor)),
                          ],
                        ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ScheduleKindBadge(kind: date.kind, long: true),
                          if (showCompany)
                            Text(date.companyName, style: const TextStyle(fontWeight: FontWeight.w700)),
                          if (past) Text('Done', style: TextStyle(fontSize: 12, color: theme.hintColor)),
                        ],
                      ),
                      if (date.venue != null) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          Icon(Icons.place_outlined, size: 13, color: theme.hintColor),
                          const SizedBox(width: 3),
                          Expanded(child: Text(date.venue!, style: TextStyle(fontSize: 12, color: theme.hintColor))),
                        ]),
                      ],
                      if (date.details != null) ...[
                        const SizedBox(height: 4),
                        Text(date.details!, style: const TextStyle(fontSize: 13)),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- statistics
class _StatisticsTab extends ConsumerWidget {
  const _StatisticsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    Widget section(String title, String subtitle, Widget child) => Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                Text(subtitle, style: TextStyle(fontSize: 12, color: theme.hintColor)),
                const SizedBox(height: 12),
                child,
              ],
            ),
          ),
        );

    return ref.watch(placementOverviewProvider).when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(message: errorText(e), onRetry: () => ref.invalidate(placementOverviewProvider)),
          data: (overview) {
            // Highest packages: full-time compensation by company in the latest season that has it.
            final topPay = overview.topPaying.isEmpty ? 1 : overview.topPaying.first.ctcMax;
            final paySection = overview.topPaying.isEmpty
                ? null
                : section(
                    'Highest packages, ${overview.payYear! - 1}-${(overview.payYear! % 100).toString().padLeft(2, '0')}',
                    'Full-time compensation (CTC) each company offered, lowest to highest role. Tap one to see its roles.',
                    Column(
                      children: [
                        for (final c in overview.topPaying)
                          InkWell(
                            onTap: () => context.go('/placements/${c.companyId}'),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 160,
                                    child: Text(c.companyName, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w600)),
                                  ),
                                  Expanded(
                                    child: LayoutBuilder(
                                      builder: (context, box) {
                                        final w = box.maxWidth - 8;
                                        final left = w * c.ctcMin / topPay;
                                        final right = w * c.ctcMax / topPay;
                                        return Stack(children: [
                                          Container(height: 16),
                                          Positioned(
                                            left: c.ctcMin == c.ctcMax ? 0 : left,
                                            width: (c.ctcMin == c.ctcMax ? right : right - left).clamp(4, w),
                                            top: 0,
                                            bottom: 0,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.teal.withValues(alpha: 0.75),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                            ),
                                          ),
                                        ]);
                                      },
                                    ),
                                  ),
                                  SizedBox(
                                    width: 120,
                                    child: Text(formatCtc(c.ctcMin, c.ctcMax),
                                        textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
            if (overview.seasons.isEmpty && paySection != null) {
              return _centered(ListView(padding: const EdgeInsets.all(16), children: [paySection]));
            }
            if (overview.seasons.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('No placement statistics yet. They appear once a placement sheet is imported.',
                      textAlign: TextAlign.center, style: TextStyle(color: theme.hintColor)),
                ),
              );
            }
            final seasons = overview.seasons.take(6).toList().reversed.toList();
            final most = seasons.map((s) => s.studentsSelected).reduce((a, b) => a > b ? a : b);
            final topMost = overview.topCompanies.isEmpty
                ? 1
                : overview.topCompanies.map((c) => c.studentsSelected).reduce((a, b) => a > b ? a : b);
            final latest = overview.seasons.first;
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(placementOverviewProvider),
              child: _centered(ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _BigStat(value: '${latest.studentsSelected}', label: 'Students selected in ${latest.year}'),
                      _BigStat(value: '${latest.companies}', label: 'Companies hiring in ${latest.year}'),
                      if (overview.seasons.length > 1)
                        _BigStat(
                          value: _change(overview.seasons[1].studentsSelected, latest.studentsSelected),
                          label: 'Change from ${overview.seasons[1].year}',
                        ),
                    ],
                  ),
                  if (ref.watch(isGuestUserProvider)) ...[
                    const SizedBox(height: 16),
                    const SignInForPlacementRecords(
                      message: 'That\'s the season total. Sign in to see top recruiters, pay and every company\'s record.'),
                  ],
                  const SizedBox(height: 16),
                  section(
                    'Seasons at a glance',
                    'Students selected per placement season. Totals only; no student is ever shown.',
                    SizedBox(
                      height: 150,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final s in seasons)
                            Expanded(
                              child: Tooltip(
                                message: '${s.studentsSelected} students, ${s.companies} companies',
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text('${s.studentsSelected}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      Container(
                                        height: most == 0 ? 4.0 : 4.0 + 90 * s.studentsSelected / most,
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
                    section(
                      'Top recruiters, ${overview.year}',
                      'Students selected by each company. Tap one to open its page.',
                      Column(
                        children: [
                          for (final c in overview.topCompanies)
                            InkWell(
                              onTap: () => context.go('/placements/${c.companyId}'),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 5),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 160,
                                      child: Text(c.companyName, maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w600)),
                                    ),
                                    Expanded(
                                      child: LayoutBuilder(
                                        builder: (context, box) => Align(
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            height: 16,
                                            width: (box.maxWidth - 8) * c.studentsSelected / topMost + 4,
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.primary.withValues(alpha: 0.75),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 36,
                                      child: Text('${c.studentsSelected}',
                                          textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                    SizedBox(
                                      width: 110,
                                      child: Text(c.ctcMin == null ? '' : formatCtc(c.ctcMin, c.ctcMax),
                                          textAlign: TextAlign.right,
                                          style: TextStyle(fontSize: 12, color: theme.hintColor)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ?paySection,
                  section(
                    'Every season',
                    'Students selected and companies that hired.',
                    Table(
                      columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(2), 2: FlexColumnWidth(2)},
                      children: [
                        TableRow(
                          children: [
                            for (final h in ['Season', 'Students selected', 'Companies'])
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(h, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.hintColor)),
                              ),
                          ],
                        ),
                        for (final s in overview.seasons)
                          TableRow(
                            children: [
                              for (final v in ['${s.year}', '${s.studentsSelected}', '${s.companies}'])
                                Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(v)),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              )),
            );
          },
        );
  }

  static String _change(int before, int now) {
    if (before == 0) return now == 0 ? '0' : '+$now';
    final pct = ((now - before) * 100 / before).round();
    return '${pct >= 0 ? '+' : ''}$pct%';
  }
}

class _BigStat extends StatelessWidget {
  final String value;
  final String label;

  const _BigStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 200,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          Text(label, style: TextStyle(fontSize: 12, color: theme.hintColor)),
        ],
      ),
    );
  }
}
