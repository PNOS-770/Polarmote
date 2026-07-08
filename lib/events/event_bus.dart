import 'dart:async';

abstract class AppEvent {
  const AppEvent();
}

class SessionConnectedEvent extends AppEvent {
  const SessionConnectedEvent({required this.sessionId});
  final String sessionId;
}

class SessionDisconnectedEvent extends AppEvent {
  const SessionDisconnectedEvent({required this.sessionId, this.error});
  final String sessionId;
  final String? error;
}

class TransferCompletedEvent extends AppEvent {
  const TransferCompletedEvent({required this.sessionId, required this.taskId});
  final String sessionId;
  final String taskId;
}

class TransferErrorEvent extends AppEvent {
  const TransferErrorEvent({
    required this.sessionId,
    required this.taskId,
    required this.error,
  });
  final String sessionId;
  final String taskId;
  final String error;
}

class HostListChangedEvent extends AppEvent {
  const HostListChangedEvent();
}

class EventBus {
  final StreamController<AppEvent> _controller = StreamController<AppEvent>.broadcast();

  Stream<T> on<T extends AppEvent>() {
    return _controller.stream.where((event) => event is T).cast<T>();
  }

  void fire(AppEvent event) {
    _controller.add(event);
  }

  StreamSubscription<T> listen<T extends AppEvent>(void Function(T event) handler) {
    return on<T>().listen(handler);
  }

  void dispose() {
    _controller.close();
  }
}

