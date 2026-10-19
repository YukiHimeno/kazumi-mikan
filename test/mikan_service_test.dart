import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kazumi/services/mikan/mikan_service.dart';

void main() {
  final fixture = File('test/fixtures/mikan_search.xml').readAsStringSync();

  test('parses enclosure URLs, CDATA, title fallback and deduplicates', () {
    final releases = MikanService.parseRss(fixture);
    expect(releases, hasLength(2));
    expect(releases[0].title, '[字幕组] 葬送的芙莉莲 第03话 & 1080p');
    expect(
      releases[0].torrentUrl.toString(),
      'https://mikanani.me/Download/20240101/aaa.torrent',
    );
    expect(releases[0].episode, 3);
    expect(releases[1].title, '[字幕组] 葬送的芙莉莲 [01-12] BDRip 1080p');
    expect(releases[1].episode, isNull);
  });

  test('episode extraction is conservative for ambiguous titles', () {
    expect(MikanService.extractEpisode('S02E09 1080p'), 9);
    expect(MikanService.extractEpisode('[动漫][12v2][1080p]'), 12);
    expect(MikanService.extractEpisode('Episode 07'), 7);
    expect(MikanService.extractEpisode('第 8 集'), 8);
    expect(MikanService.extractEpisode('EP01-02'), isNull);
    expect(MikanService.extractEpisode('[01][02]'), isNull);
    expect(MikanService.extractEpisode('BDRip 1080p 2024'), isNull);
  });

  test('rejects DTDs, malformed and non-RSS XML', () {
    expect(
      () => MikanService.parseRss(
        '<!DOCTYPE rss [<!ENTITY x SYSTEM "file:///etc/passwd">]>'
        '<rss><channel><item><title>&x;</title></item></channel></rss>',
      ),
      throwsFormatException,
    );
    expect(
      () => MikanService.parseRss('<rss><channel>'),
      throwsFormatException,
    );
    expect(() => MikanService.parseRss('<html/>'), throwsFormatException);
  });

  test(
    'ignores unsafe or non-torrent enclosures, falls back to description',
    () {
      final releases = MikanService.parseRss('''<rss><channel>
      <item><title>bad</title><enclosure url="javascript:alert(1).torrent"/></item>
      <item><title>page</title><enclosure url="https://mikanani.me/Home/Episode/1"/></item>
      <item><description>Episode 04</description>
        <enclosure url="https://mikanani.me/Download/4.torrent?token=a&amp;b=c"/></item>
    </channel></rss>''');
      expect(releases, hasLength(1));
      expect(releases.single.title, 'Episode 04');
      expect(releases.single.episode, 4);
      expect(releases.single.torrentUrl.queryParameters, {
        'token': 'a',
        'b': 'c',
      });
    },
  );

  test('search encodes keyword and fetches the RSS feed', () async {
    late Uri requested;
    final client = MockClient((request) async {
      requested = request.url;
      return http.Response.bytes(utf8.encode(fixture), 200);
    });
    final service = MikanService(client: client);
    try {
      final results = await service.search(' 葬送的芙莉莲 & 朋友 ');
      expect(requested.scheme, 'https');
      expect(requested.host, 'mikanime.tv');
      expect(requested.path, '/RSS/Search');
      expect(requested.queryParameters['searchstr'], '葬送的芙莉莲 & 朋友');
      expect(results, hasLength(2));
      await expectLater(service.search('  '), throwsArgumentError);
    } finally {
      service.close();
    }
  });

  test('search surfaces HTTP errors and rejects oversized feeds', () async {
    final errorService = MikanService(
      client: MockClient((_) async => http.Response('', 503)),
    );
    final largeService = MikanService(
      client: MockClient(
        (_) async => http.Response('x' * (5 * 1024 * 1024 + 1), 200),
      ),
    );
    try {
      await expectLater(
        errorService.search('x'),
        throwsA(isA<http.ClientException>()),
      );
      await expectLater(largeService.search('x'), throwsFormatException);
    } finally {
      errorService.close();
      largeService.close();
    }
  });
}
