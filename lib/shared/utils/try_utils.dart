T? tryOrLog<T>(T Function() action, {String? label, T? fallback}) {
  try {
    return action();
  } catch (_) {
    return fallback;
  }
}

Future<T?> tryOrLogAsync<T>(Future<T> Function() action, {String? label, T? fallback}) async {
  try {
    return await action();
  } catch (_) {
    return fallback;
  }
}

void tryDo(void Function() action, {String? label}) {
  try {
    action();
  } catch (_) {}
}

Future<void> tryDoAsync(Future<void> Function() action, {String? label}) async {
  try {
    await action();
  } catch (_) {}
}
