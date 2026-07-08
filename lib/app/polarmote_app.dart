// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:safe_layout_x/safe_layout_x.dart';

import 'mobile_startup_gate.dart';
import 'system_tray_manager.dart';
import '../features/terminal/debug/stress_test_server.dart';
import '../features/terminal/presentation/terminal_home_page.dart';
import '../features/terminal/state/terminal_app_state.dart';
import '../providers/host_book_provider.dart';
import '../providers/script_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/transfer_provider.dart';
import '../shared/constants/app_string.dart';
import '../shared/design_system/components/notifications/shimmer_banner.dart';

class PolarmoteAppBootstrap extends StatelessWidget {
  const PolarmoteAppBootstrap({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<TerminalAppState>(
          create: (_) {
            final state = TerminalAppState();
            PolarmoteSystemTray.addShutdownHook(() => state.dispose());
            return state;
          },
        ),
        ChangeNotifierProvider<SessionProvider>(
          create: (context) {
            final appState = context.read<TerminalAppState>();
            return SessionProvider(
              appState: appState,
              eventBus: appState.eventBus,
            );
          },
        ),
        ChangeNotifierProvider<HostBookProvider>(
          create: (context) {
            final appState = context.read<TerminalAppState>();
            return HostBookProvider(
              appState: appState,
              eventBus: appState.eventBus,
            );
          },
        ),
        ChangeNotifierProvider<TransferProvider>(
          create: (context) {
            final appState = context.read<TerminalAppState>();
            return TransferProvider(
              appState: appState,
              eventBus: appState.eventBus,
            );
          },
        ),
        ChangeNotifierProvider<ScriptProvider>(
          create: (context) {
            final appState = context.read<TerminalAppState>();
            return ScriptProvider(appState: appState);
          },
        ),
        ChangeNotifierProvider<SettingsProvider>(
          create: (context) {
            final appState = context.read<TerminalAppState>();
            return SettingsProvider(appState: appState);
          },
        ),
      ],
      child: const PolarmoteApp(),
    );
  }
}

class PolarmoteApp extends StatefulWidget {
  const PolarmoteApp({super.key});

  @override
  State<PolarmoteApp> createState() => _PolarmoteAppState();
}

class _PolarmoteAppState extends State<PolarmoteApp> with WidgetsBindingObserver {
  static const MethodChannel _runtimeRecoveryChannel = MethodChannel(
    'Polarmote/runtime_recovery',
  );
  DateTime? _lastBackPress;
  StressTestServer? _stressServer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _runtimeRecoveryChannel.setMethodCallHandler(_handleRuntimeRecoveryCall);
    _startStressServer();
  }

  void _startStressServer() {
    if (!kDebugMode) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final appState = context.read<TerminalAppState>();
      _stressServer = StressTestServer(appState);
      unawaited(_stressServer!.start());
    });
  }

  @override
  void dispose() {
    _runtimeRecoveryChannel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    _stressServer?.stop();
    super.dispose();
  }

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
          title: AppStrings.values.PolarmoteTerminal.resolve(
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

