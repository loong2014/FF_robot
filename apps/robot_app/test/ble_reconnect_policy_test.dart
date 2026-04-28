import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_sdk/mobile_sdk.dart';
import 'package:robot_app/src/ble_reconnect_policy.dart';

void main() {
  test('BleReconnectPolicy only retries BLE with exponential backoff',
      () async {
    const policy = BleReconnectPolicy();

    expect(
      await policy.nextDelay(transport: TransportKind.tcp, attempt: 1),
      isNull,
    );
    expect(
      await policy.nextDelay(transport: TransportKind.ble, attempt: 1),
      const Duration(seconds: 1),
    );
    expect(
      await policy.nextDelay(transport: TransportKind.ble, attempt: 2),
      const Duration(seconds: 2),
    );
    expect(
      await policy.nextDelay(transport: TransportKind.ble, attempt: 5),
      const Duration(seconds: 10),
    );
  });
}
