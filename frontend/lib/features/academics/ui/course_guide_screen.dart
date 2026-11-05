import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/ui/auth_dialog.dart';
import '../domain/academics_models.dart';
import '../providers/academics_providers.dart';
import '../../forums/domain/forum_models.dart';
import '../../forums/ui/forum_board.dart';
import 'course_materials.dart';
import 'sentiment_trend_chart.dart';

/// Polarity colors for labels; always shown next to the word, never alone.
Color sentimentColor(SentimentLabel label) => switch (label) {
  SentimentLabel.positive => Colors.teal.shade700,
  SentimentLabel.negative => Colors.deepOrange.shade700,
  SentimentLabel.mixed => Colors.blueGrey.shade600,
};

IconData sentimentIcon(SentimentLabel label) => switch (label) {
  SentimentLabel.positive => Icons.sentiment_satisfied_alt_rounded,
  SentimentLabel.negative => Icons.sentiment_dissatisfied_rounded,
  SentimentLabel.mixed => Icons.sentiment_neutral_rounded,
};

/// A course's page in three tabs: the survival guide (summary, sentiment over time, themes, advice, semester
/// by semester, feedback), the shared materials repository, and the course forum. Follow it for updates.
class CourseGuideScreen extends ConsumerWidget {
  final String courseId;

  const CourseGuideScreen({super.key, required this.courseId});

  Future<void> _toggleFollow(BuildContext context, WidgetRef ref, bool following) async {
    final ok = await AuthDialog.ensureSignedIn(
      context,
      ref,
      title: 'Sign in to follow courses',
      message: 'Follow a course to hear about new materials, feedback and forum posts.',
    );
    if (ok != true) return;
    try {
      await ref.read(academicsRepositoryProvider).setFollowing(courseId, !following);
      ref.invalidate(courseProvider(courseId));
      // So the Following tab and other departments' lists pick up the change too.
      ref.invalidate(allCoursesProvider);
      ref.invalidate(followingCoursesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              following
                  ? 'You stopped following this course.'
                  : 'Following. New materials, feedback and forum posts will notify you.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorText(e)), behavior: SnackBarBehavior.floating));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guideAsync = ref.watch(survivalGuideProvider(courseId));
    final course = ref.watch(courseProvider(courseId)).valueOrNull;
    final code = course?.code ?? guideAsync.valueOrNull?.courseCode ?? 'this course';
    final following = course?.following ?? false;
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back to courses',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.canPop() ? context.pop() : context.go('/courses'),
          ),
          title: guideAsync.maybeWhen(
            data: (g) => Text('${g.courseCode} · ${g.courseName}', overflow: TextOverflow.ellipsis),
            orElse: () => const Text('Course survival guide'),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: following
                  ? OutlinedButton.icon(
                      onPressed: () => _toggleFollow(context, ref, true),
                      icon: const Icon(Icons.notifications_active_rounded, size: 18),
                      label: const Text('Following'),
                    )
                  : FilledButton.icon(
                      onPressed: () => _toggleFollow(context, ref, false),
                      icon: const Icon(Icons.notifications_none_rounded, size: 18),
                      label: const Text('Follow'),
                    ),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.insights_rounded, size: 18), text: 'Survival guide', iconMargin: EdgeInsets.zero),
              Tab(icon: Icon(Icons.folder_shared_outlined, size: 18), text: 'Materials', iconMargin: EdgeInsets.zero),
              Tab(icon: Icon(Icons.forum_outlined, size: 18), text: 'Forum', iconMargin: EdgeInsets.zero),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            guideAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(errorText(e))),
              data: (guide) => Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(survivalGuideProvider(courseId));
                      ref.invalidate(courseFeedbackProvider(courseId));
                    },
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _SummaryCard(guide: guide),
                        if (guide.semesters.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _Section(
                            title: 'Sentiment over time',
                            subtitle: 'Average review score per semester. Hover a point for details.',
                            child: SentimentTrendChart(semesters: guide.semesters),
                          ),
                        ],
                        if (guide.themes.isNotEmpty || guide.advice.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, c) {
                              final themes = _Section(
                                title: 'What students talk about',
                                child: _ThemeList(themes: guide.themes),
                              );
                              final advice = _Section(
                                title: 'Advice students repeat',
                                child: _AdviceList(advice: guide.advice),
                              );
                              if (c.maxWidth < 640) {
                                return Column(children: [themes, const SizedBox(height: 16), advice]);
                              }
                              return IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(child: themes),
                                    const SizedBox(width: 16),
                                    Expanded(child: advice),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                        if (guide.semesters.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Semester by semester',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          for (final s in guide.semesters.reversed) _SemesterCard(semester: s),
                        ],
                        const SizedBox(height: 16),
                        _FeedbackSection(courseId: courseId),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            CourseMaterialsTab(courseId: courseId, courseCode: code),
            SingleChildScrollView(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ForumBoard(
                      scope: ForumScope.course,
                      scopeId: courseId,
                      placeName: code,
                      blurb: 'ask about $code: doubts, exams, projects, resources',
                      embedded: true,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _Section({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 11, color: theme.hintColor)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _LabelChip extends StatelessWidget {
  final SentimentLabel label;
  final String? text;

  const _LabelChip({required this.label, this.text});

  @override
  Widget build(BuildContext context) {
    final color = sentimentColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(sentimentIcon(label), size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text ?? label.name,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final SurvivalGuide guide;

  const _SummaryCard({required this.guide});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overall = guide.overall;
    final trendIcon = switch (guide.trend) {
      GuideTrend.improving => Icons.trending_up_rounded,
      GuideTrend.declining => Icons.trending_down_rounded,
      GuideTrend.steady => Icons.trending_flat_rounded,
      GuideTrend.notEnoughData => Icons.hourglass_empty_rounded,
    };
    return _Section(
      title: 'Survival guide',
      subtitle: guide.departmentName.isEmpty ? null : guide.departmentName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (overall != null)
            Wrap(
              spacing: 16,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Stat(value: '${guide.feedbackCount}', label: 'reviews'),
                _Stat(value: '${(overall.positiveShare * 100).round()}%', label: 'positive'),
                _Stat(value: '${(overall.negativeShare * 100).round()}%', label: 'negative'),
                _LabelChip(label: overall.label, text: 'Overall ${overall.label.name}'),
                Chip(
                  avatar: Icon(trendIcon, size: 16),
                  label: Text(guide.trend.label, style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          if (overall != null) const SizedBox(height: 14),
          Text(guide.summary, style: const TextStyle(fontSize: 14, height: 1.45)),
          const SizedBox(height: 8),
          Text(
            'Built from student feedback, scored sentence by sentence by a sentiment model; read the reviews for the full picture.',
            style: TextStyle(fontSize: 10, color: theme.hintColor),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;

  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
      ],
    );
  }
}

class _ThemeList extends StatelessWidget {
  final List<GuideTheme> themes;

  const _ThemeList({required this.themes});

  @override
  Widget build(BuildContext context) {
    if (themes.isEmpty) return const Text('Not enough feedback yet.');
    return Column(
      children: [
        for (final t in themes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${t.theme[0].toUpperCase()}${t.theme.substring(1)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text('${t.mentions} mentions  ', style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
                _LabelChip(label: t.label),
              ],
            ),
          ),
      ],
    );
  }
}

class _AdviceList extends StatelessWidget {
  final List<String> advice;

  const _AdviceList({required this.advice});

  @override
  Widget build(BuildContext context) {
    if (advice.isEmpty) return const Text('No repeated advice yet.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final a in advice)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline_rounded, size: 16, color: Colors.amber.shade800),
                const SizedBox(width: 8),
                Expanded(child: Text(a)),
              ],
            ),
          ),
      ],
    );
  }
}

class _SemesterCard extends StatelessWidget {
  final GuideSemester semester;

  const _SemesterCard({required this.semester});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget quote(String text, SentimentLabel label) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(sentimentIcon(label), size: 15, color: sentimentColor(label)),
          const SizedBox(width: 6),
          Expanded(
            child: Text('“$text”', style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
          ),
        ],
      ),
    );
    final s = semester.sentiment;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(semester.term, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                if (semester.inProgress) ...[
                  const SizedBox(width: 8),
                  Text('in progress', style: TextStyle(fontSize: 11, color: theme.hintColor)),
                ],
                const Spacer(),
                _LabelChip(label: s.label),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${semester.feedbackCount} review${semester.feedbackCount == 1 ? '' : 's'} · '
              'score ${s.score >= 0 ? '+' : ''}${s.score.toStringAsFixed(2)} · '
              '${(s.positiveShare * 100).round()}% positive, ${(s.negativeShare * 100).round()}% negative'
              '${semester.topThemes.isEmpty ? '' : ' · about ${semester.topThemes.map((t) => t.theme).join(', ')}'}',
              style: TextStyle(fontSize: 12, color: theme.hintColor),
            ),
            if (semester.positiveQuote != null) quote(semester.positiveQuote!, SentimentLabel.positive),
            if (semester.negativeQuote != null) quote(semester.negativeQuote!, SentimentLabel.negative),
          ],
        ),
      ),
    );
  }
}

class _FeedbackSection extends ConsumerWidget {
  final String courseId;

  const _FeedbackSection({required this.courseId});

  void _refresh(WidgetRef ref) {
    ref.invalidate(courseFeedbackProvider(courseId));
    ref.invalidate(myCourseFeedbackProvider(courseId));
    ref.invalidate(survivalGuideProvider(courseId));
  }

  void _toast(ScaffoldMessengerState messenger, String text, {bool error = false}) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  /// Write a new review, or edit [existing]. One review per person per course.
  Future<void> _write(BuildContext context, WidgetRef ref, {CourseFeedback? existing}) async {
    if (existing == null) {
      final signedIn = await AuthDialog.ensureSignedIn(
        context,
        ref,
        title: 'Sign In to Share Feedback',
        message: 'Feedback is tied to your IISc account (one review per course), but you can hide your name.',
      );
      if (!signedIn || !context.mounted) return;
    }
    final result = await showDialog<({String text, bool anonymous})>(
      context: context,
      builder: (_) => _FeedbackEditor(existing: existing),
    );
    if (result == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(academicsRepositoryProvider);
    try {
      if (existing == null) {
        await repo.postFeedback(courseId, result.text, anonymous: result.anonymous);
        _toast(messenger, 'Thanks! Your review is posted.');
      } else {
        await repo.updateFeedback(existing.id, content: result.text, anonymous: result.anonymous);
        _toast(messenger, 'Your review is updated.');
      }
      _refresh(ref);
    } catch (e) {
      _toast(messenger, errorText(e), error: true);
      _refresh(ref); // e.g. "already reviewed": show their existing review with Edit
    }
  }

  /// A moderator removes someone else's review (course or department moderator). No strike: this is
  /// not a Buy & Sell or Lost & Found post.
  Future<void> _removeAsModerator(BuildContext context, WidgetRef ref, CourseFeedback review) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this review?'),
        content: Text('“${review.content.length > 120 ? '${review.content.substring(0, 120)}…' : review.content}”'
            ' is removed from this course for everyone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(academicsRepositoryProvider).deleteFeedback(review.id);
      _toast(messenger, 'Review removed.');
      _refresh(ref);
    } catch (e) {
      _toast(messenger, errorText(e), error: true);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, CourseFeedback mine) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your review?'),
        content: const Text('It is removed from this course and its survival guide. You can write a new one later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(academicsRepositoryProvider).deleteFeedback(mine.id);
      _toast(messenger, 'Your review is deleted.');
      _refresh(ref);
    } catch (e) {
      _toast(messenger, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedbackAsync = ref.watch(courseFeedbackProvider(courseId));
    final mine = ref.watch(myCourseFeedbackProvider(courseId)).valueOrNull;
    final isGuest = ref.watch(isGuestUserProvider);
    final theme = Theme.of(context);
    return _Section(
      title: 'Recent feedback',
      subtitle: isGuest ? 'Sign in to see who wrote each review.' : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mine == null)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _write(context, ref),
                icon: const Icon(Icons.rate_review_outlined, size: 16),
                label: const Text('Share your feedback'),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Your review', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      if (mine.isAnonymous)
                        Text('posted anonymously', style: TextStyle(fontSize: 11, color: theme.hintColor)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _write(context, ref, existing: mine),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit'),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                        onPressed: () => _delete(context, ref, mine),
                        icon: const Icon(Icons.delete_outline_rounded, size: 16),
                        label: const Text('Delete'),
                      ),
                    ],
                  ),
                  Text(mine.content, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          const SizedBox(height: 8),
          feedbackAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(errorText(e)),
            data: (items) {
              final others = items.where((f) => !f.isMine).toList();
              return others.isEmpty
                  ? Text(
                      mine == null ? 'No feedback yet.' : 'No other feedback yet.',
                      style: TextStyle(color: theme.hintColor),
                    )
                  : Column(
                      children: [
                        for (final f in others)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(f.content, style: const TextStyle(fontSize: 13)),
                            subtitle: Text(
                              '${f.displayAuthor} · ${DateTimeFormatter.timeAgo(f.createdAt)}${f.wasEdited ? ' · edited' : ''}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: f.canRemove
                                ? IconButton(
                                    tooltip: 'Remove review (moderator)',
                                    icon: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red.shade700),
                                    onPressed: () => _removeAsModerator(context, ref, f),
                                  )
                                : null,
                          ),
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }
}

/// Write or edit a review: the text, and whether to hide your name.
class _FeedbackEditor extends StatefulWidget {
  final CourseFeedback? existing;

  const _FeedbackEditor({this.existing});

  @override
  State<_FeedbackEditor> createState() => _FeedbackEditorState();
}

class _FeedbackEditorState extends State<_FeedbackEditor> {
  late final _controller = TextEditingController(text: widget.existing?.content);
  late bool _anonymous = widget.existing?.isAnonymous ?? false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'How did this course go?' : 'Edit your review'),
      // Scrolls on short screens (and with the keyboard up) instead of overflowing.
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _controller,
                maxLines: 6,
                maxLength: 5000,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Workload, exams, teaching, what you wish you had known...',
                  border: OutlineInputBorder(),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _anonymous,
                onChanged: (v) => setState(() => _anonymous = v ?? false),
                title: const Text('Post anonymously', style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                  'Your name is hidden from everyone else. You can still edit or delete it.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, (text: _controller.text.trim(), anonymous: _anonymous)),
          child: Text(widget.existing == null ? 'Post' : 'Save'),
        ),
      ],
    );
  }
}
