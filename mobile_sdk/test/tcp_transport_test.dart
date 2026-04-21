import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_sdk/mobile_sdk.dart';

void main() {
  group('TcpTransport', () {
    late ServerSocket server;
    final connectedSockets = <Socket>[];
    final receivedChunks = <List<int>>[];

    Future<void> startServer({void Function(Socket socket)? onConnect}) async {
      connectedSockets.clear();
      receivedChunks.clear();
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((socket) {
        connectedSockets.add(socket);
        socket.listen(
          (data) => receivedChunks.add(data),
          onError: (_) {},
          onDone: () {},
        );
        onConnect?.call(socket);
      });
    }

    tearDown(() async {
      for (final socket in connectedSockets) {
        try {
          await socket.close();
          socket.destroy();
        } catch (_) {}
      }
      connectedSockets.clear();
      await server.close();
    });

    test('connect, send, decode ACK frame and disconnect cleanly', () async {
      await startServer(
        onConnect: (socket) {
          socket.add(encodeFrame(buildAckFrame(7)));
        },
      );

      final transport = TcpTransport(
        TcpConnectionOptions(host: server.address.address, port: server.port),
      );
      final frames = <RobotFrame>[];
      final subscription = transport.frames.listen(frames.add);

      await transport.connect();
      expect(transport.isConnected, isTrue);

      await transport.send(
        encodeFrame(buildCommandFrame(
          const DiscreteCommand(CommandId.stand),
          7,
        )),
      );

      await _eventually(() => frames.isNotEmpty && receivedChunks.isNotEmpty);
      expect(frames.first.type, FrameType.ack);
      expect(parseAckPayload(frames.first.payload), 7);

      await transport.disconnect();
      expect(transport.isConnected, isFalse);

      await subscription.cancel();
    });

    test('remote close propagates error on frames stream', () async {
      await startServer();

      final transport = TcpTransport(
        TcpConnectionOptions(host: server.address.address, port: server.port),
      );
      final errors = <Object>[];
      final subscription = transport.frames.listen(
        (_) {},
        onError: errors.add,
      );

      await transport.connect();
      expect(transport.isConnected, isTrue);

      while (connectedSockets.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await connectedSockets.first.close();
      connectedSockets.first.destroy();

      await _eventually(() => errors.isNotEmpty || !transport.isConnected);
      expect(transport.isConnected, isFalse);
      expect(errors, isNotEmpty);
      expect(errors.first, isA<SocketException>());

      await transport.disconnect();
      await subscription.cancel();
    });

    test('send while disconnected throws SocketException', () async {
      final transport = TcpTransport(
        const TcpConnectionOptions(host: '127.0.0.1', port: 1),
      );

      expect(
        () => transport.send(Uint8List.fromList(<int>[0x01])),
        throwsA(isA<SocketException>()),
      );
    });

    test('connect failure surfaces through Future', () async {
      final transport = TcpTransport(
        const TcpConnectionOptions(
          host: '127.0.0.1',
          port: 1,
          connectTimeout: Duration(milliseconds: 50),
        ),
      );

      await expectLater(transport.connect(), throwsA(isA<SocketException>()));
      expect(transport.isConnected, isFalse);
    });
  });
}

Future<void> _eventually(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
  Duration step = const Duration(milliseconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('condition not met within $timeout');
    }
    await Future<void>.delayed(step);
  }
}
