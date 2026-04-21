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
  });

  final int seq;
  final RobotCommand command;
  final Uint8List frameBytes;
  final bool isMove;
  final int retries;
  final DateTime? lastSentAt;

  QueuedCommand copyWith({
    int? retries,
    DateTime? lastSentAt,
    bool clearLastSentAt = false,
  }) {
    return QueuedCommand(
      seq: seq,
      command: command,
      frameBytes: frameBytes,
      isMove: isMove,
      retries: retries ?? this.retries,
      lastSentAt: clearLastSentAt ? null : (lastSentAt ?? this.lastSentAt),
    );
  }

  QueuedCommand markSent(DateTime sentAt) => copyWith(lastSentAt: sentAt);

  QueuedCommand bumpRetry(DateTime sentAt) =>
      copyWith(retries: retries + 1, lastSentAt: sentAt);
}

class CommandQueue {
  final Queue<QueuedCommand> _discreteQueue = Queue<QueuedCommand>();
  QueuedCommand? _moveSlot;
  QueuedCommand? _inflight;

  QueuedCommand? get inflight => _inflight;

  bool get hasPending =>
      _inflight != null || _moveSlot != null || _discreteQueue.isNotEmpty;

  void enqueue(QueuedCommand command) {
    if (command.isMove) {
      _moveSlot = command;
      return;
    }
    _discreteQueue.add(command);
  }

  QueuedCommand? promoteNext(DateTime sentAt) {
    if (_inflight != null) {
      return null;
    }

    final next = _discreteQueue.isNotEmpty
        ? _discreteQueue.removeFirst()
        : _moveSlot;
    if (next == null) {
      return null;
    }

    if (next.isMove) {
      _moveSlot = null;
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
