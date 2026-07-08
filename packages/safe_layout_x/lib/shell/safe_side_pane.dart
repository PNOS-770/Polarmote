import 'package:flutter/material.dart';

import '../containers/safe_container.dart';

class SafeSidePane extends StatelessWidget {
  const SafeSidePane({
    super.key,
    required this.body,
    this.title,
    this.actions = const <Widget>[],
    this.onPointerDown,
    this.backgroundColor = Colors.white,
    this.borderColor = const Color(0xFFE0E0E0),
    this.headerPadding = const EdgeInsets.fromLTRB(16, 16, 16, 8),
    this.showHeaderDivider = true,
  });

  final Widget body;
  final String? title;
  final List<Widget> actions;
  final VoidCallback? onPointerDown;
  final Color backgroundColor;
  final Color borderColor;
  final EdgeInsets headerPadding;
  final bool showHeaderDivider;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onPointerDown?.call(),
      behavior: HitTestBehavior.translucent,
      child: SafeContainer(
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border(right: BorderSide(color: borderColor)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null || actions.isNotEmpty)
              Padding(
                padding: headerPadding,
                child: Row(
                  children: [
                    if (title != null)
                      Expanded(
                        child: Text(
                          title!,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ...actions,
                  ],
                ),
              ),
            if (showHeaderDivider && (title != null || actions.isNotEmpty))
              const Divider(height: 1),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
