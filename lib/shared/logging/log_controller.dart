import 'package:flutter/foundation.dart';

class LogController extends ChangeNotifier {
  static const int _maxLines = 500;

  final List<String> logs = [];

  void addLog(String message, {bool notify = true}) {
    final now = DateTime.now();
    final timestamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final line = '[$timestamp] $message';
    logs.add(line);
    while (logs.length > _maxLines) {
      logs.removeAt(0);
    }
    if (notify) notifyListeners();
  }

  List<String> get todayLogs {
    final now = DateTime.now();
    final prefix =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return logs.where((l) => l.startsWith('[$prefix')).toList();
  }

  @override
  void dispose() {
    logs.clear();
    super.dispose();
  }
}
