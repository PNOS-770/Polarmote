import 'package:flutter/widgets.dart';

import '../foundation/overflow_guard.dart';

class AutoSafe extends StatelessWidget {
  const AutoSafe({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return OverflowGuard(child: child);
  }
}
