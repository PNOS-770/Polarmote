import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../containers/safe_container.dart';
import 'safe_resizable_pane.dart';
import 'shell_models.dart';

class SafeDesktopPaneLayout extends StatefulWidget {
  const SafeDesktopPaneLayout({
    super.key,
    required this.pane,
    required this.main,
    this.config = const SafeDesktopPaneLayoutConfig(),
    this.onPaneVisibilityChanged,
    this.onPaneWidthChanged,
  });

  final Widget pane;
  final Widget main;
  final SafeDesktopPaneLayoutConfig config;
  final ValueChanged<bool>? onPaneVisibilityChanged;
  final ValueChanged<double>? onPaneWidthChanged;

  @override
  State<SafeDesktopPaneLayout> createState() => _SafeDesktopPaneLayoutState();
}

class _SafeDesktopPaneLayoutState extends State<SafeDesktopPaneLayout> {
  double _paneWidth = 0;
  double _lastAvailableWidth = 0;
  double _lastMaxWidth = 0;
  bool _dragging = false;
  double _previewWidth = 0;
  bool _lastVisible = true;
  Object? _lastRevealToken;
  bool _initialWidthResolved = false;

  @override
  void initState() {
    super.initState();
    _paneWidth = widget.config.initialPaneWidth;
    _lastVisible = _paneWidth > _collapseThreshold;
    _lastRevealToken = widget.config.revealToken;
  }

  @override
  void didUpdateWidget(covariant SafeDesktopPaneLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    final token = widget.config.revealToken;
    if (token != _lastRevealToken) {
      _lastRevealToken = token;
      if (_paneWidth <= _collapseThreshold) {
        final restored = _resolveInitialPaneWidth();
        _applyWidth(restored);
      }
    }
  }

  double get _collapseThreshold {
    final snap = widget.config.collapseSnapWidth;
    if (!snap.isFinite || snap < 0) return 0;
    return snap;
  }

  void _setStateOrSchedule(VoidCallback fn) {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks ||
        SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(fn);
      });
      return;
    }
    setState(fn);
  }

  double _clampWidth(double width) {
    if (!width.isFinite) return _paneWidth;
    final configMax = widget.config.paneMaxWidth;
    final maxWidth = _lastMaxWidth.isFinite && _lastMaxWidth > 0
        ? _lastMaxWidth
        : (configMax.isFinite ? configMax : width);
    return width.clamp(0.0, maxWidth).toDouble();
  }

  double _resolveInitialPaneWidth() {
    final availableWidth = _lastAvailableWidth;
    final config = widget.config;
    final maxWidth = _lastMaxWidth.isFinite && _lastMaxWidth > 0
        ? _lastMaxWidth
        : (config.paneMaxWidth.isFinite ? config.paneMaxWidth : availableWidth);
    final mainInitialWidth = config.mainInitialWidth;
    if (availableWidth > 0 &&
        mainInitialWidth != null &&
        mainInitialWidth.isFinite &&
        mainInitialWidth > 0) {
      final desiredMain = mainInitialWidth
          .clamp(0.0, availableWidth)
          .toDouble();
      final desiredPane = (availableWidth - desiredMain)
          .clamp(0.0, maxWidth)
          .toDouble();
      return desiredPane;
    }
    return config.initialPaneWidth;
  }

  void _maybeApplyInitialFromMain() {
    if (_initialWidthResolved) return;
    final availableWidth = _lastAvailableWidth;
    final config = widget.config;
    final maxWidth = _lastMaxWidth.isFinite && _lastMaxWidth > 0
        ? _lastMaxWidth
        : (config.paneMaxWidth.isFinite ? config.paneMaxWidth : availableWidth);
    final mainInitialWidth = widget.config.mainInitialWidth;
    if (mainInitialWidth == null ||
        !mainInitialWidth.isFinite ||
        mainInitialWidth <= 0) {
      _initialWidthResolved = true;
      return;
    }
    if (!availableWidth.isFinite || availableWidth <= 0) return;
    final desiredMain = mainInitialWidth.clamp(0.0, availableWidth).toDouble();
    final desiredPane = (availableWidth - desiredMain)
        .clamp(0.0, maxWidth)
        .toDouble();
    _initialWidthResolved = true;
    final clamped = _clampWidth(desiredPane);
    if ((clamped - _paneWidth).abs() < 0.001) return;
    _paneWidth = clamped;
    widget.onPaneWidthChanged?.call(_paneWidth);
    _notifyVisibilityIfNeeded();
  }

  void _applyWidth(double nextWidth) {
    final clamped = _clampWidth(nextWidth);
    if ((clamped - _paneWidth).abs() < 0.001) return;
    _setStateOrSchedule(() {
      _paneWidth = clamped;
    });
    widget.onPaneWidthChanged?.call(_paneWidth);
    _notifyVisibilityIfNeeded();
  }

  void _notifyVisibilityIfNeeded() {
    final visible = _paneWidth > _collapseThreshold;
    if (visible == _lastVisible) return;
    _lastVisible = visible;
    widget.onPaneVisibilityChanged?.call(visible);
  }

  void _requestResize(double width) {
    _applyWidth(width);
  }

  void _handleDragStart() {
    if (!_dragging) {
      _dragging = true;
      _previewWidth = _paneWidth;
    }
  }

  void _handleDragUpdate(double delta) {
    if (!_dragging) return;
    final maxWidth = _lastMaxWidth.isFinite && _lastMaxWidth > 0
        ? _lastMaxWidth
        : double.infinity;
    _previewWidth = (_previewWidth + delta).clamp(0.0, maxWidth).toDouble();
    _setStateOrSchedule(() {});
  }

  void _handleDragEnd() {
    if (!_dragging) return;
    _dragging = false;
    final edgeSnapWidth = widget.config.edgeSnapWidth;
    final snap = edgeSnapWidth.isFinite && edgeSnapWidth > 0
        ? edgeSnapWidth
        : 0.0;
    var next = _previewWidth;
    if (next <= (_collapseThreshold + snap)) {
      next = 0;
    } else {
      final maxWidth = _lastMaxWidth;
      if (maxWidth.isFinite && maxWidth > 0) {
        if ((maxWidth - next).abs() <= snap) {
          next = maxWidth;
        }
      }
    }
    _previewWidth = 0;
    _applyWidth(next);
  }

  Widget _buildRevealButton(BuildContext context, VoidCallback onPressed) {
    final builder = widget.config.revealButtonBuilder;
    if (builder != null) {
      return builder(context, onPressed);
    }
    return SafeContainer(
      width: 28,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
        border: Border.all(color: const Color(0xFFE0E0E0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.chevron_left, size: 18),
        onPressed: onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final animationDuration =
        config.animationDuration ?? config.paneStyle.animationDuration;
    return LayoutBuilder(
      builder: (context, constraints) {
        final rawAvailableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final availableWidth = rawAvailableWidth.isFinite
            ? rawAvailableWidth.clamp(0.0, double.infinity).toDouble()
            : 0.0;
        final maxWidth = config.paneMaxWidth.isFinite
            ? config.paneMaxWidth.clamp(0.0, availableWidth).toDouble()
            : availableWidth;
        _lastAvailableWidth = availableWidth;
        _lastMaxWidth = maxWidth;
        _maybeApplyInitialFromMain();
        final paneMinWidth =
            config.paneMinWidth.isFinite && config.paneMinWidth > 0
            ? config.paneMinWidth
            : 0.0;
        final baseMainMinWidth =
            config.mainMinWidth.isFinite && config.mainMinWidth > 0
            ? config.mainMinWidth
            : 0.0;
        final paneWidth = _paneWidth.clamp(0.0, maxWidth).toDouble();
        final paneVisible = paneWidth > _collapseThreshold;
        final paneFullyExpanded = paneVisible && paneWidth >= (maxWidth - 0.5);
        final effectiveMainMinWidth = paneFullyExpanded
            ? 0.0
            : baseMainMinWidth;
        final maxPushWidth = (availableWidth - effectiveMainMinWidth)
            .clamp(0.0, maxWidth)
            .toDouble();
        final pushWidth = paneWidth.clamp(0.0, maxPushWidth).toDouble();
        final mainWidth = (availableWidth - pushWidth)
            .clamp(0.0, availableWidth)
            .toDouble();
        final paneBelowMin = paneVisible && paneWidth < (paneMinWidth - 0.5);
        final mainHidden = mainWidth <= 1;
        final mainCoversPane = paneBelowMin;
        final showRevealButton =
            config.showRevealButton &&
            paneVisible &&
            maxWidth > 0 &&
            paneWidth >= (maxWidth - 0.5);
        final mainSurface = ClipRect(
          child: SafeContainer(
            decoration: BoxDecoration(color: config.mainBackgroundColor),
            child: widget.main,
          ),
        );
        final mainView = Positioned(
          left: pushWidth,
          top: 0,
          bottom: 0,
          width: mainWidth,
          child: AnimatedContainer(
            duration: animationDuration,
            curve: Curves.easeOut,
            child: mainSurface,
          ),
        );

        final paneView = Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: SafeResizablePane(
            pane: widget.pane,
            width: paneWidth,
            pushWidth: pushWidth,
            minWidth: paneMinWidth,
            visible: paneVisible,
          ),
        );

        final revealButton = Positioned.fill(
          child: Align(
            alignment: Alignment.centerRight,
            child: AnimatedOpacity(
              duration: animationDuration,
              opacity: showRevealButton ? 1 : 0,
              child: AnimatedSlide(
                duration: animationDuration,
                offset: showRevealButton ? Offset.zero : const Offset(0.4, 0),
                curve: Curves.easeOut,
                child: IgnorePointer(
                  ignoring: !showRevealButton,
                  child: _buildRevealButton(
                    context,
                    () => _requestResize(_resolveInitialPaneWidth()),
                  ),
                ),
              ),
            ),
          ),
        );

        final handleWidth = config.paneStyle.dividerHitWidth;
        final maxHandleLeft = (availableWidth - handleWidth).clamp(
          0.0,
          double.infinity,
        );
        final dragLineX = _dragging
            ? _previewWidth.clamp(0.0, availableWidth).toDouble()
            : paneWidth.clamp(0.0, availableWidth).toDouble();
        final dragHandle = Positioned(
          left: (dragLineX - handleWidth / 2).clamp(0.0, maxHandleLeft),
          top: 0,
          bottom: 0,
          child: SafePaneDragHandle(
            enabled: paneVisible,
            style: config.paneStyle,
            showLine:
                config.paneStyle.showDividerLine || paneBelowMin || _dragging,
            onDragStart: _handleDragStart,
            onDragUpdate: _handleDragUpdate,
            onDragEnd: _handleDragEnd,
          ),
        );

        final dragOverlay = Positioned.fill(
          child: IgnorePointer(
            child: _PaneBlueprintDragOverlay(
              progress: availableWidth <= 0
                  ? 0.5
                  : (dragLineX / availableWidth).clamp(0.0, 1.0).toDouble(),
              centerX: dragLineX,
              overlayColor: config.dragOverlayColor,
            ),
          ),
        );

        final children = <Widget>[
          if (mainCoversPane) paneView,
          if (mainCoversPane && !mainHidden) mainView,
          if (!mainCoversPane && !mainHidden) mainView,
          if (!mainCoversPane) paneView,
          if (paneVisible) dragHandle,
          if (_dragging) dragOverlay,
          revealButton,
        ];

        return Stack(clipBehavior: Clip.none, children: children);
      },
    );
  }
}

class _PaneBlueprintDragOverlay extends StatelessWidget {
  const _PaneBlueprintDragOverlay({
    required this.progress,
    required this.centerX,
    required this.overlayColor,
  });

  final double progress;
  final double centerX;
  final Color overlayColor;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: progress, end: progress),
      duration: const Duration(milliseconds: 80),
      curve: Curves.easeOutCubic,
      builder: (context, animatedProgress, child) {
        return ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 1.6, sigmaY: 1.6),
            child: CustomPaint(
              painter: _PaneBlueprintDragPainter(
                progress: animatedProgress,
                centerX: centerX,
                overlayColor: overlayColor,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PaneBlueprintDragPainter extends CustomPainter {
  const _PaneBlueprintDragPainter({
    required this.progress,
    required this.centerX,
    required this.overlayColor,
  });

  final double progress;
  final double centerX;
  final Color overlayColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final center = centerX.clamp(0.0, size.width).toDouble();
    final pull = ((progress - 0.5).abs() * 2).clamp(0.0, 1.0).toDouble();
    final accent = overlayColor.withValues(alpha: 1).computeLuminance() > 0.6
        ? const Color(0xFF38BDF8)
        : overlayColor.withValues(alpha: 1);
    final baseRect = Offset.zero & size;

    final scrim = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF020617).withValues(alpha: 0.34 + pull * 0.08),
          const Color(0xFF0F172A).withValues(alpha: 0.22 + pull * 0.07),
          const Color(0xFF020617).withValues(alpha: 0.36 + pull * 0.08),
        ],
        stops: const [0, 0.52, 1],
      ).createShader(baseRect);
    canvas.drawRect(baseRect, scrim);

    final leftRect = Rect.fromLTWH(0, 0, center, size.height);
    final rightRect = Rect.fromLTWH(
      center,
      0,
      size.width - center,
      size.height,
    );
    final leftWash = Paint()
      ..shader = LinearGradient(
        colors: [
          accent.withValues(alpha: 0.03),
          accent.withValues(alpha: 0.11 + pull * 0.04),
        ],
      ).createShader(leftRect);
    final rightWash = Paint()
      ..shader = LinearGradient(
        colors: [
          accent.withValues(alpha: 0.11 + pull * 0.04),
          accent.withValues(alpha: 0.03),
        ],
      ).createShader(rightRect);
    canvas.drawRect(leftRect, leftWash);
    canvas.drawRect(rightRect, rightWash);

    _drawGrid(canvas, size, accent, center, pull);
    _drawCenterGuide(canvas, size, accent, center, pull);
    _drawWidthBadge(canvas, size, accent, center);
  }

  void _drawGrid(
    Canvas canvas,
    Size size,
    Color accent,
    double center,
    double pull,
  ) {
    final minorPaint = Paint()
      ..color = accent.withValues(alpha: 0.08 + pull * 0.04)
      ..strokeWidth = 1;
    final majorPaint = Paint()
      ..color = accent.withValues(alpha: 0.16 + pull * 0.04)
      ..strokeWidth = 1;

    const minorStep = 24.0;
    const majorStep = 96.0;
    for (double x = center % minorStep; x < size.width; x += minorStep) {
      final major = (x - center).abs() % majorStep < 0.5;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        major ? majorPaint : minorPaint,
      );
    }
    for (double y = 0; y < size.height; y += minorStep) {
      final major = y % majorStep < 0.5;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        major ? majorPaint : minorPaint,
      );
    }

    final paneFill = Paint()
      ..color = accent.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, center, size.height), paneFill);
  }

  void _drawCenterGuide(
    Canvas canvas,
    Size size,
    Color accent,
    double center,
    double pull,
  ) {
    final glowPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          accent.withValues(alpha: 0),
          accent.withValues(alpha: 0.22 + pull * 0.16),
          accent.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(center - 18, 0, 36, size.height));
    canvas.drawRect(Rect.fromLTWH(center - 18, 0, 36, size.height), glowPaint);

    final linePaint = Paint()
      ..color = accent.withValues(alpha: 0.9)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(center, 0), Offset(center, size.height), linePaint);

    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.48)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (double y = 12; y < size.height; y += 18) {
      canvas.drawLine(Offset(center - 6, y), Offset(center + 6, y), tickPaint);
    }
  }

  void _drawWidthBadge(Canvas canvas, Size size, Color accent, double center) {
    final label = '${center.round()} px';
    const textStyle = TextStyle(
      color: Color(0xFFE0F2FE),
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
    );
    final painter = TextPainter(
      text: TextSpan(text: label, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final badgeWidth = painter.width + 28;
    const badgeHeight = 28.0;
    final left = (center - badgeWidth / 2).clamp(
      10.0,
      (size.width - badgeWidth - 10).clamp(10.0, double.infinity),
    );
    final top = size.height < 90 ? 10.0 : 22.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, badgeWidth, badgeHeight),
      const Radius.circular(999),
    );

    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.24)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawRRect(rect.shift(const Offset(0, 2)), shadow);
    final fill = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF0F172A).withValues(alpha: 0.82),
          const Color(0xFF082F49).withValues(alpha: 0.78),
        ],
      ).createShader(rect.outerRect);
    canvas.drawRRect(rect, fill);
    final border = Paint()
      ..color = accent.withValues(alpha: 0.62)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(rect, border);

    final textOffset = Offset(
      left + (badgeWidth - painter.width) / 2,
      top + (badgeHeight - painter.height) / 2,
    );
    painter.paint(canvas, textOffset);
  }

  @override
  bool shouldRepaint(covariant _PaneBlueprintDragPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.centerX != centerX ||
        oldDelegate.overlayColor != overlayColor;
  }
}
