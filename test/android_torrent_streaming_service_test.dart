import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_go_torrent_streamer/flutter_go_torrent_streamer.dart';
import 'package:kazumi/services/torrent/android_torrent_streaming_service.dart';

void main() {
  test('native torrent argument contains the original metainfo bytes', () {
    final bytes = [0, 1, 255, 42];
    final argument = torrentStreamArgument(bytes);
    expect(argument, startsWith('torrent:'));
    expect(base64Decode(argument.substring('torrent:'.length)), bytes);
  });

  test('native error detail is forwarded into the session failure', () {
    expect(
      torrentSessionError({
        'state': 'Error',
        'error': 'timed out waiting for torrent metadata',
      }),
      contains('timed out waiting for torrent metadata'),
    );
    expect(
      torrentSessionError({'state': 'Stopped'}),
      'Torrent session failed: Stopped',
    );
  });
}
