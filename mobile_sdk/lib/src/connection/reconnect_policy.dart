import '../models/connection_state.dart';

abstract class ReconnectPolicy {
  Future<Duration?> nextDelay({
    required TransportKind transport,
    required int attempt,
    Object? lastError,
  });
}

class NoReconnectPolicy implements ReconnectPolicy {
  const NoReconnectPolicy();

  @override
  Future<Duration?> nextDelay({
    required TransportKind transport,
    required int attempt,
    Object? lastError,
  }) async {
    return null;
  }
}
