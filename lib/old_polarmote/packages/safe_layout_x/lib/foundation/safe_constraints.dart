import 'package:flutter/widgets.dart';

@immutable
class SafeConstraints {
  const SafeConstraints({
    required this.maxWidth,
    required this.maxHeight,
    required this.minWidth,
    required this.minHeight,
  });

  factory SafeConstraints.fromBoxConstraints(BoxConstraints constraints) {
    return SafeConstraints(
      maxWidth: constraints.maxWidth,
      maxHeight: constraints.maxHeight,
      minWidth: constraints.minWidth,
      minHeight: constraints.minHeight,
    );
  }

  final double maxWidth;
  final double maxHeight;
  final double minWidth;
  final double minHeight;

  bool get hasBoundedWidth => maxWidth.isFinite;
  bool get hasBoundedHeight => maxHeight.isFinite;
}

extension SafeBoxConstraintsX on BoxConstraints {
  SafeConstraints get safe => SafeConstraints.fromBoxConstraints(this);
}
