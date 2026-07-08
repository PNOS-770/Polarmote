class CronExpression {
  const CronExpression._();

  static bool isValid(String expression) {
    final parts = expression
        .trim()
        .split(RegExp(r'\s+'))
        .where((item) => item.isNotEmpty)
        .toList();
    return parts.length == 5;
  }

  static bool matches(String expression, DateTime value) {
    final parts = expression
        .trim()
        .split(RegExp(r'\s+'))
        .where((item) => item.isNotEmpty)
        .toList();
    if (parts.length != 5) return false;
    final weekday = value.weekday % 7;
    return _fieldMatches(parts[0], value.minute, 0, 59) &&
        _fieldMatches(parts[1], value.hour, 0, 23) &&
        _fieldMatches(parts[2], value.day, 1, 31) &&
        _fieldMatches(parts[3], value.month, 1, 12) &&
        _fieldMatches(parts[4], weekday, 0, 7, allowSevenAsZero: true);
  }

  static bool _fieldMatches(
    String field,
    int value,
    int min,
    int max, {
    bool allowSevenAsZero = false,
  }) {
    final tokens = field.split(',');
    for (final raw in tokens) {
      final token = raw.trim();
      if (token.isEmpty) continue;
      if (_tokenMatches(token, value, min, max,
          allowSevenAsZero: allowSevenAsZero)) {
        return true;
      }
    }
    return false;
  }

  static bool _tokenMatches(
    String token,
    int value,
    int min,
    int max, {
    bool allowSevenAsZero = false,
  }) {
    if (token == '*') return true;
    var rangePart = token;
    var step = 1;
    if (token.contains('/')) {
      final segments = token.split('/');
      if (segments.length != 2) return false;
      rangePart = segments[0];
      step = int.tryParse(segments[1]) ?? 0;
      if (step <= 0) return false;
    }
    int start;
    int end;
    if (rangePart == '*' || rangePart.isEmpty) {
      start = min;
      end = max;
    } else if (rangePart.contains('-')) {
      final seg = rangePart.split('-');
      if (seg.length != 2) return false;
      final left = int.tryParse(seg[0]);
      final right = int.tryParse(seg[1]);
      if (left == null || right == null) return false;
      start = left;
      end = right;
    } else {
      final parsed = int.tryParse(rangePart);
      if (parsed == null) return false;
      start = parsed;
      end = parsed;
    }
    if (allowSevenAsZero && start == 7) start = 0;
    if (allowSevenAsZero && end == 7) end = 0;
    if (start < min || start > max || end < min || end > max) return false;
    if (start == end) return value == start;
    if (end < start) return false;
    if (value < start || value > end) return false;
    return ((value - start) % step) == 0;
  }

  static List<DateTime> momentsInRange({
    required String expression,
    required DateTime startExclusiveUtc,
    required DateTime endInclusiveUtc,
    required int timezoneOffsetMinutes,
    int maxCount = 64,
  }) {
    if (!endInclusiveUtc.isAfter(startExclusiveUtc)) return const [];
    if (!isValid(expression)) return const [];
    final result = <DateTime>[];
    final offset = Duration(minutes: timezoneOffsetMinutes);
    final startLocal = startExclusiveUtc.toUtc().add(offset);
    final endLocal = endInclusiveUtc.toUtc().add(offset);
    var cursor = _minuteBucket(startLocal);
    if (!cursor.isAfter(startLocal)) {
      cursor = cursor.add(const Duration(minutes: 1));
    }
    final endBucket = _minuteBucket(endLocal);
    while (!cursor.isAfter(endBucket)) {
      if (matches(expression, cursor)) {
        result.add(cursor.subtract(offset).toUtc());
        if (result.length >= maxCount) break;
      }
      cursor = cursor.add(const Duration(minutes: 1));
    }
    return result;
  }

  static DateTime minuteBucket(DateTime value) => _minuteBucket(value);

  static DateTime _minuteBucket(DateTime value) {
    return value.isUtc
        ? DateTime.utc(value.year, value.month, value.day, value.hour,
            value.minute)
        : DateTime(
            value.year, value.month, value.day, value.hour, value.minute);
  }
}

