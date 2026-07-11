import 'package:asmote/features/terminal/models/port_forward_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PortForwardEntry json round-trip keeps values', () {
    final createdAt = DateTime.utc(2026, 2, 21, 10, 30);
    final entry = PortForwardEntry(
      id: 'fwd-1',
      name: 'Local API',
      hostId: 'host-1',
      localHost: '127.0.0.1',
      localPort: 8080,
      remoteHost: '10.0.0.5',
      remotePort: 80,
      createdAt: createdAt,
      autoStart: true,
      type: PortForwardType.reverse,
    );

    final decoded = PortForwardEntry.fromJson(entry.toJson());
    expect(decoded.id, entry.id);
    expect(decoded.name, entry.name);
    expect(decoded.hostId, entry.hostId);
    expect(decoded.localHost, entry.localHost);
    expect(decoded.localPort, entry.localPort);
    expect(decoded.remoteHost, entry.remoteHost);
    expect(decoded.remotePort, entry.remotePort);
    expect(decoded.createdAt.toIso8601String(), createdAt.toIso8601String());
    expect(decoded.autoStart, isTrue);
    expect(decoded.type, PortForwardType.reverse);
  });

  test('PortForwardEntry.fromJson parses legacy values safely', () {
    final before = DateTime.now();
    final entry = PortForwardEntry.fromJson({
      'id': 'fwd-legacy',
      'name': 'Legacy',
      'hostId': 'host-legacy',
      'localPort': '7000',
      'remoteHost': '127.0.0.1',
      'remotePort': 'bad-port',
      'createdAt': 'bad-time',
      'autoStart': 'true',
    });
    final after = DateTime.now();

    expect(entry.localHost, '127.0.0.1');
    expect(entry.localPort, 7000);
    expect(entry.remotePort, 0);
    expect(entry.autoStart, isFalse);
    expect(entry.type, PortForwardType.local);
    expect(entry.createdAt.isBefore(before), isFalse);
    expect(entry.createdAt.isAfter(after), isFalse);
  });

  test('PortForwardTemplate json round-trip keeps values', () {
    final createdAt = DateTime.utc(2026, 2, 21, 10, 30);
    final updatedAt = DateTime.utc(2026, 2, 21, 11, 30);
    final template = PortForwardTemplate(
      id: 'tpl-1',
      name: 'Reverse service',
      type: PortForwardType.reverse,
      localHost: '127.0.0.1',
      localPort: 8080,
      remoteHost: '0.0.0.0',
      remotePort: 18080,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    final decoded = PortForwardTemplate.fromJson(template.toJson());
    expect(decoded.id, template.id);
    expect(decoded.name, template.name);
    expect(decoded.type, PortForwardType.reverse);
    expect(decoded.localHost, template.localHost);
    expect(decoded.localPort, template.localPort);
    expect(decoded.remoteHost, template.remoteHost);
    expect(decoded.remotePort, template.remotePort);
    expect(decoded.createdAt.toIso8601String(), createdAt.toIso8601String());
    expect(decoded.updatedAt.toIso8601String(), updatedAt.toIso8601String());
  });
}
