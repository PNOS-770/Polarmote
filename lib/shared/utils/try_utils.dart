import '../logging/Polarmote_log.dart';

T? tryOrLog<T>(T Function() action, {String? label, T? fallback}) {
  try {
    return action();
  } catch (e, s) {
    PolarmoteLog.error(label ?? 'operation', '$e\n$s');
    return fallback;
  }
}

Future<T?> tryOrLogAsync<T>(Future<T> Function() action, {String? label, T? fallback}) async {
  try {
    return await action();
  } catch (e, s) {
    PolarmoteLog.error(label ?? 'operation', '$e\n$s');
    return fallback;
  }
}

void tryDo(void Function() action, {String? label}) {
  try {
    action();
  } catch (e, s) {
    PolarmoteLog.error(label ?? 'operation', '$e\n$s');
  }
}

Future<void> tryDoAsync(Future<void> Function() action, {String? label}) async {
  try {
    await action();
  } catch (e, s) {
    PolarmoteLog.error(label ?? 'operation', '$e\n$s');
  }
}

