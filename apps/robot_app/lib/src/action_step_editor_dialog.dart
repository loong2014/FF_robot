import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'action_models.dart';

Future<ActionStep?> showActionStepEditorDialog({
  required BuildContext context,
  required ActionStep initial,
}) {
  return showDialog<ActionStep>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ActionStepEditorDialog(initial: initial),
  );
}

class _ActionStepEditorDialog extends StatefulWidget {
  const _ActionStepEditorDialog({required this.initial});

  final ActionStep initial;

  @override
  State<_ActionStepEditorDialog> createState() =>
      _ActionStepEditorDialogState();
}

class _ActionStepEditorDialogState extends State<_ActionStepEditorDialog> {
  late final TextEditingController _vx;
  late final TextEditingController _vy;
  late final TextEditingController _yaw;
  late final TextEditingController _durationMs;
  late final TextEditingController _retries;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _vx = TextEditingController(text: widget.initial.vx.toString());
    _vy = TextEditingController(text: widget.initial.vy.toString());
    _yaw = TextEditingController(text: widget.initial.yaw.toString());
    _durationMs = TextEditingController(
      text: (widget.initial.duration?.inMilliseconds ?? 1000).toString(),
    );
    _retries = TextEditingController(
      text: widget.initial.maxRetries.toString(),
    );
  }

  @override
  void dispose() {
    _vx.dispose();
    _vy.dispose();
    _yaw.dispose();
    _durationMs.dispose();
    _retries.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.initial;
    final isMove = step.type == ActionCommandType.move;

    return AlertDialog(
      title: Text('编辑动作 · ${step.title}'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (isMove) ...<Widget>[
                _numberField(
                  controller: _vx,
                  label: 'vx (m/s)',
                  allowNegative: true,
                ),
                _numberField(
                  controller: _vy,
                  label: 'vy (m/s)',
                  allowNegative: true,
                ),
                _numberField(
                  controller: _yaw,
                  label: 'yaw (rad/s)',
                  allowNegative: true,
                ),
                _numberField(
                  controller: _durationMs,
                  label: '持续 duration (ms)',
                  allowNegative: false,
                  isInteger: true,
                ),
              ],
              _numberField(
                controller: _retries,
                label: '失败重试次数 maxRetries',
                allowNegative: false,
                isInteger: true,
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
        FilledButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }

  void _submit() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    final step = widget.initial;
    final retries = int.tryParse(_retries.text.trim()) ?? 0;

    ActionStep updated;
    if (step.type == ActionCommandType.move) {
      final vx = double.tryParse(_vx.text.trim()) ?? step.vx;
      final vy = double.tryParse(_vy.text.trim()) ?? step.vy;
      final yaw = double.tryParse(_yaw.text.trim()) ?? step.yaw;
      final durationMs =
          int.tryParse(_durationMs.text.trim()) ??
          step.duration?.inMilliseconds ??
          0;
      updated = step.copyWith(
        vx: vx,
        vy: vy,
        yaw: yaw,
        duration: Duration(milliseconds: durationMs),
        maxRetries: retries,
      );
    } else {
      updated = step.copyWith(maxRetries: retries);
    }

    Navigator.of(context).pop(updated);
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required bool allowNegative,
    bool isInteger = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        keyboardType: TextInputType.numberWithOptions(
          decimal: !isInteger,
          signed: allowNegative,
        ),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(
            RegExp(
              allowNegative
                  ? (isInteger ? r'[-0-9]' : r'[-0-9.]')
                  : (isInteger ? r'[0-9]' : r'[0-9.]'),
            ),
          ),
        ],
        validator: (value) {
          final text = value?.trim() ?? '';
          if (text.isEmpty) {
            return '不能为空';
          }
          if (isInteger) {
            final parsed = int.tryParse(text);
            if (parsed == null) {
              return '需要整数';
            }
            if (!allowNegative && parsed < 0) {
              return '必须 ≥ 0';
            }
          } else {
            final parsed = double.tryParse(text);
            if (parsed == null) {
              return '需要数字';
            }
          }
          return null;
        },
      ),
    );
  }
}
