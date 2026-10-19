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
    expect(releases[0].sourceGroup, '字幕组');
    expect(releases[0].qualityHint, '1080p');
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

  test('classifies old and modern public RSS release examples', () {
    final releases = MikanService.parseRss(
      File('test/fixtures/mikan_era_samples.xml').readAsStringSync(),
    );
    final expected = <(String, int?, String?)>[
      ('DBD-Raws&澄空学园', null, '1080P'),
      ('Moozzi2', null, null),
      ('影片压制', null, '720P'),
      ('xyx98', null, null),
      ('绿茶字幕组', 38, '1080p'),
      ('Zzz睡不醒', null, '1080P'),
      ('7³ACG', null, '1080p'),
      ('喵萌奶茶屋', null, '1080p'),
    ];
    expect(releases, hasLength(expected.length));
    for (var i = 0; i < expected.length; i++) {
      expect(
        releases[i].sourceGroup,
        expected[i].$1,
        reason: releases[i].title,
      );
      expect(releases[i].episode, expected[i].$2, reason: releases[i].title);
      expect(
        releases[i].qualityHint,
        expected[i].$3,
        reason: releases[i].title,
      );
      expect(releases[i].title, isNotEmpty);
      expect(releases[i].torrentUrl.path, endsWith('.torrent'));
    }
  });

  test('leading metadata, group labels and ambiguous series titles', () {
    final cases = <String, String>{
      '[2024][S02][1080p][WEB-DL][EP03][LoliHouse] 番剧': 'LoliHouse',
      '【动漫国字幕组】【某番剧】【03】': '动漫国字幕组',
      '[VCB-Studio] 番剧 [01-12]': 'VCB-Studio',
      '[Nix-Raws] 番剧 [01]': 'Nix-Raws',
      '【喵萌奶茶屋】某番剧 第03话': '喵萌奶茶屋',
      '[NewSub] 番剧 [03]': 'NewSub',
      '[2024][720p][HEVC] 番剧 [03]': '未标注来源',
      '[葬送的芙莉莲][03][1080p]': '未标注来源',
      '[Naruto][03][1080p]': '未标注来源',
      '[Naruto] 第03话 [1080p]': '未标注来源',
      '[Unknown] 番剧 EP03': '未标注来源',
      '[01][1080p]': '未标注来源',
      '无标签标题 第01话': '未标注来源',
    };
    for (final entry in cases.entries) {
      expect(
        MikanService.extractSourceGroup(entry.key),
        entry.value,
        reason: entry.key,
      );
    }
    expect(MikanService.extractEpisode('剧场版 番剧 [01]'), isNull);
    expect(MikanService.extractEpisode('番剧 合集 EP01'), isNull);
    expect(MikanService.extractEpisode('番剧 [01-12] EP01'), isNull);
    expect(
      MikanRelease(
        title: '无标签标题',
        torrentUrl: Uri.parse('https://mikanani.me/Download/1.torrent'),
        episode: null,
      ).sourceGroup,
      MikanService.unknownSourceGroup,
    );
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
