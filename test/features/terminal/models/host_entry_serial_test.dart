import 'package:Polarmote/features/terminal/models/host_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HostEntry.fromJson parses serial settings', () {
    final entry = HostEntry.fromJson({
      'id': 'serial-1',
      'name': 'COM3',
      'host': 'COM3',
      'port': 0,
      'username': 'serial',
      'group': 'Lab',
      'authType': 'password',
      'connectionType': 'serial',
      'serialPortPath': 'COM3',
      'serialBaudRate': 115200,
      'serialDataBits': 8,
      'serialStopBits': 2,
      'serialParity': 'odd',
    });

    expect(entry.connectionType, ConnectionType.serial);
    expect(entry.isSerial, isTrue);
    expect(entry.serialPortPath, 'COM3');
    expect(entry.serialBaudRate, 115200);
    expect(entry.serialDataBits, 8);
    expect(entry.serialStopBits, 2);
    expect(entry.serialParity, SerialParity.odd);
  });

  test('HostEntry.fromJson applies serial defaults and clamps values', () {
    final entry = HostEntry.fromJson({
      'id': 'serial-2',
      'name': 'ttyUSB0',
      'host': 'ttyUSB0',
      'port': 0,
      'username': 'serial',
      'group': '',
      'authType': 'password',
      'connectionType': 'serial',
      'serialBaudRate': 100,
      'serialDataBits': 20,
      'serialStopBits': 7,
    });

    expect(entry.serialBaudRate, 1200);
    expect(entry.serialDataBits, 8);
    expect(entry.serialStopBits, 1);
    expect(entry.serialParity, SerialParity.none);
  });
}
