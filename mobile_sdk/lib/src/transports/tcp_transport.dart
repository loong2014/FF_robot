import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:robot_protocol/robot_protocol.dart';

import '../models/connection_options.dart';
import 'transport.dart';

/// TCP implementation of [RobotTransport].
///
/// Behavior aligned with the BLE path used by [RobotClient]:
/// - Emits decoded [RobotFrame]s on [frames];
/// - Propagates peer close / socket errors as an error event on [frames]
///   so [RobotClient] can trigger its reconnect policy;
/// - [disconnect] is idempotent and fully releases the socket, the decoder
///   subscription and the frame controller that are owned by this instance.
class TcpTransport implements RobotTransport {
  TcpTransport(this.options, {SocketFactory? socketFactory})
    : _socketFactory = socketFactory ?? _defaultSocketFactory;

  final TcpConnectionOptions options;
  final SocketFactory _socketFactory;

  final StreamController<RobotFrame> _frames =
      StreamController<RobotFrame>.broadcast();
  final StreamFrameDecoder _decoder = StreamFrameDecoder();

  Socket? _socket;
  StreamSubscription<Uint8List>? _subscription;
  bool _isConnected = false;
  bool _disposed = false;

  @override
  Stream<RobotFrame> get frames => _frames.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect() async {
    if (_disposed) {
      throw StateError('TcpTransport has been disposed');
    }
    await disconnect();

    final socket = await _socketFactory(
      host: options.host,
      port: options.port,
      timeout: options.connectTimeout,
    );
    _socket = socket;
    _isConnected = true;
    _subscription = socket.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  @override
  Future<void> disconnect() async {
    final subscription = _subscription;
    final socket = _socket;
    _subscription = null;
    _socket = null;
    _isConnected = false;

    await subscription?.cancel();
    if (socket != null) {
      try {
        await socket.close();
      } catch (_) {
        // swallow close errors; the socket is going away anyway.
      }
      socket.destroy();
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await disconnect();
    if (!_frames.isClosed) {
      await _frames.close();
    }
  }

  @override
  Future<void> send(Uint8List bytes) async {
    final socket = _socket;
    if (socket == null || !_isConnected) {
      throw const SocketException('TCP transport is not connected');
    }
    socket.add(bytes);
    await socket.flush();
  }

  void _onData(Uint8List data) {
    if (_frames.isClosed) {
      return;
    }
    try {
      for (final frame in _decoder.feed(data)) {
        _frames.add(frame);
      }
    } catch (error, stackTrace) {
      _frames.addError(error, stackTrace);
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    _isConnected = false;
    if (!_frames.isClosed) {
      _frames.addError(error, stackTrace);
    }
  }

  void _onDone() {
    final wasConnected = _isConnected;
    _isConnected = false;
    _socket = null;
    if (wasConnected && !_frames.isClosed) {
      _frames.addError(
        const SocketException('TCP connection closed by peer'),
        StackTrace.current,
      );
    }
  }

  static Future<Socket> _defaultSocketFactory({
    required String host,
    required int port,
    required Duration timeout,
  }) {
    return Socket.connect(host, port, timeout: timeout);
  }
}

/// Injectable factory for unit tests. Production code uses
/// [Socket.connect] via the default implementation.
typedef SocketFactory =
    Future<Socket> Function({
      required String host,
      required int port,
      required Duration timeout,
    });
