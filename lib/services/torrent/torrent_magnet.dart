import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Hash the original bencoded info bytes, not a re-encoded representation.
String torrentToMagnet(List<int> bytes) {
  final data = Uint8List.fromList(bytes);
  final decoder = _BencodeDecoder(data);
  final root = decoder.read();
  if (root is! Map<String, Object> ||
      decoder.position != data.length ||
      root['info'] is! Map<String, Object> ||
      decoder.infoStart == null ||
      decoder.infoEnd == null) {
    throw const FormatException('Invalid torrent metainfo');
  }

  final hash = sha1.convert(data.sublist(decoder.infoStart!, decoder.infoEnd!));
  final trackers = <String>{};
  void addTracker(Object? value) {
    if (value is Uint8List) {
      final url = utf8.decode(value, allowMalformed: true);
      if (url.isNotEmpty) trackers.add(url);
    } else if (value is List<Object>) {
      for (final item in value) {
        addTracker(item);
      }
    }
  }

  addTracker(root['announce']);
  addTracker(root['announce-list']);
  return Uri(
    scheme: 'magnet',
    queryParameters: {
      'xt': 'urn:btih:$hash',
      if (trackers.isNotEmpty) 'tr': trackers.toList(),
    },
  ).toString();
}

class _BencodeDecoder {
  _BencodeDecoder(this.data);

  final Uint8List data;
  int position = 0;
  int? infoStart;
  int? infoEnd;

  Object read([int depth = 0, bool root = true]) {
    if (depth > 64 || position >= data.length) {
      throw const FormatException('Invalid bencode');
    }
    final token = data[position];
    if (token == 100) {
      position++;
      final result = <String, Object>{};
      while (position < data.length && data[position] != 101) {
        final key = utf8.decode(_readBytes());
        if (result.containsKey(key)) {
          throw const FormatException('Duplicate torrent key');
        }
        final start = position;
        final value = read(depth + 1, false);
        if (root && key == 'info') {
          infoStart = start;
          infoEnd = position;
        }
        result[key] = value;
      }
      _end();
      return result;
    }
    if (token == 108) {
      position++;
      final result = <Object>[];
      while (position < data.length && data[position] != 101) {
        result.add(read(depth + 1, false));
      }
      _end();
      return result;
    }
    if (token == 105) {
      position++;
      final end = data.indexOf(101, position);
      if (end < 0) throw const FormatException('Unterminated integer');
      final value = int.tryParse(ascii.decode(data.sublist(position, end)));
      if (value == null) throw const FormatException('Invalid integer');
      position = end + 1;
      return value;
    }
    return _readBytes();
  }

  Uint8List _readBytes() {
    final start = position;
    while (position < data.length &&
        data[position] >= 48 &&
        data[position] <= 57) {
      position++;
    }
    if (start == position || position >= data.length || data[position] != 58) {
      throw const FormatException('Invalid byte string');
    }
    final length = int.tryParse(ascii.decode(data.sublist(start, position)));
    position++;
    if (length == null || length > data.length - position) {
      throw const FormatException('Truncated byte string');
    }
    final result = Uint8List.sublistView(data, position, position + length);
    position += length;
    return result;
  }

  void _end() {
    if (position >= data.length || data[position] != 101) {
      throw const FormatException('Unterminated bencode container');
    }
    position++;
  }
}
