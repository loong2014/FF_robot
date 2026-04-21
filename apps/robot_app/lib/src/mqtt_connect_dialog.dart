import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_sdk/mobile_sdk.dart';

/// Prompts the user for MQTT broker address, robot id and optional
/// credentials. Returns a new [MqttConnectionOptions] on submit, or
/// `null` if the dialog is dismissed.
Future<MqttConnectionOptions?> showMqttConnectDialog({
  required BuildContext context,
  MqttConnectionOptions initial = const MqttConnectionOptions(),
}) {
  return showDialog<MqttConnectionOptions>(
    context: context,
    builder: (context) => _MqttConnectDialog(initial: initial),
  );
}

class _MqttConnectDialog extends StatefulWidget {
  const _MqttConnectDialog({required this.initial});

  final MqttConnectionOptions initial;

  @override
  State<_MqttConnectDialog> createState() => _MqttConnectDialogState();
}

class _MqttConnectDialogState extends State<_MqttConnectDialog> {
  late final TextEditingController _hostController = TextEditingController(
    text: widget.initial.host,
  );
  late final TextEditingController _portController = TextEditingController(
    text: widget.initial.port.toString(),
  );
  late final TextEditingController _robotIdController = TextEditingController(
    text: widget.initial.robotId,
  );
  late final TextEditingController _clientIdController = TextEditingController(
    text: widget.initial.clientId,
  );
  late final TextEditingController _usernameController = TextEditingController(
    text: widget.initial.username ?? '',
  );
  late final TextEditingController _passwordController = TextEditingController(
    text: widget.initial.password ?? '',
  );
  bool _useTls = false;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _useTls = widget.initial.useTls;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _robotIdController.dispose();
    _clientIdController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final host = _hostController.text.trim();
    final port = int.parse(_portController.text.trim());
    final robotId = _robotIdController.text.trim();
    final clientId = _clientIdController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    Navigator.of(context).pop(
      MqttConnectionOptions(
        host: host,
        port: port,
        robotId: robotId,
        clientId: clientId,
        username: username.isEmpty ? null : username,
        password: password.isEmpty ? null : password,
        useTls: _useTls,
        keepAlive: widget.initial.keepAlive,
        connectTimeout: widget.initial.connectTimeout,
        qos: widget.initial.qos,
        subscribeEvents: widget.initial.subscribeEvents,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('MQTT 连接参数'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: 'Broker Host',
                  hintText: '例如 broker.local 或 127.0.0.1',
                ),
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Host 不能为空';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  hintText: '默认 1883，TLS 常用 8883',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                textInputAction: TextInputAction.next,
                validator: (value) {
                  final port = int.tryParse(value?.trim() ?? '');
                  if (port == null || port <= 0 || port > 65535) {
                    return '端口必须在 1-65535 范围内';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _robotIdController,
                decoration: const InputDecoration(
                  labelText: 'Robot ID',
                  hintText: '决定 topic 前缀 robot/{id}/*',
                ),
                textInputAction: TextInputAction.next,
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) {
                    return 'Robot ID 不能为空';
                  }
                  if (trimmed.contains('/') ||
                      trimmed.contains('+') ||
                      trimmed.contains('#')) {
                    return '不能包含 / + # 等 MQTT 通配符';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _clientIdController,
                decoration: const InputDecoration(
                  labelText: 'Client ID (可选)',
                  hintText: '留空则自动生成 mobile-sdk-{robotId}-*',
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username (可选)',
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password (可选)',
                ),
                obscureText: true,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _useTls,
                onChanged: (value) => setState(() => _useTls = value),
                title: const Text('启用 TLS'),
                subtitle: const Text('开启后请把端口改到 8883 或 broker 指定端口'),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('连接')),
      ],
    );
  }
}
