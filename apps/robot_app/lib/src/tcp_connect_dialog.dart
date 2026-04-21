import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_sdk/mobile_sdk.dart';

/// Prompts the user for TCP host/port and returns a new
/// [TcpConnectionOptions] on submit, or `null` if the dialog is dismissed.
Future<TcpConnectionOptions?> showTcpConnectDialog({
  required BuildContext context,
  TcpConnectionOptions initial = const TcpConnectionOptions(),
}) {
  return showDialog<TcpConnectionOptions>(
    context: context,
    builder: (context) => _TcpConnectDialog(initial: initial),
  );
}

class _TcpConnectDialog extends StatefulWidget {
  const _TcpConnectDialog({required this.initial});

  final TcpConnectionOptions initial;

  @override
  State<_TcpConnectDialog> createState() => _TcpConnectDialogState();
}

class _TcpConnectDialogState extends State<_TcpConnectDialog> {
  late final TextEditingController _hostController = TextEditingController(
    text: widget.initial.host,
  );
  late final TextEditingController _portController = TextEditingController(
    text: widget.initial.port.toString(),
  );
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final host = _hostController.text.trim();
    final port = int.parse(_portController.text.trim());
    Navigator.of(context).pop(
      TcpConnectionOptions(
        host: host,
        port: port,
        connectTimeout: widget.initial.connectTimeout,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('TCP 连接参数'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextFormField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: 'Host',
                hintText: '例如 192.168.1.10 或 127.0.0.1',
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
                hintText: '1-65535，默认 9000',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              validator: (value) {
                final port = int.tryParse(value?.trim() ?? '');
                if (port == null || port <= 0 || port > 65535) {
                  return '端口必须在 1-65535 范围内';
                }
                return null;
              },
            ),
          ],
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
