import 'dart:typed_data';

import 'codec.dart';
import 'frame_types.dart';
import 'models.dart';

class StreamFrameDecoder {
  final List<int> _buffer = <int>[];

  List<RobotFrame> feed(List<int> chunk) {
    if (chunk.isEmpty) {
      return const <RobotFrame>[];
    }

    _buffer.addAll(chunk);
    final frames = <RobotFrame>[];

    while (true) {
      final start = _findMagic();
      if (start == -1) {
        if (_buffer.isNotEmpty && _buffer.last == kMagic.first) {
          final tail = _buffer.last;
          _buffer
            ..clear()
            ..add(tail);
        } else {
          _buffer.clear();
        }
        break;
      }

      if (start > 0) {
        _buffer.removeRange(0, start);
      }

      if (_buffer.length < kFrameOverhead) {
        break;
      }

      final payloadLength = _buffer[4] | (_buffer[5] << 8);
      if (payloadLength > kMaxPayloadLength) {
        _buffer.removeAt(0);
        continue;
      }

      final totalLength = kFrameOverhead + payloadLength;
      if (_buffer.length < totalLength) {
        break;
      }

      final candidate = Uint8List.fromList(_buffer.sublist(0, totalLength));
      try {
        frames.add(decodeFrame(candidate));
        _buffer.removeRange(0, totalLength);
      } on ProtocolException {
        _buffer.removeAt(0);
      }
    }

    return frames;
  }

  int _findMagic() {
    for (var i = 0; i <= _buffer.length - 2; i += 1) {
      if (_buffer[i] == kMagic[0] && _buffer[i + 1] == kMagic[1]) {
        return i;
      }
    }
    return -1;
  }
}
