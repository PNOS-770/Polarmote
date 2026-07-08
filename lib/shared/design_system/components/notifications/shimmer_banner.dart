import 'package:flutter/material.dart';
import 'package:safe_layout_x/safe_layout_x.dart';

import '../../theme/app_radius.dart';

class ShimmerBannerWidget extends StatefulWidget {
  const ShimmerBannerWidget({
    super.key,
    required this.data,
    required this.onDismiss,
    required this.width,
  });

  final BannerData data;
  final VoidCallback onDismiss;
  final double width;

  @override
  State<ShimmerBannerWidget> createState() => _ShimmerBannerWidgetState();
}

class _ShimmerBannerWidgetState extends State<ShimmerBannerWidget>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  bool _exiting = false;

  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0.18, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();

    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_exiting) return;
    _exiting = true;
    await _controller.reverse();
    if (!mounted) return;
    widget.onDismiss();
  }

  Color _accentColor(BannerType type) {
    return switch (type) {
      BannerType.success => const Color(0xFF2F7A53),
      BannerType.error => const Color(0xFFB04444),
      BannerType.warning => const Color(0xFFB7791F),
      BannerType.info => const Color(0xFF2F647D),
      BannerType.progress => const Color(0xFF0F766E),
    };
  }

  Color _backgroundColor(BannerType type) {
    return switch (type) {
      BannerType.success => const Color(0xFFEEF8F2),
      BannerType.error => const Color(0xFFFDEEEE),
      BannerType.warning => const Color(0xFFFFF7E8),
      BannerType.info => const Color(0xFFEEF5F8),
      BannerType.progress => const Color(0xFFEDF6F5),
    };
  }

  IconData _icon(BannerType type) {
    return switch (type) {
      BannerType.success => Icons.check_circle,
      BannerType.error => Icons.error,
      BannerType.warning => Icons.warning,
      BannerType.info => Icons.info,
      BannerType.progress => Icons.sync,
    };
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final accent = _accentColor(data.type);
    final background = _backgroundColor(data.type);

    return MouseRegion(
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: SizedBox(
            width: widget.width,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: AppRadius.radiusDialog,
                onTap: data.onTap,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: AppRadius.radiusDialog,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      ),
                    ],
                    border: Border(left: BorderSide(color: accent, width: 3)),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: _shimmerController,
                          builder: (context, child) {
                            return CustomPaint(
                              painter: _BannerShimmerPainter(
                                progress: _shimmerController.value,
                                accentColor: accent,
                              ),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(_icon(data.type), size: 18, color: accent),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        data.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF223238),
                                        ),
                                      ),
                                      if (data.message.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          data.message,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF5E727A),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkResponse(
                                  radius: 16,
                                  onTap: _dismiss,
                                  child: const Icon(Icons.close, size: 16),
                                ),
                              ],
                            ),
                            if (data.progress != null) ...[
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: data.progress!.clamp(0.0, 1.0),
                                  backgroundColor: const Color(0xFFE0E0E0),
                                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                                  minHeight: 4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BannerShimmerPainter extends CustomPainter {
  _BannerShimmerPainter({
    required this.progress,
    required this.accentColor,
  });

  final double progress;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final bandWidth = size.width * 0.3;
    final featherWidth = bandWidth * 0.35;
    final centerX = progress * (size.width + bandWidth) - bandWidth / 2;

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          accentColor.withValues(alpha: 0),
          accentColor.withValues(alpha: 0.12),
          accentColor.withValues(alpha: 0.12),
          accentColor.withValues(alpha: 0),
        ],
        stops: const [0, 0.35, 0.65, 1],
      ).createShader(Rect.fromLTWH(
        centerX - bandWidth / 2 - featherWidth / 2,
        0,
        bandWidth + featherWidth,
        size.height,
      ));

    canvas.drawRect(
      Rect.fromLTWH(
        centerX - bandWidth / 2 - featherWidth / 2,
        0,
        bandWidth + featherWidth,
        size.height,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_BannerShimmerPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.accentColor != accentColor;
  }
}

