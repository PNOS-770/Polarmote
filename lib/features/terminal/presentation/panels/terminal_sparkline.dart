import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// ═══════════════════════════════════════════
//  Bottom-bar sparkline (unchanged)
// ═══════════════════════════════════════════

class AnimatedSparkline extends StatefulWidget {
  const AnimatedSparkline({
    super.key,
    required this.history,
    required this.getColor,
    this.smooth = false,
    this.height = 16,
    this.showFill = false,
    this.showGlow = false,
    this.strokeWidth = 1.5,
  });

  final List<double> history;
  final Color Function(double fraction) getColor;
  final bool smooth;
  final double height;
  final bool showFill;
  final bool showGlow;
  final double strokeWidth;

  @override
  State<AnimatedSparkline> createState() => _AnimatedSparklineState();
}

class _AnimatedSparklineState extends State<AnimatedSparkline>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) { if (mounted) setState(() {}); });
    _ticker.start();
  }

  @override
  void dispose() { _ticker.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final h = widget.history;
    final n = h.length;
    final ht = widget.height;
    if (n < 1) return SizedBox(height: ht);
    final v = widget.smooth ? _smooth(h) : h;
    if (n == 1) {
      final c = widget.getColor(v[0]);
      return SizedBox(width: double.infinity, height: ht,
        child: CustomPaint(painter: _SparkPainter(
          points: [Offset(0, ht), Offset(16, ht * (1 - v[0]))],
          lineColor: c, fillColor: widget.showFill ? c.withValues(alpha: 0.08) : null,
          showGlow: widget.showGlow, strokeWidth: widget.strokeWidth)));
    }
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      if (w <= 0) return SizedBox(height: ht);
      final stepX = w / (n - 1);
      final pts = List.generate(n, (i) => Offset(i * stepX, ht * (1 - v[i].clamp(0.0, 1.0))));
      final c = widget.getColor(v.last);
      return SizedBox(width: w, height: ht,
        child: CustomPaint(painter: _SparkPainter(
          points: pts, lineColor: c,
          fillColor: widget.showFill ? c.withValues(alpha: 0.08) : null,
          showGlow: widget.showGlow, strokeWidth: widget.strokeWidth)));
    });
  }

  static List<double> _smooth(List<double> h) {
    if (h.isEmpty) return h;
    final r = [h[0]];
    for (var i = 1; i < h.length; i++) { r.add(0.3 * h[i] + 0.7 * r[i - 1]); }
    return r;
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({
    required this.points, required this.lineColor,
    this.fillColor, this.showGlow = false, this.strokeWidth = 1.5,
  });

  final List<Offset> points;
  final Color lineColor;
  final Color? fillColor;
  final bool showGlow;
  final double strokeWidth;

  static final _gp = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
  static final _lp = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    canvas.clipRect(Offset.zero & size);
    final path = _linePath(points);
    if (showGlow) {
      _gp..color = lineColor.withValues(alpha: 0.08)..strokeWidth = strokeWidth * 3;
      canvas.drawPath(path, _gp);
    }
    if (fillColor != null) {
      final fp = Path.from(path);
      fp.lineTo(points.last.dx, size.height); fp.lineTo(points.first.dx, size.height); fp.close();
      canvas.drawPath(fp, Paint()..color = fillColor!);
    }
    _lp..color = lineColor..strokeWidth = strokeWidth;
    canvas.drawPath(path, _lp);
  }

  static Path _linePath(List<Offset> pts) {
    final p = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i < pts.length; i++) { p.lineTo(pts[i].dx, pts[i].dy); }
    return p;
  }

  @override
  bool shouldRepaint(_SparkPainter o) =>
      o.points != points || o.lineColor != lineColor || o.showGlow != showGlow;
}

// ═══════════════════════════════════════════
//  Bar chart (side panel)
// ═══════════════════════════════════════════

class MonitorChart extends StatefulWidget {
  const MonitorChart({
    super.key,
    required this.history,
    required this.getColor,
    this.fixedColor,
    this.height = 56,
  });

  final List<double> history;
  final Color Function(double fraction) getColor;
  final Color? fixedColor;
  final double height;

  @override
  State<MonitorChart> createState() => _MonitorChartState();
}

class _MonitorChartState extends State<MonitorChart>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) { if (mounted) setState(() {}); });
    _ticker.start();
  }

  @override
  void dispose() { _ticker.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final h = widget.history;
    final count = math.min(h.length, 60);
    if (count < 2) return SizedBox(height: widget.height);

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      if (w <= 0) return SizedBox(height: widget.height);
      return _buildChart(w, h, count);
    });
  }

  Widget _buildChart(double width, List<double> history, int count) {
    final ht = widget.height;
    const tPad = 2.0, bPad = 2.0;
    final chartH = ht - tPad - bPad;
    if (chartH <= 0) return SizedBox(height: ht);

    final bars = <_BarEntry>[];
    final start = history.length - count;
    for (var i = start; i < history.length; i++) {
      final val = history[i].clamp(0.0, 1.0);
      bars.add(_BarEntry(
        value: val,
        color: widget.fixedColor ?? widget.getColor(val),
      ));
    }

    return SizedBox(width: width, height: ht,
      child: CustomPaint(painter: _BarPainter(
        bars: bars, chartHeight: chartH, topPad: tPad)));
  }
}

class _BarEntry {
  final double value;
  final Color color;
  const _BarEntry({required this.value, required this.color});
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.bars,
    required this.chartHeight,
    this.topPad = 2,
  });

  final List<_BarEntry> bars;
  final double chartHeight;
  final double topPad;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final n = bars.length;
    final barWidth = size.width / n;
    final gap = barWidth * 0.15;
    final drawW = barWidth - gap;

    for (var i = 0; i < n; i++) {
      final bar = bars[i];
      final barH = chartHeight * bar.value;
      final x = i * barWidth + gap / 2;
      final y = topPad + chartHeight - barH;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, drawW, barH),
          const Radius.circular(1.5),
        ),
        Paint()..color = bar.color,
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter o) => o.bars != bars;
}
