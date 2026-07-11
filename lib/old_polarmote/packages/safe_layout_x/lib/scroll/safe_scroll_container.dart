import 'package:flutter/widgets.dart';

class SafeScrollContainer extends StatelessWidget {
  const SafeScrollContainer({
    super.key,
    required this.child,
    this.padding,
    this.controller,
    this.physics,
    this.primary,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final bool? primary;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: controller,
      primary: primary,
      physics: physics,
      padding: padding,
      child: child,
    );
  }
}
