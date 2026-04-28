import 'dart:math' as math;

import 'package:mobile_sdk/mobile_sdk.dart';

class BleReconnectPolicy implements ReconnectPolicy {
  const BleReconnectPolicy({
    this.maxDelay = const Duration(seconds: 10),
  });

  final Duration maxDelay;

  @override
  Future<Duration?> nextDelay({
    required TransportKind transport,
    required int attempt,
    Object? lastError,
  }) async {
    if (transport != TransportKind.ble) {
      return null;
    }

    final normalizedAttempt = attempt < 1 ? 1 : attempt;
    final seconds = math.min(1 << (normalizedAttempt - 1), maxDelay.inSeconds);
    return Duration(seconds: seconds);
  }
}
