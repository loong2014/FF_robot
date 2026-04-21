import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:robot_protocol/robot_protocol.dart';

import '../models/connection_options.dart';
import 'ble_discovered_device.dart';
import 'transport.dart';

enum BleConnectStage {
  gattConnect,
  discoverServices,
  subscribeState,
}

void _bleLog(String message) {
  if (kDebugMode) {
    debugPrint('[BleTransport] $message');
  }
}

class BleConnectException implements Exception {
  const BleConnectException({required this.stage, required this.cause});

  final BleConnectStage stage;
  final Object cause;

  String get stageLabel {
    switch (stage) {
      case BleConnectStage.gattConnect:
        return 'gatt_connect';
      case BleConnectStage.discoverServices:
        return 'discover_services';
      case BleConnectStage.subscribeState:
        return 'subscribe_state';
    }
  }

  @override
  String toString() => 'BLE connect failed at $stageLabel: $cause';
}

abstract class BleConnectionSession {
  Stream<bool> get connectionState;

  int get mtuNow;

  bool get isConnected;

  Future<void> connect({
    required Duration timeout,
    required BlePluginLicense pluginLicense,
  });

  Future<void> disconnect();

  Future<int?> requestMtu(int mtu);

  Future<void> discoverServices();

  Future<void> setNotifyValue({
    required String serviceUuid,
    required String characteristicUuid,
    required bool enabled,
  });

  Stream<List<int>> onCharacteristicValue({
    required String serviceUuid,
    required String characteristicUuid,
  });

  Future<void> write({
    required String serviceUuid,
    required String characteristicUuid,
    required List<int> value,
    required bool withoutResponse,
  });
}

abstract class BlePlatformAdapter {
  Stream<List<BleDiscoveredDevice>> get scanResults;

  Future<void> waitUntilReady();

  Future<void> startScan({
    required List<String> serviceUuids,
    required Duration timeout,
  });

  Future<void> stopScan();

  BleConnectionSession createSession(String deviceId);
}

class BleTransport implements RobotTransport {
  BleTransport(this.options, {BlePlatformAdapter? platform})
      : _platform = platform ?? FlutterBluePlusBlePlatformAdapter.instance;

  static const Duration _androidPreConnectScanStopDelay = Duration(
    milliseconds: 250,
  );

  final BleConnectionOptions options;
  final BlePlatformAdapter _platform;
  final StreamController<RobotFrame> _frames =
      StreamController<RobotFrame>.broadcast();
  final StreamFrameDecoder _decoder = StreamFrameDecoder();

  BleConnectionSession? _session;
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<List<int>>? _notifySubscription;
  bool _isConnected = false;

  @override
  Stream<RobotFrame> get frames => _frames.stream;

  @override
  bool get isConnected => _isConnected;

  static Stream<BleDiscoveredDevice> scan({
    Set<String>? withServices,
    Duration timeout = const Duration(seconds: 10),
    BlePlatformAdapter? platform,
  }) {
    final adapter = platform ?? FlutterBluePlusBlePlatformAdapter.instance;
    final controller = StreamController<BleDiscoveredDevice>();
    StreamSubscription<List<BleDiscoveredDevice>>? subscription;
    Timer? closeTimer;
    Timer? fallbackTimer;
    final seen = <String, BleDiscoveredDevice>{};
    final requestedServices = withServices?.toList() ?? <String>[];
    var usingUnfilteredFallback = false;
    var sawAnyDevice = false;
    var closed = false;

    Future<void> closeScan() async {
      if (closed) {
        return;
      }
      closed = true;
      fallbackTimer?.cancel();
      closeTimer?.cancel();
      await subscription?.cancel();
      await adapter.stopScan();
      _bleLog('scan stopped');
      await controller.close();
    }

    Duration fallbackDelayFor(Duration totalTimeout) {
      final totalMs = totalTimeout.inMilliseconds;
      if (totalMs <= 0) {
        return Duration.zero;
      }
      final fallbackMs = totalMs < 4000 ? totalMs ~/ 2 : 2000;
      return Duration(milliseconds: fallbackMs.clamp(1, totalMs).toInt());
    }

    Future<void> restartWithoutServiceFilter() async {
      if (closed ||
          usingUnfilteredFallback ||
          sawAnyDevice ||
          requestedServices.isEmpty) {
        return;
      }
      usingUnfilteredFallback = true;
      _bleLog(
        'service-filtered scan returned no results, retrying without service filter',
      );
      try {
        await adapter.stopScan();
        if (closed) {
          return;
        }
        await adapter.startScan(
          serviceUuids: const <String>[],
          timeout: timeout,
        );
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
        await closeScan();
      }
    }

    Future<void> startScan() async {
      try {
        await adapter.waitUntilReady();
        subscription = adapter.scanResults.listen(
          (devices) {
            for (final device in devices) {
              if (seen[device.id] == device) {
                continue;
              }
              seen[device.id] = device;
              sawAnyDevice = true;
              fallbackTimer?.cancel();
              _bleLog(
                'scan found device id=${device.id} name=${device.name} rssi=${device.rssi}',
              );
              controller.add(device);
            }
          },
          onError: controller.addError,
        );
        _bleLog(
          requestedServices.isEmpty
              ? 'scan started without service filter'
              : 'scan started with service filter: ${requestedServices.join(", ")}',
        );
        await adapter.startScan(
          serviceUuids: requestedServices,
          timeout: timeout,
        );
        if (requestedServices.isNotEmpty) {
          fallbackTimer = Timer(
            fallbackDelayFor(timeout),
            () => unawaited(restartWithoutServiceFilter()),
          );
        }
        closeTimer = Timer(timeout, () => unawaited(closeScan()));
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
        await closeScan();
      }
    }

    controller.onListen = () {
      unawaited(startScan());
    };
    controller.onCancel = closeScan;

    return controller.stream;
  }

  @override
  Future<void> connect() async {
    if (options.deviceId.isEmpty) {
      throw ArgumentError('BLE connect requires a non-empty deviceId');
    }

    await disconnect();

    try {
      _bleLog('ensuring scan is stopped before connect');
      await _platform.stopScan();
      if (defaultTargetPlatform == TargetPlatform.android) {
        await Future<void>.delayed(_androidPreConnectScanStopDelay);
      }
    } catch (_) {
      // Best effort only. Some adapters may already be idle.
    }

    final session = _platform.createSession(options.deviceId);
    _session = session;
    _connectionSubscription = session.connectionState.listen((connected) {
      _isConnected = connected;
      _bleLog('connection state update connected=$connected');
    });

    try {
      _bleLog('connecting to deviceId=${options.deviceId}');
      await session.connect(
        timeout: options.timeout,
        pluginLicense: options.pluginLicense,
      );
    } catch (error) {
      throw BleConnectException(
        stage: BleConnectStage.gattConnect,
        cause: error,
      );
    }
    _isConnected = session.isConnected;
    _bleLog('gatt connected, mtuNow=${session.mtuNow}');

    // Android 端常见问题：GATT 刚 connected 时若立即 requestMtu / discoverServices
    // 可能触发 LINK_SUPERVISION_TIMEOUT，特别是 BlueZ 外设。这里给协议层一点
    // 时间先完成 connection parameter update 再继续握手。
    if (options.postConnectSettleDelay > Duration.zero) {
      await Future<void>.delayed(options.postConnectSettleDelay);
    }

    if (!session.isConnected) {
      throw BleConnectException(
        stage: BleConnectStage.gattConnect,
        cause: StateError(
          'BLE link dropped right after connect (common LINK_SUPERVISION_TIMEOUT)',
        ),
      );
    }

    if (!kIsWeb && options.mtuRequest > 0) {
      try {
        await session.requestMtu(options.mtuRequest);
        _bleLog(
            'requested mtu=${options.mtuRequest}, negotiated=${session.mtuNow}');
      } catch (_) {
        // iOS/macOS will negotiate MTU automatically; some peripherals just
        // reject the request, which is fine — keep going with the default MTU.
      }
    }

    try {
      await session.discoverServices();
      _bleLog('services discovered');
    } catch (error) {
      throw BleConnectException(
        stage: BleConnectStage.discoverServices,
        cause: error,
      );
    }

    try {
      _notifySubscription = session
          .onCharacteristicValue(
        serviceUuid: options.serviceUuid,
        characteristicUuid: options.stateCharacteristicUuid,
      )
          .listen(
        (value) {
          for (final frame in _decoder.feed(value)) {
            _frames.add(frame);
          }
        },
        onError: _frames.addError,
      );
      await session.setNotifyValue(
        serviceUuid: options.serviceUuid,
        characteristicUuid: options.stateCharacteristicUuid,
        enabled: true,
      );
      _bleLog(
        'state notify enabled for ${options.serviceUuid}/${options.stateCharacteristicUuid}',
      );
    } catch (error) {
      throw BleConnectException(
        stage: BleConnectStage.subscribeState,
        cause: error,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    final session = _session;
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _isConnected = false;
    _session = null;
    if (session != null) {
      try {
        await session.setNotifyValue(
          serviceUuid: options.serviceUuid,
          characteristicUuid: options.stateCharacteristicUuid,
          enabled: false,
        );
      } catch (_) {
        // Ignore cleanup failures while disconnecting.
      }
      await session.disconnect();
    }
  }

  @override
  Future<void> send(Uint8List bytes) async {
    final session = _session;
    if (session == null || !session.isConnected) {
      throw StateError('BLE transport is not connected');
    }

    final chunkSize = _chunkSizeForMtu(session.mtuNow);
    _bleLog(
      'sending ${bytes.length} bytes via ${options.cmdCharacteristicUuid} in chunks of $chunkSize',
    );
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end =
          offset + chunkSize > bytes.length ? bytes.length : offset + chunkSize;
      await session.write(
        serviceUuid: options.serviceUuid,
        characteristicUuid: options.cmdCharacteristicUuid,
        value: bytes.sublist(offset, end),
        withoutResponse: true,
      );
    }
  }

  int _chunkSizeForMtu(int mtu) {
    final safeMtu = mtu <= 0 ? options.mtuRequest : mtu;
    return (safeMtu - 3).clamp(20, 512).toInt();
  }
}

class FlutterBluePlusBlePlatformAdapter implements BlePlatformAdapter {
  FlutterBluePlusBlePlatformAdapter._();

  static final FlutterBluePlusBlePlatformAdapter instance =
      FlutterBluePlusBlePlatformAdapter._();

  @override
  Stream<List<BleDiscoveredDevice>> get scanResults =>
      FlutterBluePlus.onScanResults.map(
        (results) => results
            .map(
              (result) => BleDiscoveredDevice(
                id: result.device.remoteId.toString(),
                name: _resolveDeviceName(result),
                rssi: result.rssi,
              ),
            )
            .toList(growable: false),
      );

  @override
  Future<void> waitUntilReady() async {
    var state = FlutterBluePlus.adapterStateNow;
    if (state == BluetoothAdapterState.unknown) {
      state = await FlutterBluePlus.adapterState.firstWhere(
        (value) => value != BluetoothAdapterState.unknown,
      );
    }

    switch (state) {
      case BluetoothAdapterState.on:
        return;
      case BluetoothAdapterState.unavailable:
        throw StateError('Bluetooth adapter unavailable on this device');
      case BluetoothAdapterState.unauthorized:
        throw StateError('Bluetooth permission not granted');
      case BluetoothAdapterState.off:
        if (defaultTargetPlatform == TargetPlatform.android) {
          _bleLog('bluetooth adapter is off, requesting turnOn()');
          try {
            await FlutterBluePlus.turnOn();
          } catch (error) {
            throw StateError(
              'Bluetooth is off and could not be enabled automatically: $error',
            );
          }
        }
        break;
      case BluetoothAdapterState.turningOn:
      case BluetoothAdapterState.turningOff:
      case BluetoothAdapterState.unknown:
        break;
    }

    await FlutterBluePlus.adapterState
        .where((value) => value == BluetoothAdapterState.on)
        .first
        .timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw TimeoutException(
          'Timed out waiting for Bluetooth adapter to turn on',
        );
      },
    );
  }

  @override
  Future<void> startScan({
    required List<String> serviceUuids,
    required Duration timeout,
  }) {
    final services = serviceUuids.map(Guid.new).toList(growable: false);
    return FlutterBluePlus.startScan(
      withServices: services,
      timeout: timeout,
    );
  }

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();

  @override
  BleConnectionSession createSession(String deviceId) {
    return _FlutterBluePlusConnectionSession(BluetoothDevice.fromId(deviceId));
  }

  static String _resolveDeviceName(ScanResult result) {
    final advName = result.advertisementData.advName.trim();
    if (advName.isNotEmpty) {
      return advName;
    }
    final platformName = result.device.platformName.trim();
    if (platformName.isNotEmpty) {
      return platformName;
    }
    return result.device.remoteId.toString();
  }
}

class _FlutterBluePlusConnectionSession implements BleConnectionSession {
  _FlutterBluePlusConnectionSession(this._device);

  final BluetoothDevice _device;
  final Map<String, BluetoothCharacteristic> _characteristics =
      <String, BluetoothCharacteristic>{};

  @override
  Stream<bool> get connectionState => _device.connectionState.map(
        (state) => state == BluetoothConnectionState.connected,
      );

  @override
  int get mtuNow => _device.mtuNow;

  @override
  bool get isConnected => _device.isConnected;

  @override
  Future<void> connect({
    required Duration timeout,
    required BlePluginLicense pluginLicense,
  }) {
    return _device.connect(
      license: pluginLicense == BlePluginLicense.commercial
          ? License.commercial
          : License.free,
      timeout: timeout,
      mtu: null,
    );
  }

  @override
  Future<void> disconnect() => _device.disconnect();

  @override
  Future<int?> requestMtu(int mtu) => _device.requestMtu(mtu);

  @override
  Future<void> discoverServices() async {
    final services = await _device.discoverServices();
    _characteristics.clear();
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        final key =
            '${service.uuid.toString().toLowerCase()}/${characteristic.uuid.toString().toLowerCase()}';
        _characteristics[key] = characteristic;
      }
    }
    _bleLog(
      'device ${_device.remoteId} discovered ${_characteristics.length} characteristics: '
      '${_characteristics.keys.join(", ")}',
    );
  }

  @override
  Future<void> setNotifyValue({
    required String serviceUuid,
    required String characteristicUuid,
    required bool enabled,
  }) async {
    final characteristic = _findCharacteristic(serviceUuid, characteristicUuid);
    await characteristic.setNotifyValue(enabled);
  }

  @override
  Stream<List<int>> onCharacteristicValue({
    required String serviceUuid,
    required String characteristicUuid,
  }) {
    final characteristic = _findCharacteristic(serviceUuid, characteristicUuid);
    return characteristic.onValueReceived;
  }

  @override
  Future<void> write({
    required String serviceUuid,
    required String characteristicUuid,
    required List<int> value,
    required bool withoutResponse,
  }) async {
    final characteristic = _findCharacteristic(serviceUuid, characteristicUuid);
    await characteristic.write(value, withoutResponse: withoutResponse);
  }

  BluetoothCharacteristic _findCharacteristic(
    String serviceUuid,
    String characteristicUuid,
  ) {
    final key =
        '${serviceUuid.toLowerCase()}/${characteristicUuid.toLowerCase()}';
    final characteristic = _characteristics[key];
    if (characteristic == null) {
      final discovered = _characteristics.keys.toList(growable: false)..sort();
      throw StateError(
        'BLE characteristic not found for $serviceUuid/$characteristicUuid. '
        'Discovered: ${discovered.isEmpty ? "<none>" : discovered.join(", ")}',
      );
    }
    return characteristic;
  }
}
