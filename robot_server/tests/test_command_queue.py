from __future__ import annotations

import unittest

from robot_server.runtime import CommandQueue, QueuedCommand


class CommandQueueTests(unittest.TestCase):
    def test_move_only_keeps_latest(self) -> None:
        queue = CommandQueue()
        queue.enqueue(QueuedCommand(seq=1, frame=b"a", is_move=True))
        queue.enqueue(QueuedCommand(seq=2, frame=b"b", is_move=True))

        current = queue.promote_next(sent_at=1.0)
        self.assertIsNotNone(current)
        assert current is not None
        self.assertEqual(current.seq, 2)

    def test_discrete_commands_are_fifo(self) -> None:
        queue = CommandQueue()
        queue.enqueue(QueuedCommand(seq=1, frame=b"a", is_move=False))
        queue.enqueue(QueuedCommand(seq=2, frame=b"b", is_move=False))

        first = queue.promote_next(sent_at=1.0)
        self.assertEqual(first.seq if first else None, 1)
        self.assertTrue(queue.ack(1))

        second = queue.promote_next(sent_at=2.0)
        self.assertEqual(second.seq if second else None, 2)

    def test_retry_then_drop_after_limit(self) -> None:
        queue = CommandQueue()
        queue.enqueue(QueuedCommand(seq=5, frame=b"x", is_move=False))
        queue.promote_next(sent_at=1.0)

        self.assertEqual(queue.retry_current(sent_at=2.0, max_retries=3).retries, 1)
        self.assertEqual(queue.retry_current(sent_at=3.0, max_retries=3).retries, 2)
        self.assertEqual(queue.retry_current(sent_at=4.0, max_retries=3).retries, 3)
        self.assertIsNone(queue.retry_current(sent_at=5.0, max_retries=3))
        self.assertIsNone(queue.inflight)


if __name__ == "__main__":
    unittest.main()
