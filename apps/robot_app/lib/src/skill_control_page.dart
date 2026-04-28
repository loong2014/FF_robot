import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_sdk/mobile_sdk.dart';

import 'robot_skill_catalog.dart';

class SkillControlPage extends StatefulWidget {
  const SkillControlPage({
    super.key,
    required this.client,
    this.catalogFuture,
    this.initialTabIndex = 0,
  });

  final RobotClient client;
  final Future<RobotSkillCatalog>? catalogFuture;
  final int initialTabIndex;

  @override
  State<SkillControlPage> createState() => _SkillControlPageState();
}

class _SkillControlPageState extends State<SkillControlPage> {
  late final Future<RobotSkillCatalog> _catalogFuture;
  late RobotConnectionState _connection = widget.client.currentConnection;
  StreamSubscription<RobotConnectionState>? _connectionSubscription;
  StreamSubscription<RobotState>? _stateSubscription;

  RobotState? _state;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _catalogFuture = widget.catalogFuture ?? RobotSkillCatalog.load();
    _connectionSubscription = widget.client.connectionState.listen((state) {
      setState(() {
        _connection = state;
      });
    });
    _stateSubscription = widget.client.stateStream.listen((state) {
      setState(() {
        _state = state;
      });
    });
  }

  @override
  void dispose() {
    unawaited(_connectionSubscription?.cancel());
    unawaited(_stateSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTabIndex,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F4EA),
        appBar: AppBar(
          title: const Text('完整动作控制'),
          backgroundColor: const Color(0xFFF1F4EA),
          foregroundColor: const Color(0xFF172F2A),
          elevation: 0,
          bottom: const TabBar(
            labelColor: Color(0xFF172F2A),
            indicatorColor: Color(0xFF2F6B55),
            tabs: <Widget>[
              Tab(text: 'do_action'),
              Tab(text: 'do_dog_behavior'),
            ],
          ),
        ),
        body: FutureBuilder<RobotSkillCatalog>(
          future: _catalogFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorView(error: snapshot.error!);
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final catalog = snapshot.data!;
            final actions = _filterActions(catalog.actions);
            final behaviors = _filterBehaviors(catalog.behaviors);
            return Column(
              children: <Widget>[
                _HeaderPanel(
                  connection: _connection,
                  state: _state,
                  actionCount: catalog.actions.length,
                  behaviorCount: catalog.behaviors.length,
                  duplicateActionIds: catalog.duplicateActionIds,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '搜索动作 ID / 名称 / 行为名',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _query = value.trim().toLowerCase();
                      });
                    },
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: <Widget>[
                      _ActionList(
                        actions: actions,
                        duplicateActionIds: catalog.duplicateActionIds,
                        onRun: _runAction,
                      ),
                      _BehaviorList(
                        behaviors: behaviors,
                        onRun: _runBehavior,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<SkillActionItem> _filterActions(List<SkillActionItem> actions) {
    if (_query.isEmpty) {
      return actions;
    }
    return actions
        .where(
          (item) =>
              item.actionName.toLowerCase().contains(_query) ||
              item.actionId.toString().contains(_query),
        )
        .toList(growable: false);
  }

  List<SkillBehaviorItem> _filterBehaviors(List<SkillBehaviorItem> behaviors) {
    if (_query.isEmpty) {
      return behaviors;
    }
    return behaviors
        .where((item) => item.behaviorName.toLowerCase().contains(_query))
        .toList(growable: false);
  }

  Future<void> _runAction(SkillActionItem action) async {
    if (!_isConnected) {
      _showMessage('请先连接机器人');
      return;
    }
    try {
      await widget.client.doAction(action.actionId);
      _showMessage('已发送动作 ${action.actionName} (${action.actionId})');
    } catch (error) {
      _showMessage('动作发送失败: $error');
    }
  }

  Future<void> _runBehavior(SkillBehaviorItem item) async {
    if (!_isConnected) {
      _showMessage('请先连接机器人');
      return;
    }
    final behavior = item.behavior;
    if (behavior == null) {
      _showMessage('当前协议未支持行为 ${item.behaviorName}');
      return;
    }
    try {
      await widget.client.doDogBehavior(behavior);
      _showMessage('已发送行为 ${item.behaviorName}');
    } catch (error) {
      _showMessage('行为发送失败: $error');
    }
  }

  bool get _isConnected => _connection.status == ConnectionStatus.connected;

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _HeaderPanel extends StatelessWidget {
  const _HeaderPanel({
    required this.connection,
    required this.state,
    required this.actionCount,
    required this.behaviorCount,
    required this.duplicateActionIds,
  });

  final RobotConnectionState connection;
  final RobotState? state;
  final int actionCount;
  final int behaviorCount;
  final Set<int> duplicateActionIds;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF173D35),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x24112F2A),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _StatusChip(
                label: '连接',
                value: _connectionLabel(connection),
              ),
              _StatusChip(
                label: '动作',
                value: '$actionCount',
              ),
              _StatusChip(
                label: '行为',
                value: '$behaviorCount',
              ),
              if (duplicateActionIds.isNotEmpty)
                _StatusChip(
                  label: '重复 ID',
                  value: duplicateActionIds.join(', '),
                  warning: true,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _StateMetric(
                label: '电量',
                value: state == null ? '--' : '${state!.battery}%',
              ),
              _StateMetric(
                label: 'Roll',
                value: state == null ? '--' : state!.roll.toStringAsFixed(2),
              ),
              _StateMetric(
                label: 'Pitch',
                value: state == null ? '--' : state!.pitch.toStringAsFixed(2),
              ),
              _StateMetric(
                label: 'Yaw',
                value: state == null ? '--' : state!.yaw.toStringAsFixed(2),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _connectionLabel(RobotConnectionState connection) {
    if (connection.status == ConnectionStatus.connected) {
      return connection.transport.name.toUpperCase();
    }
    return connection.status.name;
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.value,
    this.warning = false,
  });

  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: warning ? const Color(0xFFFFE2B7) : const Color(0xFFE6F4DC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          '$label $value',
          style: TextStyle(
            color: warning ? const Color(0xFF7A3D00) : const Color(0xFF173D35),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _StateMetric extends StatelessWidget {
  const _StateMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 118,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFBBD1C8),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionList extends StatelessWidget {
  const _ActionList({
    required this.actions,
    required this.duplicateActionIds,
    required this.onRun,
  });

  final List<SkillActionItem> actions;
  final Set<int> duplicateActionIds;
  final ValueChanged<SkillActionItem> onRun;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return const _EmptyList();
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: actions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final action = actions[index];
        final duplicated = duplicateActionIds.contains(action.actionId);
        return _SkillTile(
          key: ValueKey<String>('action-${action.stableKey}'),
          title: action.actionName,
          subtitle: duplicated
              ? 'action_id ${action.actionId}，该 ID 在资源中重复'
              : 'action_id ${action.actionId}',
          icon: duplicated ? Icons.warning_amber_rounded : Icons.bolt_rounded,
          warning: duplicated,
          onPressed: () => onRun(action),
        );
      },
    );
  }
}

class _BehaviorList extends StatelessWidget {
  const _BehaviorList({
    required this.behaviors,
    required this.onRun,
  });

  final List<SkillBehaviorItem> behaviors;
  final ValueChanged<SkillBehaviorItem> onRun;

  @override
  Widget build(BuildContext context) {
    if (behaviors.isEmpty) {
      return const _EmptyList();
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: behaviors.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final behavior = behaviors[index];
        return _SkillTile(
          key: ValueKey<String>('behavior-${behavior.behaviorName}'),
          title: behavior.behaviorName,
          subtitle: behavior.isSupported ? '协议枚举已支持' : '协议枚举未支持',
          icon: behavior.isSupported
              ? Icons.account_tree_rounded
              : Icons.lock_outline_rounded,
          warning: !behavior.isSupported,
          onPressed: () => onRun(behavior),
        );
      },
    );
  }
}

class _SkillTile extends StatelessWidget {
  const _SkillTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onPressed,
    this.warning = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onPressed;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: warning ? const Color(0xFFFFC875) : const Color(0xFFE1E8DD),
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              warning ? const Color(0xFFFFE6BD) : const Color(0xFFE6F4DC),
          foregroundColor:
              warning ? const Color(0xFF7A3D00) : const Color(0xFF2F6B55),
          child: Icon(icon),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF172F2A),
          ),
        ),
        subtitle: Text(subtitle),
        trailing: FilledButton.tonal(
          onPressed: onPressed,
          child: const Text('执行'),
        ),
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('没有匹配的动作或行为'),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '加载 robot_skill 资源失败: $error',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
