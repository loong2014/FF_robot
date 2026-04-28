import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_sdk/mobile_sdk.dart';

class BleScanPage extends StatefulWidget {
  const BleScanPage({required this.client, super.key});

  final RobotClient client;

  @override
  State<BleScanPage> createState() => _BleScanPageState();
}

class _BleScanPageState extends State<BleScanPage> {
  static const Duration _scanTimeout = Duration(seconds: 8);
  static const Duration _emptyHintDelay = Duration(seconds: 10);
  static const String _robotDevicePrefix = 'Robot';

  final Map<String, BleDiscoveredDevice> _devices =
      <String, BleDiscoveredDevice>{};

  StreamSubscription<BleDiscoveredDevice>? _scanSubscription;
  Timer? _emptyHintTimer;
  bool _isScanning = false;
  bool _shouldShowEmptyHint = false;
  Object? _lastError;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    unawaited(_scanSubscription?.cancel());
    _emptyHintTimer?.cancel();
    super.dispose();
  }

  Future<void> _stopScan() async {
    final subscription = _scanSubscription;
    _scanSubscription = null;
    await subscription?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _isScanning = false;
    });
  }

  Future<void> _startScan() async {
    await _scanSubscription?.cancel();
    _emptyHintTimer?.cancel();
    if (!mounted) {
      return;
    }

    setState(() {
      _devices.clear();
      _lastError = null;
      _isScanning = true;
      _shouldShowEmptyHint = false;
    });

    _emptyHintTimer = Timer(_emptyHintDelay, () {
      if (!mounted || _devices.isNotEmpty) {
        return;
      }
      setState(() {
        _shouldShowEmptyHint = true;
      });
    });

    _scanSubscription = widget.client.scanBLE(timeout: _scanTimeout).listen(
      (device) {
        if (!_isRobotDevice(device)) {
          return;
        }
        if (!mounted) {
          return;
        }
        setState(() {
          _devices[device.id] = device;
        });
      },
      onError: (error) {
        if (!mounted) {
          return;
        }
        setState(() {
          _lastError = error;
          _isScanning = false;
        });
      },
      onDone: () {
        if (!mounted) {
          return;
        }
        setState(() {
          _isScanning = false;
        });
      },
    );
  }

  bool _isRobotDevice(BleDiscoveredDevice device) {
    return device.name.trim().startsWith(_robotDevicePrefix);
  }

  @override
  Widget build(BuildContext context) {
    final devices = _devices.values.toList()
      ..sort((left, right) => right.rssi.compareTo(left.rssi));

    return Scaffold(
      appBar: AppBar(
        title: const Text('选择 BLE 设备'),
        actions: <Widget>[
          IconButton(
            onPressed: _isScanning ? null : _startScan,
            icon: const Icon(Icons.refresh),
            tooltip: '重新扫描',
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          ListTile(
            leading: _isScanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bluetooth_searching),
            title: Text(_isScanning ? '正在扫描附近机器人...' : '扫描已完成'),
            subtitle: const Text(
              '当前仅展示名称以 Robot 开头的 BLE 设备；选择后再按 Robot OS Lite 的 service UUID 建立连接。',
            ),
          ),
          if (_lastError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '扫描失败: $_lastError',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          Expanded(
            child: devices.isEmpty
                ? _shouldShowEmptyHint
                    ? const Center(
                        child: Text(
                          '暂无以 Robot 开头的可连接设备，请确认机器人已开启 BLE 广播。',
                        ),
                      )
                    : const SizedBox.shrink()
                : ListView.separated(
                    itemCount: devices.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      return ListTile(
                        leading: const Icon(Icons.bluetooth),
                        title: Text(
                          device.name.isEmpty ? '未命名设备' : device.name,
                        ),
                        subtitle: Text('${device.id}\nRSSI ${device.rssi} dBm'),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final navigator = Navigator.of(context);
                          await _stopScan();
                          if (!mounted) {
                            return;
                          }
                          navigator.pop(device);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
