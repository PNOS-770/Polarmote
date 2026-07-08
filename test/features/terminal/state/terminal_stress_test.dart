import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Polarmote/features/terminal/state/terminal_app_state.dart';


/// 创建一个干净的 TerminalAppState，关闭自动保存
Future<TerminalAppState> _newCleanState() async {
  final state = TerminalAppState();
  state.suspendStateSave = true;
  await Future<void>.delayed(const Duration(milliseconds: 220));
  state.hosts.clear();
  state.scripts.clear();
  state.scriptSchedules.clear();
  state.scriptRunHistory.clear();
  state.portForwards.clear();
  state.commandHistoryByHost.clear();
  return state;
}

/// 注册一张测试背景图（使用临时文件）
Future<String> _registerTestBgImage(TerminalAppState state, String id) async {
  final tmpDir = await Directory.systemTemp.createTemp('bg-test');
  final file = File('${tmpDir.path}/bg_$id.png');
  await file.writeAsBytes([0x89, 0x50, 0x4E, 0x47]); // minimal PNG header
  await state.addBackgroundImage(file.path);
  addTearDown(() => tmpDir.delete(recursive: true));
  return file.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Stage 切换极限', () {
    const stageCount = 20;
    const switchCount = 200;

    late TerminalAppState appState;
    late List<String> stageIds;

    setUp(() async {
      appState = await _newCleanState();
      addTearDown(appState.dispose);
      stageIds = [];

      // 创建 20 个 stage
      for (var i = 1; i <= stageCount; i++) {
        appState.createTerminalStage('Stage $i');
        stageIds.add(appState.activeTerminalStageId);
      }
    });

    test('快速切换 $switchCount 次不崩溃', () async {
      final stopwatch = Stopwatch()..start();

      for (var i = 0; i < switchCount; i++) {
        final targetId = stageIds[i % stageCount];
        appState.switchTerminalStage(targetId);
        // 每次切换后验证 activeStageId 正确
        expect(appState.activeTerminalStageId, equals(targetId));
        // 模拟 UI 帧间隔
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      stopwatch.stop();
      final avg = stopwatch.elapsedMilliseconds / switchCount;
      // 每次切换应 < 20ms
      expect(avg, lessThan(20.0),
          reason: '平均切换耗时 ${avg.toStringAsFixed(2)}ms，超过 20ms');
    });

    test('切换后 backgroundImageId 隔离', () async {
      // 为每个 stage 设置唯一背景
      for (var i = 0; i < stageCount; i++) {
        appState.switchTerminalStage(stageIds[i]);
        appState.setStageBackgroundImage(stageIds[i], 'bg-test-$i');
      }

      // 验证每个 stage 的背景独立
      for (var i = 0; i < stageCount; i++) {
        appState.switchTerminalStage(stageIds[i]);
        final stage = appState.terminalStages.firstWhere(
          (s) => s.id == stageIds[i],
        );
        expect(stage.backgroundImageId, equals('bg-test-$i'),
            reason: 'Stage $i 的背景应该是 bg-test-$i');
      }
    });
  });

  group('Stage 创建/删除风暴', () {
    late TerminalAppState appState;

    setUp(() async {
      appState = await _newCleanState();
      addTearDown(appState.dispose);
    });

    test('创建 100 个 stage 再全部删除', () async {
      final ids = <String>[];

      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        appState.createTerminalStage('Bulk $i');
        ids.add(appState.activeTerminalStageId);
      }
      stopwatch.stop();
      final createAvg = stopwatch.elapsedMilliseconds / 100;
      expect(createAvg, lessThan(5.0),
          reason: '创建平均耗时 ${createAvg.toStringAsFixed(2)}ms，超过 5ms');

      expect(appState.terminalStages.length, equals(101)); // 1 initial + 100

      stopwatch
        ..reset()
        ..start();
      for (final id in ids) {
        appState.removeStageById(id);
      }
      stopwatch.stop();
      final removeAvg = stopwatch.elapsedMilliseconds / 100;
      expect(removeAvg, lessThan(5.0),
          reason: '删除平均耗时 ${removeAvg.toStringAsFixed(2)}ms，超过 5ms');

      expect(appState.terminalStages.length, equals(1));
    });
  });

  group('背景图隔离', () {
    late TerminalAppState appState;
    late String stageA;
    late String stageB;

    setUp(() async {
      appState = await _newCleanState();
      addTearDown(appState.dispose);

      appState.createTerminalStage('A');
      stageA = appState.activeTerminalStageId;
      appState.createTerminalStage('B');
      stageB = appState.activeTerminalStageId;
    });

    test('Stage A 设置背景不影响 Stage B', () async {
      // 注册测试背景
      final bgPath = await _registerTestBgImage(appState, 'test');
      final bgId = appState.terminalBackgroundImages.last.id;

      // 在 Stage A 上设置背景
      appState.setStageBackgroundImage(stageA, bgId);

      // 切换到 Stage B，验证没有背景
      appState.switchTerminalStage(stageB);
      final stageBbg = appState.backgroundImagePathForActiveStage();
      expect(stageBbg, isNull, reason: 'Stage B 应该没有背景');

      // 切回 Stage A，验证背景还在
      appState.switchTerminalStage(stageA);
      final stageAbg = appState.backgroundImagePathForActiveStage();
      expect(stageAbg, isNotNull, reason: 'Stage A 应该仍有背景');
      expect(stageAbg, equals(bgPath));
    });

    test('删除背景图不影响其他 stage', () async {
      final bgPathA = await _registerTestBgImage(appState, 'A');
      final bgIdA = appState.terminalBackgroundImages.last.id;
      final bgPathB = await _registerTestBgImage(appState, 'B');
      final bgIdB = appState.terminalBackgroundImages.last.id;

      appState.setStageBackgroundImage(stageA, bgIdA);
      appState.setStageBackgroundImage(stageB, bgIdB);

      // 删除背景 A
      appState.removeBackgroundImage(bgIdA);

      // Stage A 的背景应自动清除
      appState.switchTerminalStage(stageA);
      expect(
        appState.backgroundImagePathForActiveStage(),
        isNull,
        reason: 'Stage A 的背景图被删除后应返回 null',
      );

      // Stage B 的背景不受影响
      appState.switchTerminalStage(stageB);
      expect(
        appState.backgroundImagePathForActiveStage(),
        equals(bgPathB),
        reason: 'Stage B 的背景不应被连带删除',
      );
    });
  });

  group('长时间运行稳定性', () {
    late TerminalAppState appState;

    setUp(() async {
      appState = await _newCleanState();
      addTearDown(appState.dispose);
    });

    test('频繁创建/删除 stage 后无泄漏', () {
      final initialStageCount = appState.terminalStages.length;

      for (var cycle = 0; cycle < 50; cycle++) {
        appState.createTerminalStage('Cycle $cycle');
        final id = appState.activeTerminalStageId;
        appState.removeStageById(id);
      }

      expect(appState.terminalStages.length, equals(initialStageCount));
    });
  });

  group('多 Stage 并发操作', () {
    late TerminalAppState appState;

    setUp(() async {
      appState = await _newCleanState();
      addTearDown(appState.dispose);
    });

    test('10 个 stage 同时设置背景后快速切换', () async {
      // 注册多个背景图
      final bgIds = <String>[];
      for (var i = 0; i < 10; i++) {
        await _registerTestBgImage(appState, '$i');
        bgIds.add(appState.terminalBackgroundImages.last.id);
      }

      // 创建 10 个 stage 并各设不同背景
      final stageIds = <String>[];
      for (var i = 0; i < 10; i++) {
        appState.createTerminalStage('Concurrent $i');
        stageIds.add(appState.activeTerminalStageId);
        appState.setStageBackgroundImage(stageIds.last, bgIds[i]);
      }

      // 快速遍历切换，验证背景正确
      for (var round = 0; round < 5; round++) {
        for (var i = 0; i < stageIds.length; i++) {
          appState.switchTerminalStage(stageIds[i]);
          final bg = appState.backgroundImagePathForActiveStage();
          if (bgIds[i].isNotEmpty) {
            expect(bg, isNotNull,
                reason: 'Stage $i 应该有背景 (round $round)');
          }
        }
      }
    });
  });
}
