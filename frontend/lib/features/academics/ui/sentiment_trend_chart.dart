import 'package:flutter/material.dart';
import '../domain/academics_models.dart';

/// Sentiment over time: one line of semester scores on a fixed −1…+1 axis with a neutral zero line.
/// Hovering (or long-pressing) a point shows its term, score and review count. The in-progress
/// semester is drawn hollow. The semester cards below the chart carry the same numbers as text.
class SentimentTrendChart extends StatelessWidget {
  final List<GuideSemester> semesters;
  final double height;

  const SentimentTrendChart({super.key, required this.semesters, this.height = 180});

  static const _leftGutter = 64.0;
  static const _topPad = 12.0;
  static const _bottomGutter = 28.0;
  static const _hit = 32.0;
  static const _rightPad = 32.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final colors = _ChartColors(
      line: theme.colorScheme.primary,
      grid: theme.dividerColor.withValues(alpha: 0.35),
      zero: ink.withValues(alpha: 0.45),
      muted: ink.withValues(alpha: 0.6),
      surface: theme.cardColor,
    );

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final plotW = width - _leftGutter - _rightPad;
      final plotH = height - _topPad - _bottomGutter;
      final n = semesters.length;
      Offset pointAt(int i) {
        final x = _leftGutter + (n == 1 ? plotW / 2 : plotW * i / (n - 1));
        final y = _topPad + plotH * (1 - (semesters[i].sentiment.score.clamp(-1.0, 1.0) + 1) / 2);
        return Offset(x, y);
      }

      return SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _TrendPainter(
                  semesters: semesters,
                  colors: colors,
                  pointAt: pointAt,
                  plotTop: _topPad,
                  plotHeight: plotH,
                  plotLeft: _leftGutter,
                  plotRight: width - _rightPad,
                  labelStyle: TextStyle(fontSize: 10, color: colors.muted),
                ),
              ),
            ),
            for (var i = 0; i < n; i++)
              Positioned(
                left: pointAt(i).dx - _hit / 2,
                top: pointAt(i).dy - _hit / 2,
                width: _hit,
                height: _hit,
                child: Tooltip(
                  waitDuration: Duration.zero,
                  message: '${semesters[i].term}${semesters[i].inProgress ? ' (in progress)' : ''}\n'
                      'Score ${semesters[i].sentiment.score >= 0 ? '+' : ''}'
                      '${semesters[i].sentiment.score.toStringAsFixed(2)} · ${semesters[i].sentiment.label.name}\n'
                      '${semesters[i].feedbackCount} review${semesters[i].feedbackCount == 1 ? '' : 's'}',
                  child: const MouseRegion(cursor: SystemMouseCursors.click, child: SizedBox.expand()),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _ChartColors {
  final Color line;
  final Color grid;
  final Color zero;
  final Color muted;
  final Color surface;

  const _ChartColors({
    required this.line,
    required this.grid,
    required this.zero,
    required this.muted,
    required this.surface,
  });
}

class _TrendPainter extends CustomPainter {
  final List<GuideSemester> semesters;
  final _ChartColors colors;
  final Offset Function(int) pointAt;
  final double plotTop;
  final double plotHeight;
  final double plotLeft;
  final double plotRight;
  final TextStyle labelStyle;

  _TrendPainter({
    required this.semesters,
    required this.colors,
    required this.pointAt,
    required this.plotTop,
    required this.plotHeight,
    required this.plotLeft,
    required this.plotRight,
    required this.labelStyle,
  });

  double _y(double score) => plotTop + plotHeight * (1 - (score + 1) / 2);

  void _text(Canvas canvas, String text, Offset at, {TextAlign align = TextAlign.left, TextStyle? style}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style ?? labelStyle),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout();
    final dx = switch (align) {
      TextAlign.right => at.dx - tp.width,
      TextAlign.center => at.dx - tp.width / 2,
      _ => at.dx,
    };
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Recessive grid at +1 and −1, a stronger neutral zero line, and y labels in muted ink.
    final grid = Paint()
      ..color = colors.grid
      ..strokeWidth = 1;
    for (final v in [1.0, -1.0]) {
      canvas.drawLine(Offset(plotLeft, _y(v)), Offset(plotRight, _y(v)), grid);
    }
    canvas.drawLine(
      Offset(plotLeft, _y(0)),
      Offset(plotRight, _y(0)),
      Paint()
        ..color = colors.zero
        ..strokeWidth = 1,
    );
    _text(canvas, 'Positive', Offset(plotLeft - 8, _y(1)), align: TextAlign.right);
    _text(canvas, 'Mixed', Offset(plotLeft - 8, _y(0)), align: TextAlign.right);
    _text(canvas, 'Negative', Offset(plotLeft - 8, _y(-1)), align: TextAlign.right);

    if (semesters.isEmpty) return;

    // 2px line through finished semesters; the in-progress one is joined with a dashed segment.
    final line = Paint()
      ..color = colors.line
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 1; i < semesters.length; i++) {
      final a = pointAt(i - 1);
      final b = pointAt(i);
      if (semesters[i].inProgress) {
        const dash = 4.0;
        final length = (b - a).distance;
        final dir = (b - a) / length;
        for (var d = 0.0; d < length; d += dash * 2) {
          canvas.drawLine(a + dir * d, a + dir * (d + dash).clamp(0, length), line);
        }
      } else {
        canvas.drawLine(a, b, line);
      }
    }

    // ≥8px markers with a 2px surface ring; hollow for the semester still running.
    for (var i = 0; i < semesters.length; i++) {
      final p = pointAt(i);
      canvas.drawCircle(p, 6, Paint()..color = colors.surface);
      canvas.drawCircle(
        p,
        4.5,
        Paint()
          ..color = colors.line
          ..style = semesters[i].inProgress ? PaintingStyle.stroke : PaintingStyle.fill
          ..strokeWidth = 2,
      );
      _text(canvas, semesters[i].term, Offset(p.dx, plotTop + plotHeight + 16), align: TextAlign.center);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => old.semesters != semesters || old.colors.line != colors.line;
}
