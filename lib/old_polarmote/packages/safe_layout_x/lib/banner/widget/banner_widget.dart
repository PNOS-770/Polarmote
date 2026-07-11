import 'package:flutter/material.dart';

import '../manager/banner_manager.dart';
import '../model/banner_data.dart';
import '../theme/banner_theme.dart';
import 'banner_icon.dart';
import 'banner_progress.dart';

class BannerWidget extends StatefulWidget {
  const BannerWidget({
    super.key,
    required this.data,
    required this.onDismiss,
    required this.width,
  });

  final BannerData data;
  final VoidCallback onDismiss;
  final double width;

  @override
  State<BannerWidget> createState() => _BannerWidgetState();
}

class _BannerWidgetState extends State<BannerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  bool _exiting = false;

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
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_exiting) return;
    _exiting = true;
    await _controller.reverse();
    if (!mounted) return;
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final theme = BannerTheme.of(context);
    final accent = theme.accentColor(data.type, context);
    final background = theme.backgroundFor(data.type);
    return MouseRegion(
      onEnter: (_) => BannerManager.pauseTimer(data.id),
      onExit: (_) => BannerManager.resumeTimer(data.id),
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: SizedBox(
            width: widget.width,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: theme.borderRadius,
                onTap: data.onTap,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: theme.borderRadius,
                    boxShadow: [theme.shadow],
                    border: Border(left: BorderSide(color: accent, width: 3)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BannerIcon(type: data.type),
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
                                  style: theme.titleStyle,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  data.message,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.messageStyle,
                                ),
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
                        BannerProgress(value: data.progress!),
                      ],
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
