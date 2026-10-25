import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../auth/ui/auth_dialog.dart';
import '../domain/academics_models.dart';
import '../providers/academics_providers.dart';
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

/// A course's page: the survival guide (summary, sentiment over time, themes, advice, semester
/// by semester) and its recent feedback.
class CourseGuideScreen extends ConsumerWidget {
  final String courseId;

  const CourseGuideScreen({super.key, required this.courseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guideAsync = ref.watch(survivalGuideProvider(courseId));
    final theme = Theme.of(context);

    return Scaffold(
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
      ),
      body: guideAsync.when(
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
                    LayoutBuilder(builder: (context, c) {
                      final themes = _Section(title: 'What students talk about', child: _ThemeList(themes: guide.themes));
                      final advice = _Section(title: 'Advice students repeat', child: _AdviceList(advice: guide.advice));
                      if (c.maxWidth < 640) {
                        return Column(children: [themes, const SizedBox(height: 16), advice]);
                      }
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [Expanded(child: themes), const SizedBox(width: 16), Expanded(child: advice)],
                        ),
                      );
                    }),
                  ],
                  if (guide.semesters.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Semester by semester', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
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
          Text(text ?? label.name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
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
            'Built from student feedback with a word-list sentiment score; read the reviews for the full picture.',
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
                  child: Text('${t.theme[0].toUpperCase()}${t.theme.substring(1)}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text('${t.mentions} mentions  ',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
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
              Expanded(child: Text('“$text”', style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic))),
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

  Future<void> _write(BuildContext context, WidgetRef ref) async {
    final signedIn = await AuthDialog.ensureSignedIn(
      context,
      ref,
      title: 'Sign In to Share Feedback',
      message: 'Feedback is posted under your IISc account.',
    );
    if (!signedIn || !context.mounted) return;
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How did this course go?'),
        content: SizedBox(
          width: 440,
          child: TextField(
            controller: controller,
            maxLines: 6,
            maxLength: 5000,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Workload, exams, teaching, what you wish you had known...',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Post')),
        ],
      ),
    );
    controller.dispose();
    if (content == null || content.isEmpty) return;
    try {
      await ref.read(academicsRepositoryProvider).postFeedback(courseId, content);
      ref.invalidate(courseFeedbackProvider(courseId));
      ref.invalidate(survivalGuideProvider(courseId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorText(e)), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedbackAsync = ref.watch(courseFeedbackProvider(courseId));
    final theme = Theme.of(context);
    return _Section(
      title: 'Recent feedback',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _write(context, ref),
              icon: const Icon(Icons.rate_review_outlined, size: 16),
              label: const Text('Share your feedback'),
            ),
          ),
          const SizedBox(height: 8),
          feedbackAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(errorText(e)),
            data: (items) => items.isEmpty
                ? Text('No feedback yet.', style: TextStyle(color: theme.hintColor))
                : Column(
                    children: [
                      for (final f in items)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(f.content, style: const TextStyle(fontSize: 13)),
                          subtitle: Text('${f.authorName} · ${DateTimeFormatter.timeAgo(f.createdAt)}',
                              style: const TextStyle(fontSize: 11)),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
