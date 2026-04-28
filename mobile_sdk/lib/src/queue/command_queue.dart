import 'dart:collection';
import 'dart:typed_data';

import 'package:robot_protocol/robot_protocol.dart';

class QueuedCommand {
  const QueuedCommand({
    required this.seq,
    required this.command,
    required this.frameBytes,
    required this.isMove,
    this.retries = 0,
    this.lastSentAt,
    this.superseded = false,
  });

  final int seq;
  final RobotCommand command;
  final Uint8List frameBytes;
  final bool isMove;
  final int retries;
  final DateTime? lastSentAt;
  final bool superseded;

  QueuedCommand copyWith({
    int? retries,
    DateTime? lastSentAt,
    bool? superseded,
    bool clearLastSentAt = false,
  }) {
    return QueuedCommand(
      seq: seq,
      command: command,
      frameBytes: frameBytes,
      isMove: isMove,
      retries: retries ?? this.retries,
      lastSentAt: clearLastSentAt ? null : (lastSentAt ?? this.lastSentAt),
      superseded: superseded ?? this.superseded,
    );
  }

  QueuedCommand markSent(DateTime sentAt) => copyWith(lastSentAt: sentAt);

  QueuedCommand bumpRetry(DateTime sentAt) =>
      copyWith(retries: retries + 1, lastSentAt: sentAt);
}

class CommandQueue {
  final Queue<QueuedCommand> _discreteQueue = Queue<QueuedCommand>();
  QueuedCommand? _latestSlot;
  QueuedCommand? _inflight;

  QueuedCommand? get inflight => _inflight;

  bool get hasPending =>
      _inflight != null || _latestSlot != null || _discreteQueue.isNotEmpty;

  void enqueue(QueuedCommand command) {
    if (command.isMove) {
      _latestSlot = command;
      return;
    }
    _latestSlot = null;
    _discreteQueue.add(command);
  }

  void enqueueLatest(QueuedCommand command) {
    _discreteQueue.clear();
    _inflight = _inflight?.copyWith(superseded: true);
    _latestSlot = command;
  }

  QueuedCommand? promoteNext(DateTime sentAt) {
    if (_inflight != null) {
      return null;
    }

    final next =
        _discreteQueue.isNotEmpty ? _discreteQueue.removeFirst() : _latestSlot;
    if (next == null) {
      return null;
    }

    if (identical(next, _latestSlot)) {
      _latestSlot = null;
    }

    _inflight = next.markSent(sentAt);
    return _inflight;
  }

  bool acknowledge(int seq) {
    if (_inflight == null || _inflight!.seq != seq) {
      return false;
    }
    _inflight = null;
    return true;
  }

  QueuedCommand? retryCurrent(DateTime sentAt, int maxRetries) {
    final current = _inflight;
    if (current == null) {
      return null;
    }
    if (current.retries >= maxRetries) {
      _inflight = null;
      return null;
    }
    _inflight = current.bumpRetry(sentAt);
    return _inflight;
  }

  void resetInflightTiming() {
    final current = _inflight;
    if (current == null) {
      return;
    }
    _inflight = current.copyWith(clearLastSentAt: true);
  }

  void dropCurrent() {
    _inflight = null;
  }
}
