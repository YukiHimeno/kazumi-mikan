import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/torrent/torrent_magnet.dart';

void main() {
  test('hashes the original info dictionary and preserves trackers', () {
    const info = 'd6:lengthi123e4:name9:video.mp4e';
    final torrent = ascii.encode(
      'd8:announce20:https://tracker.test4:info${info}e',
    );
    final magnet = Uri.parse(torrentToMagnet(torrent));

    expect(
      magnet.queryParameters['xt'],
      'urn:btih:cf97aa9f06bfb16831201e2aae57525f11d776e2',
    );
    expect(magnet.queryParametersAll['tr'], ['https://tracker.test']);
  });

  test('hashes noncanonical info bytes without re-encoding them', () {
    const info = 'd4:name9:video.mp46:lengthi123ee';
    final magnet = Uri.parse(torrentToMagnet(ascii.encode('d4:info${info}e')));
    expect(
      magnet.queryParameters['xt'],
      'urn:btih:443fd437ee1e822a8b02358bf89201c99d0e5541',
    );
  });

  test('rejects missing info and truncated metainfo', () {
    expect(
      () => torrentToMagnet(ascii.encode('d4:name3:fooe')),
      throwsFormatException,
    );
    expect(
      () => torrentToMagnet(ascii.encode('d4:infod3:foo3:bare')),
      throwsFormatException,
    );
  });
}
