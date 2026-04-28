import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_sdk/mobile_sdk.dart';
import 'package:robot_app/src/ble_scan_page.dart';

class _FakeScanRobotClient extends RobotClient {
  _FakeScanRobotClient(this._scanStream);

  final Stream<BleDiscoveredDevice> _scanStream;

  @override
  Stream<BleDiscoveredDevice> scanBLE({
    Duration timeout = const Duration(seconds: 10),
    Set<String>? withServices,
  }) {
    return _scanStream;
  }
}

void main() {
  testWidgets('BleScanPage only shows devices whose names start with Robot', (
    WidgetTester tester,
  ) async {
    final controller = StreamController<BleDiscoveredDevice>.broadcast();
    addTearDown(controller.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BleScanPage(client: _FakeScanRobotClient(controller.stream)),
      ),
    );

    controller
      ..add(const BleDiscoveredDevice(id: '1', name: 'RobotDog-1', rssi: -40))
      ..add(const BleDiscoveredDevice(id: '2', name: 'Phone', rssi: -20))
      ..add(const BleDiscoveredDevice(id: '3', name: 'RobotMini', rssi: -60));
    await tester.pump();

    expect(find.text('RobotDog-1'), findsOneWidget);
    expect(find.text('RobotMini'), findsOneWidget);
    expect(find.text('Phone'), findsNothing);
    expect(find.textContaining('仅展示名称以 Robot 开头'), findsOneWidget);
  });
}
