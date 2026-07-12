import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';


import '../models/host_entry.dart';
import '../models/session_file_state.dart';
import '../models/terminal_session.dart';
import '../models/terminal_tab.dart';
import '../state/terminal_app_state.dart';

/// 内嵌 HTTP 压力测试服务器，仅在 debug 模式启动。
/// 监听 localhost:9876，通过 REST API 控制 App 行为。
class StressTestServer {
  StressTestServer(this._appState);

  final TerminalAppState _appState;
  HttpServer? _server;

  Future<void>? _marathonTask;
  DateTime? _marathonStartedAt;
  int _marathonDurationSec = 0;
  int _marathonStageCount = 0;

  /// 启动服务器
  Future<void> start({int port = 9876}) async {
    if (_server != null) return;
    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      port,
    );
    
    _server!.listen(_handleRequest);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  void _handleRequest(HttpRequest request) {
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.contentType = ContentType('application', 'json', charset: 'utf-8');

    try {
      _route(request);
    } catch (e, stack) {
      _sendJson(request.response, 500, {'error': '$e', 'stack': '$stack'});
    }
  }

  void _route(HttpRequest request) {
    final uri = request.uri;
    final path = uri.path;
    final method = request.method;

    if (method == 'GET' && path == '/stats') {
      _sendJson(request.response, 200, _buildStats());
      return;
    }

    if (method == 'POST' && path == '/stage/create') {
      _withBody(request, (body) {
        final count = body['count'] as int? ?? 1;
        final baseName = body['name'] as String? ?? 'Stress';
        final ids = <String>[];
        for (var i = 0; i < count; i++) {
          _appState.createTerminalStage('$baseName ${ids.length + 1}');
          ids.add(_appState.activeTerminalStageId);
        }
        _sendJson(request.response, 200, {'created': ids.length, 'ids': ids});
      });
      return;
    }

    if (method == 'POST' && path == '/stage/delete') {
      _withBody(request, (body) {
        final id = body['id'] as String?;
        if (id == 'all') {
          while (_appState.terminalStages.length > 1) {
            _appState.removeStageById(_appState.terminalStages.last.id);
          }
          _sendJson(request.response, 200, {'deleted': 'all'});
        } else if (id != null) {
          _appState.removeStageById(id);
          _sendJson(request.response, 200, {'deleted': id});
        } else {
          _sendJson(request.response, 400, {'error': 'missing id'});
        }
      });
      return;
    }

    if (method == 'POST' && path == '/stage/switch') {
      _withBody(request, (body) {
        final stages = _appState.terminalStages;
        if (stages.isEmpty) {
          _sendJson(request.response, 400, {'error': 'no stages'});
          return;
        }
        final index = body['index'] as int?;
        final id = body['id'] as String?;
        if (index != null && index >= 0 && index < stages.length) {
          _appState.switchTerminalStage(stages[index].id);
          _sendJson(request.response, 200, {'switchedTo': stages[index].id});
        } else if (id != null) {
          _appState.switchTerminalStage(id);
          _sendJson(request.response, 200, {'switchedTo': id});
        } else {
          _sendJson(request.response, 400, {'error': 'need index or id'});
        }
      });
      return;
    }

    if (method == 'POST' && path == '/stage/switch-storm') {
      _withBody(request, (body) {
        final count = body['count'] as int? ?? 100;
        final stages = _appState.terminalStages;
        if (stages.isEmpty) {
          _sendJson(request.response, 400, {'error': 'no stages'});
          return;
        }
        final stopwatch = Stopwatch()..start();
        for (var i = 0; i < count; i++) {
          _appState.switchTerminalStage(stages[i % stages.length].id);
        }
        stopwatch.stop();
        _sendJson(request.response, 200, {
          'switches': count,
          'totalMs': stopwatch.elapsedMilliseconds,
          'avgMs': stopwatch.elapsedMilliseconds / count,
        });
      });
      return;
    }

    if (method == 'POST' && path == '/stage/set-bg') {
      _withBody(request, (body) {
        final stages = _appState.terminalStages;
        final index = body['index'] as int?;
        final bgId = body['bgId'] as String? ?? '';
        if (index != null && index >= 0 && index < stages.length) {
          _appState.setStageBackgroundImage(stages[index].id, bgId);
          _sendJson(request.response, 200, {
            'stage': stages[index].id,
            'backgroundImageId': bgId,
          });
        } else {
          _sendJson(request.response, 400, {'error': 'need valid index'});
        }
      });
      return;
    }

    if (method == 'POST' && path == '/stage/storm') {
      _withBody(request, (body) async {
        final createCount = body['create'] as int? ?? 20;
        final switchCount = body['switch'] as int? ?? 200;
        final bgCount = body['bg'] as int? ?? 5;

        final bgIds = <String>[];
        for (var i = 0; i < bgCount; i++) {
          final tmpDir = await Directory.systemTemp.createTemp('stress-bg');
          final file = File('${tmpDir.path}/bg_$i.png');
          await file.writeAsBytes([0x89, 0x50, 0x4E, 0x47]);
          await _appState.addBackgroundImage(file.path);
          bgIds.add(_appState.terminalBackgroundImages.last.id);
          unawaited(tmpDir.delete(recursive: true));
        }

        final stopwatch = Stopwatch()..start();

        final stageIds = <String>[];
        for (var i = 0; i < createCount; i++) {
          _appState.createTerminalStage('Storm ${i + 1}');
          stageIds.add(_appState.activeTerminalStageId);
        }

        for (var i = 0; i < stageIds.length; i++) {
          _appState.setStageBackgroundImage(
            stageIds[i],
            bgIds[i % bgIds.length],
          );
        }

        for (var i = 0; i < switchCount; i++) {
          _appState.switchTerminalStage(stageIds[i % stageIds.length]);
        }

        stopwatch.stop();

        _sendJson(request.response, 200, {
          'stagesCreated': createCount,
          'totalStages': _appState.terminalStages.length,
          'switches': switchCount,
          'backgroundsSet': stageIds.length,
          'totalMs': stopwatch.elapsedMilliseconds,
          'avgMsPerOp':
              stopwatch.elapsedMilliseconds / (createCount + switchCount + stageIds.length),
        });
      });
      return;
    }

    if (method == 'POST' && path == '/session/create') {
      _withBody(request, (body) async {
        final count = body['count'] as int? ?? 1;
        final ids = <String>[];
        for (var i = 0; i < count; i++) {
          final host = HostEntry(
            id: 'sess-host-${DateTime.now().microsecondsSinceEpoch}',
            name: 'Synthetic ${ids.length + 1}',
            host: 'localhost',
            port: 22,
            username: 'test',
            group: 'Stress',
            authType: AuthType.password,
            connectionType: ConnectionType.local,
          );
          final sessionId = 'sess-${DateTime.now().microsecondsSinceEpoch}';
          final tab = TerminalTab(
            id: sessionId,
            title: host.name,
            status: TerminalStatus.connected,
          );
          final session = TerminalSession(
            id: sessionId,
            profile: host,
            tab: tab,
            fileState: SessionFileState(rootPath: '/'),
            transferQueue: [],
            maxLines: _appState.terminalBufferSize,
          );
          _appState.sessions.add(session);
          _appState.activeSessionIndexValue = _appState.sessions.length - 1;

          final stageIndex = _appState.terminalStages.indexWhere(
            (s) => s.id == _appState.activeTerminalStageId,
          );
          if (stageIndex >= 0) {
            final stage = _appState.terminalStages[stageIndex];
            if (!stage.sessionIds.contains(session.id)) {
              _appState.terminalStages[stageIndex] = stage.copyWith(
                sessionIds: [...stage.sessionIds, session.id],
              );
            }
          }
          ids.add(sessionId);
        }
        _appState.notifyState();
        _sendJson(request.response, 200, {'created': ids.length, 'ids': ids});
      });
      return;
    }

    if (method == 'POST' && path == '/session/write') {
      _withBody(request, (body) {
        final id = body['id'] as String?;
        final text = body['text'] as String? ?? 'data line\n';
        final idx = _appState.sessions.indexWhere((s) => s.id == id);
        if (idx < 0) {
          _sendJson(request.response, 404, {'error': 'session not found'});
          return;
        }
        _appState.sessions[idx].terminal.write(text);
        _sendJson(request.response, 200, {'written': text.length});
      });
      return;
    }

    if (method == 'POST' && path == '/session/write-all') {
      _withBody(request, (body) {
        final text = body['text'] as String? ?? 'data line\n';
        for (final session in _appState.sessions) {
          session.terminal.write(text);
        }
        _sendJson(request.response, 200, {'written': text.length * _appState.sessions.length});
      });
      return;
    }

    if (method == 'POST' && path == '/throttle/reset') {
      _withBody(request, (body) {
        final sessionId = body['sessionId'] as String?;
        if (sessionId == 'all') {
          var resetCount = 0;
          for (final session in _appState.sessions) {
            session.resetAdaptiveThrottle();
            resetCount++;
          }
          _sendJson(request.response, 200, {'reset': resetCount});
        } else if (sessionId != null) {
          final session = _appState.sessions.cast<TerminalSession?>().firstWhere(
            (s) => s?.id == sessionId,
            orElse: () => null,
          );
          if (session != null) {
            session.resetAdaptiveThrottle();
            _sendJson(request.response, 200, {'reset': sessionId});
          } else {
            _sendJson(request.response, 404, {'error': 'session not found'});
          }
        } else {
          _sendJson(request.response, 400, {'error': 'missing sessionId'});
        }
      });
      return;
    }

    if (method == 'POST' && path == '/stress/marathon') {
      _handleMarathon(request);
      return;
    }

    if (method == 'GET' && path == '/stress/marathon/status') {
      _sendJson(request.response, 200, {
        'running': _marathonTask != null,
        'startedAt': _marathonStartedAt?.toIso8601String(),
        'durationSec': _marathonDurationSec,
        'stageCount': _marathonStageCount,
      });
      return;
    }

    _sendJson(request.response, 404, {'error': 'not found', 'path': path});
  }

  void _handleMarathon(HttpRequest request) {
    _parseBody(request).then((body) {
      final stageCount = body['stages'] as int? ?? 20;
      final durationSec = body['duration'] as int? ?? 60;

      final availableHosts = _appState.hosts.toList();
      if (availableHosts.isEmpty) {
        _sendJson(request.response, 400, {'error': 'no hosts in address book'});
        return;
      }

      _marathonStageCount = stageCount;
      _marathonDurationSec = durationSec;
      _marathonStartedAt = DateTime.now();

      _sendJson(request.response, 200, {
        'status': 'started',
        'stages': stageCount,
        'durationSec': durationSec,
        'hosts': availableHosts.length,
      });

      _marathonTask = _runMarathon(stageCount, durationSec, availableHosts);
    }).catchError((Object e, StackTrace s) {
      _sendJsonSafe(request.response, 500, {'error': '$e', 'stack': '$s'});
    });
  }

  Future<void> _runMarathon(
    int stageCount,
    int durationSec,
    List<HostEntry> availableHosts,
  ) async {
    final rng = Random();
    final stageIds = <String>[];
    final marathonSessionIds = <String>[];
    Timer? timer;

    try {
      
      while (_appState.terminalStages.length > 1) {
        _appState.removeStageById(_appState.terminalStages.last.id);
      }
      _appState.notifyState();

      

      // 创建 stage 并连接 session
      for (var i = 0; i < stageCount; i++) {
        final host = availableHosts[rng.nextInt(availableHosts.length)];
        _appState.createTerminalStage('Marathon ${i + 1}');
        stageIds.add(_appState.activeTerminalStageId);

        // connectToHost 会自动绑定 session 到当前 stage
        await _appState.connectToHost(host, remember: false, background: false);
        if (_appState.sessions.isNotEmpty) {
          marathonSessionIds.add(_appState.sessions.last.id);
        }

        // 发送持续输出命令
        final session = _appState.sessions.lastOrNull;
        if (session != null) {
          final outputCmd = Platform.isWindows
              ? 'ping -t localhost\r\n'
              : 'while true; do date; sleep 0.2; done\n';
          try {
            session.sendInput(outputCmd);
          } catch (_) {}
        }

        // 让 UI 有时间渲染和清理旧的 scroll controller
        await Future.delayed(const Duration(milliseconds: 200));
      }

      final stopwatch = Stopwatch()..start();
      timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (stageIds.isEmpty) return;
        _appState.switchTerminalStage(stageIds[rng.nextInt(stageIds.length)]);
      });

      
      await Future<void>.delayed(Duration(seconds: durationSec));
      timer.cancel();
      stopwatch.stop();

      
    } catch (_) {
      
    } finally {
      timer?.cancel();
      _marathonTask = null;
      
      
      // 关闭 marathon 创建的 session
      for (final sid in marathonSessionIds) {
        await _appState.closeSession(sid);
      }
      
      
      // 删除 marathon 创建的 stage
      for (final id in stageIds) {
        _appState.removeStageById(id);
      }
      _appState.notifyState();
      
      
    }
  }

  Map<String, dynamic> _buildStats() {
    // 收集所有会话的自适应限流状态
    final sessionThrottleStats = _appState.sessions.map((session) {
      return {
        'id': session.id,
        'throttle': session.getAdaptiveThrottleDiagnostics(),
      };
    }).toList();
    
    return {
      'stages': _appState.terminalStages.map((s) => {
        'id': s.id,
        'name': s.name,
        'sessionCount': s.sessionIds.length,
        'backgroundImageId': s.backgroundImageId,
      }).toList(),
      'activeStageId': _appState.activeTerminalStageId,
      'sessions': _appState.sessions.length,
      'backgroundImages': _appState.terminalBackgroundImages.length,
      'sessionThrottleStats': sessionThrottleStats,
    };
  }

  void _withBody(HttpRequest request, void Function(Map<String, dynamic>) callback) {
    _parseBody(request).then((data) => callback(data));
  }

  Future<Map<String, dynamic>> _parseBody(HttpRequest request) async {
    final text = await utf8.decodeStream(request);
    if (text.trim().isEmpty) return <String, dynamic>{};
    return jsonDecode(text) as Map<String, dynamic>;
  }

  void _sendJson(HttpResponse response, int status, dynamic data) {
    response.statusCode = status;
    response.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    response.write(jsonEncode(data));
    response.close();
  }

  void _sendJsonSafe(HttpResponse response, int status, dynamic data) {
    try {
      _sendJson(response, status, data);
    } catch (_) {}
  }
}


