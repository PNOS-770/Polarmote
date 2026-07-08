import 'package:Polarmote/shared/utils/cron_expression.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CronExpression.isValid', () {
    test('accepts valid 5-field expression', () {
      expect(CronExpression.isValid('*/5 * * * *'), isTrue);
      expect(CronExpression.isValid('0 9 * * 1-5'), isTrue);
      expect(CronExpression.isValid('30 18 * * *'), isTrue);
    });

    test('rejects invalid expression', () {
      expect(CronExpression.isValid(''), isFalse);
      expect(CronExpression.isValid('* * * *'), isFalse);
      expect(CronExpression.isValid('* * * * * *'), isFalse);
      expect(CronExpression.isValid('not-a-cron'), isFalse);
    });
  });

  group('CronExpression.matches', () {
    test('* matches any time', () {
      final time = DateTime(2026, 6, 26, 15, 30);
      expect(CronExpression.matches('* * * * *', time), isTrue);
    });

    test('exact minute matches', () {
      final time = DateTime(2026, 6, 26, 15, 30);
      expect(CronExpression.matches('30 * * * *', time), isTrue);
      expect(CronExpression.matches('0 * * * *', time), isFalse);
    });

    test('hour range matches', () {
      final time = DateTime(2026, 6, 26, 15, 30);
      expect(CronExpression.matches('30 15 * * *', time), isTrue);
      expect(CronExpression.matches('30 14 * * *', time), isFalse);
    });

    test('weekday match (0=Sunday)', () {
      final sunday = DateTime(2026, 6, 28, 10, 0);
      expect(CronExpression.matches('0 10 * * 0', sunday), isTrue);
      expect(CronExpression.matches('0 10 * * 7', sunday), isTrue);
      expect(CronExpression.matches('0 10 * * 1', sunday), isFalse);
    });

    test('step interval matches', () {
      final time = DateTime(2026, 6, 26, 15, 30);
      expect(CronExpression.matches('*/15 * * * *', time), isTrue);
      final time2 = DateTime(2026, 6, 26, 15, 31);
      expect(CronExpression.matches('*/15 * * * *', time2), isFalse);
    });

    test('comma-separated values', () {
      final time = DateTime(2026, 6, 26, 15, 0);
      expect(CronExpression.matches('0,15,30,45 * * * *', time), isTrue);
      final time2 = DateTime(2026, 6, 26, 15, 7);
      expect(CronExpression.matches('0,15,30,45 * * * *', time2), isFalse);
    });
  });
}
