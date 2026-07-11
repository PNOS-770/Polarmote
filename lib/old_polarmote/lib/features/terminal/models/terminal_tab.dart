enum TerminalStatus { connecting, connected, reconnecting, disconnected }

class TerminalTab {
  const TerminalTab({
    required this.id,
    required this.title,
    required this.status,
  });

  final String id;
  final String title;
  final TerminalStatus status;

  TerminalTab copyWith({String? title, TerminalStatus? status}) {
    return TerminalTab(
      id: id,
      title: title ?? this.title,
      status: status ?? this.status,
    );
  }
}
