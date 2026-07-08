import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../shared/constants/app_string.dart';
import '../shared/design_system/design_system.dart';

class MobileStartupGate extends StatefulWidget {
  const MobileStartupGate({required this.child, super.key});

  final Widget child;

  @override
  State<MobileStartupGate> createState() => _MobileStartupGateState();
}

class _MobileStartupGateState extends State<MobileStartupGate>
    with SingleTickerProviderStateMixin {
  static const MethodChannel _startupGuardChannel = MethodChannel(
    'Polarmote/startup_guard',
  );
  static const String _startupGuardDoneFileName = 'startup_guard_done_v1.flag';

  late final bool _shouldAnimate = _isMobilePlatform();
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final Animation<double> _elementsProgress = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.68, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _overlayOpacity = Tween<double>(begin: 1, end: 0)
      .animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.72, 1, curve: Curves.easeOut),
        ),
      );
  late final Animation<double> _contentOpacity = Tween<double>(begin: 0, end: 1)
      .animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.58, 1, curve: Curves.easeOut),
        ),
      );
  late final Future<List<String>> _blueLayerSvgs = _loadBlueLayerSvgs();

  bool _completed = false;
  bool _startupGateReady = false;
  bool _startupGatePassed = false;
  bool _exitTriggered = false;
  String _startupStatus = '';

  static bool _isMobilePlatform() {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => true,
      TargetPlatform.iOS => true,
      _ => false,
    };
  }

  @override
  void initState() {
    super.initState();
    if (!_shouldAnimate) {
      _completed = true;
    } else {
      _controller.forward().whenComplete(() {
        if (!mounted) return;
        setState(() => _completed = true);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runStartupGate());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<List<String>> _loadBlueLayerSvgs() async {
    try {
      final raw = await rootBundle.loadString('assets/images/app_icon.svg');
      final viewBox = _matchFirst(raw, RegExp(r'viewBox="([^"]+)"'));
      final defs = _matchFirst(raw, RegExp(r'<defs>([\s\S]*?)</defs>'));
      final bluePathTag = _matchFirst(
        raw,
      RegExp(r'(<path[^>]*fill="url\(#blue\)"[^>]*/>)'),
    );
    final blueD = _matchFirst(bluePathTag, RegExp(r'd="([^"]+)"'));
    final fillRuleMatch = RegExp(
      r'fill-rule="([^"]+)"',
    ).firstMatch(bluePathTag);
    final clipRuleMatch = RegExp(
      r'clip-rule="([^"]+)"',
    ).firstMatch(bluePathTag);
    final fillRule = fillRuleMatch?.group(1);
    final clipRule = clipRuleMatch?.group(1);
    final parts = RegExp(
      r'M\s*[^M]+?Z',
    ).allMatches(blueD).map((m) => m.group(0)!).toList(growable: false);
    if (parts.length < 3) {
      return const [];
    }
    final attrs = StringBuffer('fill="url(#blue)"');
    if (fillRule != null) {
      attrs.write(' fill-rule="$fillRule"');
    }
    if (clipRule != null) {
      attrs.write(' clip-rule="$clipRule"');
    }
    return parts
        .take(3)
        .map((segment) {
          return '''
<svg width="1024" height="1024" viewBox="$viewBox" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>$defs</defs>
  <path d="$segment" ${attrs.toString()} />
</svg>
''';
        })
        .toList(growable: false);
    } catch (e) {
      // 桌面端可能无法加载移动端资源，返回空列表
      return const [];
    }
  }

  String _matchFirst(String source, RegExp pattern) {
    final match = pattern.firstMatch(source);
    if (match == null || match.groupCount < 1 || match.group(1) == null) {
      throw StateError('Failed to parse startup logo SVG.');
    }
    return match.group(1)!;
  }

  bool get _isAndroidPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android;
  }

  bool _isChineseLocale() {
    final locale = Localizations.maybeLocaleOf(context);
    final languageCode = (locale?.languageCode ?? '').toLowerCase();
    return languageCode.startsWith('zh');
  }

  String _text(AppText text) {
    return text.resolve(_isChineseLocale() ? 'zh' : 'en');
  }

  Future<void> _runStartupGate() async {
    final enforce = await _shouldEnforceStartupGuard();
    if (!enforce) {
      if (!mounted) return;
      setState(() {
        _startupGateReady = true;
        _startupGatePassed = true;
      });
      return;
    }

    final alreadyDone = await _isStartupGuardDone();
    if (alreadyDone) {
      if (!mounted) return;
      setState(() {
        _startupGateReady = true;
        _startupGatePassed = true;
      });
      return;
    }

    if (!mounted) return;
    final agreed = await _showMandatoryIntroDialog();
    if (agreed != true) {
      await _exitAppNow();
      return;
    }

    if (!mounted) return;
    setState(() {
      _startupStatus = _text(AppStrings.values.checkingFirstLaunchPermissions);
    });
    final permissionsOk = await _ensureMandatoryPermissionsGranted();
    if (!permissionsOk) {
      await _exitAppNow();
      return;
    }

    if (!mounted) return;
    setState(() {
      _startupStatus = _text(AppStrings.values.checkingBatteryOptimization);
    });
    await _ensureBatteryOptimizationDisabled();

    await _markStartupGuardDone();

    if (!mounted) return;
    setState(() {
      _startupGateReady = true;
      _startupGatePassed = true;
      _startupStatus = '';
    });
  }

  Future<bool> _shouldEnforceStartupGuard() async {
    if (!_isAndroidPlatform) {
      return false;
    }
    return true;
  }

  Future<File> _startupGuardDoneFile() async {
    final base = await getApplicationSupportDirectory();
    return File('${base.path}/$_startupGuardDoneFileName');
  }

  Future<bool> _isStartupGuardDone() async {
    try {
      final file = await _startupGuardDoneFile();
      if (!await file.exists()) {
        return false;
      }
      final text = (await file.readAsString()).trim();
      return text == 'done';
    } catch (_) {
      return false;
    }
  }

  Future<void> _markStartupGuardDone() async {
    try {
      final file = await _startupGuardDoneFile();
      await file.writeAsString('done\n');
    } catch (_) {
      // Ignore first-launch flag persistence errors.
    }
  }

  Future<bool?> _showMandatoryIntroDialog() {
    return showConfirmDialog(
      context,
      title: _text(AppStrings.values.firstLaunchRequirements),
      message: _text(AppStrings.values.firstLaunchDesc),
      confirmText: _text(AppStrings.values.continueLabel),
      cancelText: _text(AppStrings.values.exitApp),
    );
  }

  Future<bool> _ensureMandatoryPermissionsGranted() async {
    if (!_isAndroidPlatform) {
      return true;
    }
    final notificationOk = await _ensureNotificationPermissionGranted();
    if (!notificationOk) {
      return false;
    }
    final storageOk = await _ensureStoragePermissionGranted();
    if (!storageOk) {
      return false;
    }
    return true;
  }

  Future<bool> _ensureNotificationPermissionGranted() async {
    try {
      var status = await Permission.notification.status;
      if (status.isGranted) {
        return true;
      }
      status = await Permission.notification.request();
      if (status.isGranted) {
        return true;
      }
      if (status.isPermanentlyDenied) {
        await openAppSettings();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        status = await Permission.notification.status;
        if (status.isGranted) {
          return true;
        }
      }
    } catch (_) {
      // Treat failures as not granted to enforce startup policy.
    }
    return false;
  }

  Future<bool> _ensureStoragePermissionGranted() async {
    Future<bool> hasPermission() async {
      final manage = await Permission.manageExternalStorage.status;
      if (manage.isGranted) {
        return true;
      }
      final storage = await Permission.storage.status;
      return storage.isGranted;
    }

    if (await hasPermission()) {
      return true;
    }

    var manageStatus = await Permission.manageExternalStorage.request();
    if (manageStatus.isGranted) {
      return true;
    }

    var storageStatus = await Permission.storage.request();
    if (storageStatus.isGranted) {
      return true;
    }

    if (manageStatus.isPermanentlyDenied || storageStatus.isPermanentlyDenied) {
      await openAppSettings();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (await hasPermission()) {
        return true;
      }
      manageStatus = await Permission.manageExternalStorage.status;
      storageStatus = await Permission.storage.status;
    }

    return manageStatus.isGranted || storageStatus.isGranted;
  }

  Future<void> _ensureBatteryOptimizationDisabled() async {
    if (!_isAndroidPlatform) return;
    if (await _isIgnoringBatteryOptimizations()) return;

    await _requestIgnoreBatteryOptimizations();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (await _isIgnoringBatteryOptimizations()) return;

    if (!mounted) return;
    final openSettings = await showConfirmDialog(
      context,
      title: _text(AppStrings.values.disableBatteryOptimization),
      message: _text(AppStrings.values.disableBatteryOptimizationDesc),
      confirmText: _text(AppStrings.values.openSettings),
      cancelText: _text(AppStrings.values.continueLabel),
    );
    if (openSettings != true) return;

    await _openBatteryOptimizationSettings();
    if (!mounted) return;
    await showConfirmDialog(
      context,
      title: _text(AppStrings.values.disableBatteryOptimization),
      message: _text(AppStrings.values.afterSettingsTapCheckAgain),
      confirmText: _text(AppStrings.values.continueLabel),
    );
  }

  Future<bool> _isIgnoringBatteryOptimizations() async {
    try {
      final result = await _startupGuardChannel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _requestIgnoreBatteryOptimizations() async {
    try {
      await _startupGuardChannel.invokeMethod<void>(
        'requestIgnoreBatteryOptimizations',
      );
    } catch (_) {
      // Ignore and continue with fallback settings flow.
    }
  }

  Future<void> _openBatteryOptimizationSettings() async {
    try {
      await _startupGuardChannel.invokeMethod<void>(
        'openBatteryOptimizationSettings',
      );
    } catch (_) {
      // Ignore settings launch failures.
    }
  }

  Future<void> _exitAppNow() async {
    if (_exitTriggered) {
      return;
    }
    _exitTriggered = true;
    if (mounted) {
      setState(() {
        _startupStatus = _text(AppStrings.values.requirementsNotMetExiting);
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (mounted) {
      await SystemNavigator.pop();
    }
  }

  Widget _buildBlockingScreen({double? progress, double? contentOpacity}) {
    final normalizedProgress = (progress ?? 1).clamp(0.0, 1.0).toDouble();
    final normalizedContentOpacity = (contentOpacity ?? 0)
        .clamp(0.0, 1.0)
        .toDouble();
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: Opacity(
            opacity: normalizedContentOpacity,
            child: widget.child,
          ),
        ),
        ColoredBox(
          color: AppColors.background,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FutureBuilder<List<String>>(
                  future: _blueLayerSvgs,
                  builder: (context, snapshot) {
                    final layers = snapshot.data ?? const <String>[];
                    return _AnimatedBlueLayers(
                      progress: normalizedProgress,
                      layers: layers,
                    );
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: 280,
                  child: Text(
                    _startupStatus.isEmpty
                        ? _text(AppStrings.values.preparingFirstLaunchChecks)
                        : _startupStatus,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if ((_completed || !_shouldAnimate) &&
        _startupGateReady &&
        _startupGatePassed) {
      return widget.child;
    }
    if (!_shouldAnimate || _completed) {
      return _buildBlockingScreen(progress: 1, contentOpacity: 0);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Opacity(
          opacity: _overlayOpacity.value,
          child: _buildBlockingScreen(
            progress: _elementsProgress.value,
            contentOpacity: _contentOpacity.value,
          ),
        );
      },
    );
  }
}

class _AnimatedBlueLayers extends StatelessWidget {
  const _AnimatedBlueLayers({required this.progress, required this.layers});

  final double progress;
  final List<String> layers;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0).toDouble();
    if (layers.length < 3) {
      return Transform.scale(
        scale: p,
        child: Opacity(
          opacity: p,
          child: SvgPicture.asset(
            'assets/images/app_icon.svg',
            width: 122,
            height: 122,
            placeholderBuilder: (context) => const SizedBox.shrink(),
          ),
        ),
      );
    }
    return SizedBox(
      width: 122,
      height: 122,
      child: Stack(
        alignment: Alignment.center,
        children: layers
            .map(
              (svg) => Transform.scale(
                scale: p,
                child: Opacity(
                  opacity: p,
                  child: SvgPicture.string(svg, width: 122, height: 122),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

