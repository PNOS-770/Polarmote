import 'package:flutter/widgets.dart';

class SmartScrollController {
  SmartScrollController({ScrollController? controller})
    : controller = controller ?? ScrollController();

  final ScrollController controller;
  bool _autoFollowEnabled = true;

  bool get autoFollowEnabled => _autoFollowEnabled;

  void pauseAutoFollow() {
    _autoFollowEnabled = false;
  }

  void resumeAutoFollow() {
    _autoFollowEnabled = true;
  }

  Future<void> maybeScrollToEnd({
    Duration duration = const Duration(milliseconds: 180),
    Curve curve = Curves.easeOut,
  }) async {
    if (!_autoFollowEnabled || !controller.hasClients) return;
    final target = controller.position.maxScrollExtent;
    await controller.animateTo(target, duration: duration, curve: curve);
  }

  void dispose() {
    controller.dispose();
  }
}
