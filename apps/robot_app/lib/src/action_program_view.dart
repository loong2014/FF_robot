import 'dart:async';

import 'package:flutter/material.dart';

import 'action_engine.dart';
import 'action_models.dart';
import 'action_step_editor_dialog.dart';

class ActionProgramView extends StatefulWidget {
  const ActionProgramView({
    super.key,
    required this.engine,
    this.initialProgram = const <ActionStep>[],
    this.isConnected = true,
    this.onRequireConnection,
  });

  final ActionEngine engine;
  final List<ActionStep> initialProgram;

  /// 机器人链路是否已连接。未连接时"执行"按钮会被禁用。
  final bool isConnected;

  /// 未连接时用户尝试执行动作的回调（用于提示去连接机器人）。
  final VoidCallback? onRequireConnection;

  @override
  State<ActionProgramView> createState() => _ActionProgramViewState();
}

class _ActionProgramViewState extends State<ActionProgramView> {
  late List<ActionStep> _program;
  ActionProgress _progress = const ActionProgress.idle();
  StreamSubscription<ActionProgress>? _subscription;

  @override
  void initState() {
    super.initState();
    _program = List<ActionStep>.from(widget.initialProgram);
    _subscription = widget.engine.progressStream.listen((progress) {
      if (!mounted) {
        return;
      }
      setState(() {
        _progress = progress;
      });
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  bool get _isRunningOrPaused =>
      _progress.engineStatus == ActionEngineStatus.running ||
      _progress.engineStatus == ActionEngineStatus.paused;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.86),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFB8D3CC)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            blurRadius: 24,
            offset: Offset(0, 12),
            color: Color(0x220F3D38),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '动作编排',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF183936),
                  ),
                ),
              ),
              _LinkStatusChip(isConnected: widget.isConnected),
              const SizedBox(width: 8),
              _EngineStatusChip(status: _progress.engineStatus),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '点击动作可修改参数；长按拖拽可调整顺序；左滑删除。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF4B6B66),
            ),
          ),
          const SizedBox(height: 16),
          _buildControlBar(),
          const SizedBox(height: 12),
          _buildAddBar(),
          const SizedBox(height: 12),
          if (_program.isEmpty)
            _emptyPlaceholder(theme)
          else
            _buildReorderableList(),
        ],
      ),
    );
  }

  Widget _emptyPlaceholder(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F7F5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFCFDFDB), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        '还没有动作，使用上面的按钮新增。',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF406763),
        ),
      ),
    );
  }

  Widget _buildControlBar() {
    final status = _progress.engineStatus;
    final canRunProgram =
        _program.isNotEmpty &&
        status != ActionEngineStatus.running &&
        status != ActionEngineStatus.paused;
    final canRun = canRunProgram && widget.isConnected;
    final canPauseResume = _isRunningOrPaused;
    final canStop = _isRunningOrPaused;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        FilledButton.icon(
          onPressed: canRun
              ? _run
              : (canRunProgram && !widget.isConnected
                    ? _handleRequireConnection
                    : null),
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('执行'),
        ),
        OutlinedButton.icon(
          onPressed: canPauseResume ? _togglePause : null,
          icon: Icon(
            status == ActionEngineStatus.paused
                ? Icons.play_circle_outline
                : Icons.pause_circle_outline,
            size: 18,
          ),
          label: Text(
            status == ActionEngineStatus.paused ? '恢复' : '暂停',
          ),
        ),
        OutlinedButton.icon(
          onPressed: canStop ? _stop : null,
          icon: const Icon(Icons.stop_circle_outlined, size: 18),
          label: const Text('停止'),
        ),
        TextButton.icon(
          onPressed: _isRunningOrPaused || _program.isEmpty ? null : _clear,
          icon: const Icon(Icons.delete_sweep_outlined, size: 18),
          label: const Text('清空'),
        ),
      ],
    );
  }

  Widget _buildAddBar() {
    final disabled = _isRunningOrPaused;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        _AddChip(
          label: '+ stand',
          onPressed: disabled ? null : () => _addStep(ActionStep.stand()),
        ),
        _AddChip(
          label: '+ move',
          onPressed: disabled
              ? null
              : () => _addStep(
                  ActionStep.move(
                    vx: 0.3,
                    duration: const Duration(seconds: 2),
                  ),
                ),
        ),
        _AddChip(
          label: '+ sit',
          onPressed: disabled ? null : () => _addStep(ActionStep.sit()),
        ),
        _AddChip(
          label: '+ stop',
          onPressed: disabled ? null : () => _addStep(ActionStep.stop()),
        ),
      ],
    );
  }

  Widget _buildReorderableList() {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: _program.length,
      onReorder: _isRunningOrPaused ? _noopReorder : _onReorder,
      itemBuilder: (context, index) {
        final step = _program[index];
        final progress = _progress.progressFor(step.id);
        return _StepTile(
          key: ValueKey<String>(step.id),
          index: index,
          step: step,
          progress: progress,
          locked: _isRunningOrPaused,
          onEdit: _isRunningOrPaused ? null : () => _editStep(index),
          onDelete: _isRunningOrPaused ? null : () => _deleteStep(index),
        );
      },
    );
  }

  void _noopReorder(int _, int __) {}

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final clampedNew = newIndex > oldIndex ? newIndex - 1 : newIndex;
      final step = _program.removeAt(oldIndex);
      _program.insert(clampedNew, step);
    });
  }

  Future<void> _addStep(ActionStep step) async {
    setState(() {
      _program.add(step);
    });
    if (step.type == ActionCommandType.move) {
      await _editStep(_program.length - 1);
    }
  }

  Future<void> _editStep(int index) async {
    final step = _program[index];
    final updated = await showActionStepEditorDialog(
      context: context,
      initial: step,
    );
    if (!mounted || updated == null) {
      return;
    }
    setState(() {
      _program[index] = updated;
    });
  }

  void _deleteStep(int index) {
    setState(() {
      _program.removeAt(index);
    });
  }

  void _clear() {
    setState(() {
      _program.clear();
    });
  }

  void _run() {
    unawaited(widget.engine.run(List<ActionStep>.of(_program)));
  }

  void _handleRequireConnection() {
    final callback = widget.onRequireConnection;
    if (callback != null) {
      callback();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('请先连接机器人 (BLE) 再执行动作')),
    );
  }

  void _togglePause() {
    if (_progress.engineStatus == ActionEngineStatus.paused) {
      widget.engine.resume();
    } else {
      widget.engine.pause();
    }
  }

  void _stop() {
    unawaited(widget.engine.stop());
  }
}

class _AddChip extends StatelessWidget {
  const _AddChip({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onPressed,
      backgroundColor: onPressed == null
          ? const Color(0xFFE0E6E3)
          : const Color(0xFFDCEEE7),
      labelStyle: TextStyle(
        color: onPressed == null
            ? const Color(0xFF94A29F)
            : const Color(0xFF165953),
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide.none,
    );
  }
}

class _LinkStatusChip extends StatelessWidget {
  const _LinkStatusChip({required this.isConnected});

  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final color = isConnected
        ? const Color(0xFF2E7D32)
        : const Color(0xFFB23A48);
    final label = isConnected ? '已连接' : '未连接';
    final icon = isConnected ? Icons.link : Icons.link_off;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _EngineStatusChip extends StatelessWidget {
  const _EngineStatusChip({required this.status});

  final ActionEngineStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _styleFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  static (String, Color) _styleFor(ActionEngineStatus status) {
    switch (status) {
      case ActionEngineStatus.idle:
        return ('空闲', const Color(0xFF546F6A));
      case ActionEngineStatus.running:
        return ('执行中', const Color(0xFF1F7A6F));
      case ActionEngineStatus.paused:
        return ('已暂停', const Color(0xFFB7791F));
      case ActionEngineStatus.stopped:
        return ('已停止', const Color(0xFFB23A48));
      case ActionEngineStatus.completed:
        return ('已完成', const Color(0xFF2E7D32));
    }
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    super.key,
    required this.index,
    required this.step,
    required this.progress,
    required this.locked,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final ActionStep step;
  final ActionStepProgress? progress;
  final bool locked;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final status = progress?.status ?? ActionStepStatus.pending;
    final (statusLabel, statusColor, statusIcon) = _statusStyle(status);
    final errorMessage = progress?.errorMessage;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey<String>('dismiss_${step.id}'),
        direction: (locked || onDelete == null)
            ? DismissDirection.none
            : DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF4CDD0),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.delete_outline, color: Color(0xFFB23A48)),
        ),
        onDismissed: (_) => onDelete?.call(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onEdit,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5FAF8),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: statusColor.withOpacity(0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: statusColor.withOpacity(0.15),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Text(
                              step.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF173C38),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusPill(
                              label: statusLabel,
                              color: statusColor,
                              icon: statusIcon,
                            ),
                            if ((progress?.attempts ?? 0) > 1) ...<Widget>[
                              const SizedBox(width: 6),
                              Text(
                                '第 ${progress!.attempts} 次尝试',
                                style: const TextStyle(
                                  color: Color(0xFF666F6D),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          step.summary,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Color(0xFF3C5956),
                          ),
                        ),
                        if (errorMessage != null) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(
                            '错误: $errorMessage',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFB23A48),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!locked)
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.drag_handle,
                          color: Color(0xFF7AA19B),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static (String, Color, IconData) _statusStyle(ActionStepStatus status) {
    switch (status) {
      case ActionStepStatus.pending:
        return ('待执行', const Color(0xFF6B8682), Icons.schedule);
      case ActionStepStatus.running:
        return ('运行中', const Color(0xFF1F7A6F), Icons.autorenew);
      case ActionStepStatus.done:
        return ('完成', const Color(0xFF2E7D32), Icons.check_circle_outline);
      case ActionStepStatus.failed:
        return ('失败', const Color(0xFFB23A48), Icons.error_outline);
      case ActionStepStatus.skipped:
        return ('跳过', const Color(0xFF8A6D3B), Icons.skip_next);
    }
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
