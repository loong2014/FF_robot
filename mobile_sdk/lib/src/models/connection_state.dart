enum TransportKind { none, ble, tcp, mqtt }

enum ConnectionStatus { idle, connecting, connected, reconnecting, failed }

const String connectionErrorBleFailed = 'bleFailed';
const String connectionErrorTcpFailed = 'tcpFailed';
const String connectionErrorMqttFailed = 'mqttFailed';
const String connectionErrorUnsupportedTransport = 'unsupportedTransport';
const String connectionErrorMissingOptions = 'missingOptions';
const String connectionErrorDisconnectedByPeer = 'disconnectedByPeer';

class RobotConnectionState {
  const RobotConnectionState({
    required this.transport,
    required this.status,
    required this.updatedAt,
    this.errorCode,
    this.errorMessage,
  });

  factory RobotConnectionState.idle({DateTime? at}) {
    return RobotConnectionState(
      transport: TransportKind.none,
      status: ConnectionStatus.idle,
      updatedAt: at ?? DateTime.now(),
    );
  }

  final TransportKind transport;
  final ConnectionStatus status;
  final DateTime updatedAt;
  final String? errorCode;
  final String? errorMessage;

  RobotConnectionState copyWith({
    TransportKind? transport,
    ConnectionStatus? status,
    DateTime? updatedAt,
    String? errorCode,
    String? errorMessage,
    bool clearError = false,
  }) {
    return RobotConnectionState(
      transport: transport ?? this.transport,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is RobotConnectionState &&
        other.transport == transport &&
        other.status == status &&
        other.updatedAt == updatedAt &&
        other.errorCode == errorCode &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode => Object.hash(
    transport,
    status,
    updatedAt,
    errorCode,
    errorMessage,
  );
}
