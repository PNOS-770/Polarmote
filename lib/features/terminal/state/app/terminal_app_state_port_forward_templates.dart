part of 'terminal_app_state_port_forward.dart';

extension TerminalAppStatePFTemplates on TerminalAppState {
  void upsertPortForwardTemplate(PortForwardTemplate template) {
    final index = portForwardTemplates.indexWhere((it) => it.id == template.id);
    final normalized = template.copyWith(updatedAt: DateTime.now());
    if (index >= 0) {
      portForwardTemplates[index] = normalized;
    } else {
      portForwardTemplates.add(normalized);
    }
    scheduleStateSave();
    notifyState();
  }

  void removePortForwardTemplate(String templateId) {
    final id = templateId.trim();
    if (id.isEmpty) return;
    portForwardTemplates.removeWhere((item) => item.id == id);
    scheduleStateSave();
    notifyState();
  }

  PortForwardTemplate buildTemplateFromPortForwardEntry(PortForwardEntry entry, {String? name}) {
    final now = DateTime.now();
    return PortForwardTemplate(
      id: 'pft-${now.microsecondsSinceEpoch}',
      name: (name ?? entry.name).trim().isEmpty ? entry.id : (name ?? entry.name).trim(),
      type: entry.type, localHost: entry.localHost, localPort: entry.localPort,
      remoteHost: entry.remoteHost, remotePort: entry.remotePort,
      createdAt: now, updatedAt: now,
    );
  }
}

