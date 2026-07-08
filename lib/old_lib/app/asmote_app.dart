// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:safe_layout_x/safe_layout_x.dart';

import 'mobile_startup_gate.dart';
import 'system_tray_manager.dart';
import '../features/terminal/presentation/terminal_home_page.dart';
import '../features/terminal/state/terminal_app_state.dart';
import '../shared/constants/app_string.dart';
import '../shared/design_system/components/notifications/shimmer_banner.dart';

class AsmoteAppBootstrap extends StatelessWidget {
  const AsmoteAppBootstrap({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final state = TerminalAppState();
        AsmoteSystemTray.addShutdownHook(() => state.dispose());
        return state;
      },
      child: const AsmoteApp(),
    );
  }
}

class AsmoteApp extends StatefulWidget {
  const AsmoteApp({super.key});

  @override
  State<AsmoteApp> createState() => _AsmoteAppState();
}

class _AsmoteAppState extends State<AsmoteApp> with WidgetsBindingObserver {
  static const MethodChannel _runtimeRecoveryChannel = MethodChannel(
    'asmote/runtime_recovery',
  );
  late final FocusManager _focusManager;
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    _focusManager = FocusManager.instance;
    _focusManager.addListener(_handleFocusChange);
    WidgetsBinding.instance.addObserver(this);
    _runtimeRecoveryChannel.setMethodCallHandler(_handleRuntimeRecoveryCall);
  }

  @override
  void dispose() {
    _runtimeRecoveryChannel.setMethodCallHandler(null);
    _focusManager.removeListener(_handleFocusChange);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleFocusChange() {}

  Future<void> _handleRuntimeRecoveryCall(MethodCall call) async {
    if (call.method != 'keyboardJsonParseError') {
      return;
    }
    if (!mounted) {
      return;
    }
    HardwareKeyboard.instance.clearState();
    final appState = context.read<TerminalAppState>();
    appState.triggerKeyboardRecovery(reason: 'json-message-empty');
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final appState = context.read<TerminalAppState>();
    if (state == AppLifecycleState.resumed) {
      appState.setAppForegroundForSshGuard(true);
      appState.syncTransferForegroundGuardNow();
      appState.syncSshForegroundGuardNow();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Start SSH foreground guard as early as possible before full background
      // restrictions are applied on newer Android versions.
      appState.setAppForegroundForSshGuard(false);
      appState.syncTransferForegroundGuardNow();
      appState.syncSshForegroundGuardNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TerminalAppState>(
      builder: (context, appState, child) {
        return MaterialApp(
          title: AppStrings.values.asmoteTerminal.resolve(
            appState.locale.languageCode,
          ),
          locale: appState.locale.languageCode == 'en'
              ? const Locale('en')
              : const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            final content = child ?? const SizedBox.shrink();
            return SafeLayoutTheme(
              data: const SafeLayoutThemeData(
                panelPadding: EdgeInsets.all(12),
                dockSpacing: 8,
                tooltipDelay: Duration(milliseconds: 500),
                minimumPanelSize: Size(240, 160),
              ),
              child: withBannerOverlay(
                context,
                content,
                bannerBuilder: (
                  BuildContext context,
                  BannerData data,
                  VoidCallback onDismiss,
                  double width,
                ) {
                  return ShimmerBannerWidget(
                    key: ValueKey(data.id),
                    data: data,
                    width: width,
                    onDismiss: onDismiss,
                  );
                },
              ),
            );
          },
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF6F6F6),
            fontFamily: 'Microsoft YaHei',
            useMaterial3: false,
          ),
          home: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              if (Platform.isAndroid || Platform.isIOS) {
                final now = DateTime.now();
                if (_lastBackPress != null &&
                    now.difference(_lastBackPress!) <
                        const Duration(seconds: 2)) {
                  SystemNavigator.pop();
                  return;
                }
                _lastBackPress = now;
                final appState =
                    context.read<TerminalAppState>();
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  SnackBar(
                    content: Text(
                      AppStrings.values.pressAgainToExit.resolve(
                        appState.locale.languageCode,
                      ),
                    ),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const MobileStartupGate(child: TerminalHomePage()),
          ),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
