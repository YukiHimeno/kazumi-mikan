import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// A torrent release, not an episode page. A null [episode] needs manual choice
/// (for example a batch, special, or an unrecognised naming convention).
class MikanRelease {
  const MikanRelease({
    required this.title,
    required this.torrentUrl,
    required this.episode,
    this.sourceGroup = MikanService.unknownSourceGroup,
    this.qualityHint,
  });

  final String title;
  final Uri torrentUrl;
  final int? episode;
  final String sourceGroup;
  final String? qualityHint;
}

class MikanService {
  MikanService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const int _maxFeedBytes = 5 * 1024 * 1024;
  static const String unknownSourceGroup = '未标注来源';

  /// Fetches Mikan's RSS search results. Throws on HTTP errors or invalid XML.
  /// Call [close] when finished; an injected client is also closed.
  Future<List<MikanRelease>> search(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) throw ArgumentError.value(keyword, 'keyword');
    final uri = Uri.https('mikanime.tv', '/RSS/Search', {'searchstr': query});
    final response = await _client
        .send(http.Request('GET', uri))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw http.ClientException('Mikan RSS HTTP ${response.statusCode}', uri);
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      if (bytes.length + chunk.length > _maxFeedBytes) {
        throw const FormatException('Mikan RSS feed is too large');
      }
      bytes.add(chunk);
    }
    return parseRss(utf8.decode(bytes.takeBytes()));
  }

  void close() => _client.close();

  /// Parses an RSS feed without resolving external entities or accepting DTDs.
  /// Items without a usable torrent enclosure are omitted; duplicate URLs keep
  /// the first occurrence in feed order.
  static List<MikanRelease> parseRss(String source) {
    if (RegExp(r'<!DOCTYPE\b', caseSensitive: false).hasMatch(source)) {
      throw const FormatException('RSS DTDs are not supported');
    }
    final document = XmlDocument.parse(source);
    if (document.doctypeElement != null ||
        document.rootElement.name.local != 'rss') {
      throw const FormatException('Expected RSS without a DTD');
    }
    final channels = document.rootElement.findElements('channel');
    if (channels.isEmpty) throw const FormatException('RSS channel missing');

    final seen = <Uri>{};
    final releases = <MikanRelease>[];
    for (final item in channels.first.findElements('item')) {
      final enclosure = item.findElements('enclosure');
      if (enclosure.isEmpty) continue;
      final rawUrl = enclosure.first.getAttribute('url')?.trim();
      if (rawUrl == null) continue;
      final url = Uri.tryParse(rawUrl);
      if (url == null ||
          (url.scheme != 'http' && url.scheme != 'https') ||
          url.host.isEmpty ||
          url.userInfo.isNotEmpty ||
          !url.path.toLowerCase().endsWith('.torrent')) {
        continue;
      }
      final title =
          _text(item, 'title') ??
          _text(item, 'guid') ??
          _text(item, 'description');
      if (title == null || !seen.add(url)) continue;
      releases.add(
        MikanRelease(
          title: title,
          torrentUrl: url,
          episode: extractEpisode(title),
          sourceGroup: extractSourceGroup(title),
          qualityHint: extractQualityHint(title),
        ),
      );
    }
    return releases;
  }

  static String? _text(XmlElement item, String tag) {
    final elements = item.findElements(tag);
    if (elements.isEmpty) return null;
    final value = elements.first.innerText.trim();
    return value.isEmpty ? null : value;
  }

  /// Only leading bracket labels can be sources. Unfamiliar Chinese labels
  /// without a fansub suffix are too easily confused with a series name.
  static String extractSourceGroup(String title) {
    var rest = title.trimLeft();
    final bracket = RegExp(
      r'^(?:\[([^\]]{1,60})\]|【([^】]{1,60})】|\(([^)]{1,60})\)|（([^）]{1,60})）)',
    );
    while (true) {
      final match = bracket.firstMatch(rest);
      if (match == null) return unknownSourceGroup;
      final label =
          (match.group(1) ??
                  match.group(2) ??
                  match.group(3) ??
                  match.group(4)!)
              .trim();
      rest = rest.substring(match.end).trimLeft();
      if (_isReleaseTag(label)) continue;
      if (_isGroupLabel(label) && rest.isNotEmpty) {
        final nextBracket = bracket.firstMatch(rest);
        if (nextBracket != null &&
            _isReleaseTag(
              (nextBracket.group(1) ??
                      nextBracket.group(2) ??
                      nextBracket.group(3) ??
                      nextBracket.group(4)!)
                  .trim(),
            ) &&
            !_knownGroups.contains(label.toLowerCase()) &&
            !RegExp(
              r'(字幕组|汉化组|製作組|制作组|压制组|压制|合成)$',
            ).hasMatch(label)) {
          return unknownSourceGroup;
        }
        return label;
      }
      return unknownSourceGroup;
    }
  }

  static const _knownGroups = {
    'lolihouse',
    'vcb-studio',
    'nix-raws',
    '喵萌奶茶屋',
  };

  static bool _isReleaseTag(String label) {
    return RegExp(
      r'^(?:\d{2,4}(?:年(?:\d{1,2}月)?)?|\d{1,2}月新番|S(?:eason)?\s*\d{1,2}|第\s*\d+\s*季|'
      r'(?:EP?|Episode)\s*[. #_-]*\d+(?:v\d+)?|第\s*\d+\s*[集话話]|\d{1,3}(?:v\d+)?|'
      r'\d{1,3}\s*[-~～–]\s*\d{1,3}|(?:480|720|1080|2160|4320)[pi]|[248]K|'
      r'BD(?:Rip|MV)?|WEB(?:-DL|Rip)?|TVRip|HEVC|AVC|H\.?26[45]|x26[45]|'
      r'MP4|MKV|简(?:繁)?(?:日)?(?:内封|外挂)?|繁(?:日)?(?:内封|外挂)?|'
      r'CHS|CHT|JPN|GB|BIG5)$',
      caseSensitive: false,
    ).hasMatch(label);
  }

  static bool _isGroupLabel(String label) {
    if (_knownGroups.contains(label.toLowerCase()) ||
        RegExp(
          r'(字幕组|汉化组|製作組|制作组|压制组|压制|合成)$',
        ).hasMatch(label)) {
      return true;
    }
    // Unadorned Latin words can also be series names (e.g. [Naruto]).
    // Accept unfamiliar handles only when they carry a source-like cue.
    return (RegExp(r'^[A-Za-z][A-Za-z0-9._&\u4e00-\u9fff-]{2,39}$')
                .hasMatch(label) &&
            (RegExp(r'[0-9._&\u4e00-\u9fff-]').hasMatch(label) ||
                RegExp(r'(?:Sub|Group|Raws|ACG)$', caseSensitive: false)
                    .hasMatch(label)) ||
            RegExp(r'^\d[⁰¹²³⁴⁵⁶⁷⁸⁹]*ACG$', caseSensitive: false)
                .hasMatch(label)) &&
        !RegExp(
          r'^(?:Anime|Movie|OVA|OAD|Special|Complete|Batch|Sub|Subtitle|RAW|Raws|AAC|FLAC|GB|BIG5)$',
          caseSensitive: false,
        ).hasMatch(label);
  }

  static String? extractQualityHint(String title) {
    final match = RegExp(
      r'(?<!\d)(?:4320|2160|1080|720|480)[pi](?!\w)|(?<!\w)[248]K(?!\w)',
      caseSensitive: false,
    ).firstMatch(title);
    return match?.group(0);
  }

  /// Only recognises explicit episode markers or isolated numeric groups.
  /// Ranges, batches, and ambiguous multi-episode titles require manual choice.
  static int? extractEpisode(String title) {
    if (RegExp(
          r'剧场版|劇場版|电影|電影|Movie|合集|全集|Batch|Complete',
          caseSensitive: false,
        ).hasMatch(title) ||
        RegExp(r'(?<!\d)\d{1,3}\s*[-~～–]\s*\d{1,3}(?!\d)')
            .hasMatch(title)) {
      return null;
    }
    final matches = <int>{};
    final patterns = [
      RegExp(r'S\d{1,2}E(\d{1,3})(?!\d)', caseSensitive: false),
      RegExp(r'第\s*(\d{1,3})\s*[集话話]', caseSensitive: false),
      RegExp(
        r'\b(?:EP|Episode)\s*[. #_-]*\s*(\d{1,3})(?!\d)',
        caseSensitive: false,
      ),
      RegExp(r'[\[【](\d{1,3})(?:v\d+)?[\]】]', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(title)) {
        final number = int.parse(match.group(1)!);
        if (number > 0) matches.add(number);
      }
    }
    return matches.length == 1 ? matches.single : null;
  }
}
