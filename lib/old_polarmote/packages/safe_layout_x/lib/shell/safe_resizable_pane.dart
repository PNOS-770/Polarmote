import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../containers/safe_container.dart';
import '../containers/safe_stack.dart';
import '../flex/safe_column.dart';
import 'shell_models.dart';

class SafeResizablePane extends StatelessWidget {
  const SafeResizablePane({
    super.key,
    required this.pane,
    required this.width,
    required this.pushWidth,
    required this.minWidth,
    this.visible = true,
  });

  final Widget pane;
  final double width;
  final double pushWidth;
  final double minWidth;
  final bool visible;

  double _effectiveMinWidth() {
    if (!minWidth.isFinite || minWidth < 0) return 0;
    return minWidth;
  }

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final floorWidth = _effectiveMinWidth();
    final renderWidth = width < floorWidth ? floorWidth : width;
    final layoutWidth =
        pushWidth.isFinite && pushWidth > 0 ? pushWidth : 0.0;
    if (layoutWidth <= 0 && renderWidth <= 0) {
      return const SizedBox.shrink();
    }
    final overflowChild = _PaneWidthOverflow(
      renderWidth: renderWidth,
      child: pane,
    );
    return SizedBox(
      width: layoutWidth,
      child: width < floorWidth
          ? ClipRect(child: overflowChild)
          : overflowChild,
    );
  }
}

class _PaneWidthOverflow extends SingleChildRenderObjectWidget {
  const _PaneWidthOverflow({required this.renderWidth, required Widget child})
      : super(child: child);

  final double renderWidth;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderPaneWidthOverflow(renderWidth: renderWidth);
  }

  @override
  void updateRenderObject(
      BuildContext context, _RenderPaneWidthOverflow renderObject) {
    renderObject.renderWidth = renderWidth;
  }
}

class _RenderPaneWidthOverflow extends RenderProxyBox {
  _RenderPaneWidthOverflow({required double renderWidth})
      : _renderWidth = renderWidth;

  double get renderWidth => _renderWidth;
  double _renderWidth;
  set renderWidth(double value) {
    if (_renderWidth == value) return;
    _renderWidth = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    if (child != null) {
      child!.layout(
        BoxConstraints(
          minWidth: renderWidth,
          maxWidth: renderWidth,
          minHeight: constraints.minHeight,
          maxHeight: constraints.maxHeight,
        ),
        parentUsesSize: false,
      );
    }
    size = constraints.smallest;
  }
}

class SafePaneDragHandle extends StatefulWidget {
  const SafePaneDragHandle({
    super.key,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.enabled = true,
    this.showLine = true,
    this.style = const SafeResizablePaneStyle(),
  });

  final VoidCallback? onDragStart;
  final ValueChanged<double>? onDragUpdate;
  final VoidCallback? onDragEnd;
  final bool enabled;
  final bool showLine;
  final SafeResizablePaneStyle style;

  @override
  State<SafePaneDragHandle> createState() => _SafePaneDragHandleState();
}

class _SafePaneDragHandleState extends State<SafePaneDragHandle> {
  bool _hovering = false;

  void _handleDragStart(DragStartDetails _) {
    if (!widget.enabled) return;
    widget.onDragStart?.call();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;
    widget.onDragUpdate?.call(details.delta.dx);
  }

  void _handleDragEnd([DragEndDetails? _]) {
    if (!widget.enabled) return;
    widget.onDragEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final dividerLineWidth =
        _hovering ? style.dividerHoverLineWidth : style.dividerLineWidth;
    final dividerLineAlignment = switch (style.dividerLineAlignment) {
      SafePaneDividerAlignment.start => Alignment.centerLeft,
      SafePaneDividerAlignment.center => Alignment.center,
      SafePaneDividerAlignment.end => Alignment.centerRight,
    };
    final dividerLineOffsetX = switch (style.dividerLineAlignment) {
      SafePaneDividerAlignment.start => -dividerLineWidth / 2,
      SafePaneDividerAlignment.center => 0.0,
      SafePaneDividerAlignment.end => dividerLineWidth / 2,
    };
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.resizeColumn
          : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: widget.enabled ? _handleDragStart : null,
        onHorizontalDragUpdate: widget.enabled ? _handleDragUpdate : null,
        onHorizontalDragEnd: widget.enabled ? _handleDragEnd : null,
        onHorizontalDragCancel: widget.enabled ? _handleDragEnd : null,
        child: SizedBox(
          width: style.dividerHitWidth,
          child: SafeStack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (widget.showLine)
                Align(
                  alignment: dividerLineAlignment,
                  child: Transform.translate(
                    offset: Offset(dividerLineOffsetX, 0),
                    child: AnimatedContainer(
                      duration: style.animationDuration,
                      curve: Curves.easeOut,
                      width: dividerLineWidth,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: _hovering
                            ? style.dividerHoverColor
                            : style.dividerColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              if (style.showHandle)
                AnimatedOpacity(
                  duration: style.animationDuration,
                  opacity: _hovering ? 1 : 0.8,
                  child: SafeContainer(
                    width: style.handleWidth,
                    height: style.handleHeight,
                    alignment: Alignment.center,
                    child: SafeColumn(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _HandleDot(
                          active: _hovering,
                          size: style.handleDotSize,
                          normalColor: style.handleDotColor,
                          activeColor: style.handleDotHoverColor,
                        ),
                        SizedBox(height: style.handleDotGap),
                        _HandleDot(
                          active: _hovering,
                          size: style.handleDotSize,
                          normalColor: style.handleDotColor,
                          activeColor: style.handleDotHoverColor,
                        ),
                        SizedBox(height: style.handleDotGap),
                        _HandleDot(
                          active: _hovering,
                          size: style.handleDotSize,
                          normalColor: style.handleDotColor,
                          activeColor: style.handleDotHoverColor,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HandleDot extends StatelessWidget {
  const _HandleDot({
    required this.active,
    required this.size,
    required this.normalColor,
    required this.activeColor,
  });

  final bool active;
  final double size;
  final Color normalColor;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return SafeContainer(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: active ? activeColor : normalColor,
        shape: BoxShape.circle,
      ),
    );
  }
}
