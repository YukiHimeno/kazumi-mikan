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
    this.season,
    this.episodeStart,
    this.episodeEnd,
    this.videoSource,
    this.videoCodec,
    this.bitDepth,
    this.audioCodec,
    this.subtitleHint,
    this.container,
  });

  final String title;
  final Uri torrentUrl;
  final int? episode;
  final int? season;
  final int? episodeStart;
  final int? episodeEnd;
  final String sourceGroup;
  final String? qualityHint;
  final String? videoSource;
  final String? videoCodec;
  final int? bitDepth;
  final String? audioCodec;
  final String? subtitleHint;
  final String? container;

  bool matchesEpisode(int number) =>
      episode == number ||
      (episodeStart != null &&
          episodeEnd != null &&
          number >= episodeStart! &&
          number <= episodeEnd!);

  /// Group filtering stays open-ended: the full title remains searchable when
  /// a new or ambiguous group label cannot be confidently parsed.
  bool matchesGroupQuery(String query) {
    final needle = query.trim().toLowerCase();
    return needle.isEmpty ||
        sourceGroup.toLowerCase().contains(needle) ||
        title.toLowerCase().contains(needle);
  }
}

class _ParsedRelease {
  const _ParsedRelease({
    this.season,
    this.episode,
    this.episodeStart,
    this.episodeEnd,
    this.quality,
    this.videoSource,
    this.videoCodec,
    this.bitDepth,
    this.audioCodec,
    this.subtitleHint,
    this.container,
  });

  final int? season;
  final int? episode;
  final int? episodeStart;
  final int? episodeEnd;
  final String? quality;
  final String? videoSource;
  final String? videoCodec;
  final int? bitDepth;
  final String? audioCodec;
  final String? subtitleHint;
  final String? container;
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
      final metadata = _parseMetadata(title);
      releases.add(
        MikanRelease(
          title: title,
          torrentUrl: url,
          episode: metadata.episode,
          season: metadata.season,
          episodeStart: metadata.episodeStart,
          episodeEnd: metadata.episodeEnd,
          sourceGroup: extractSourceGroup(title),
          qualityHint: metadata.quality,
          videoSource: metadata.videoSource,
          videoCodec: metadata.videoCodec,
          bitDepth: metadata.bitDepth,
          audioCodec: metadata.audioCodec,
          subtitleHint: metadata.subtitleHint,
          container: metadata.container,
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

  /// Reads the leading release label only when its shape or surrounding
  /// release structure supports it. No individual fansub names are whitelisted.
  static String extractSourceGroup(String title) {
    var rest = title.trimLeft();
    final bracket = RegExp(
      r'^(?:\[([^\]]{1,60})\]|【([^】]{1,60})】|\(([^)]{1,60})\)|（([^）]{1,60})）)',
    );
    while (true) {
      final match = bracket.firstMatch(rest);
      if (match == null) return unknownSourceGroup;
      final label = _bracketLabel(match);
      rest = rest.substring(match.end).trimLeft();
      if (_isReleaseTag(label)) continue;
      if (rest.isEmpty) return unknownSourceGroup;

      // Some groups use plain CJK names. Accept that shape only when a generic
      // season/banner marker separates it from a later bracketed series title.
      final titleBracket = RegExp(
        r'\[[^\]]{2,80}\]|【[^】]{2,80}】',
      ).firstMatch(rest);
      if (!_looksLikeSourceLabel(label) &&
          titleBracket != null &&
          RegExp(
            r'^[★☆\s\d年月新番★☆]+$',
          ).hasMatch(rest.substring(0, titleBracket.start))) {
        return label;
      }
      // A source label often precedes a bracketed series name. A numeric or
      // technical bracket immediately after it is an episode/tag, not evidence
      // that the preceding bracket was a fansub group. A second title-like
      // bracket plus release metadata is a strong group-agnostic structure.
      final nextBracket = bracket.firstMatch(rest);
      if (nextBracket != null &&
          !_isReleaseTag(_bracketLabel(nextBracket)) &&
          _hasReleaseSignal(title)) {
        return label;
      }
      if (!_looksLikeSourceLabel(label)) return unknownSourceGroup;
      if (_hasRoleCue(label) || _hasHandleCue(label)) return label;

      return unknownSourceGroup;
    }
  }

  static String _bracketLabel(RegExpMatch match) =>
      (match.group(1) ?? match.group(2) ?? match.group(3) ?? match.group(4)!)
          .trim();

  static bool _hasRoleCue(String label) =>
      RegExp(r'(字幕组|汉化组|製作組|制作组|压制组|压制|合成)$').hasMatch(label);

  static bool _hasReleaseSignal(String title) {
    final metadata = _parseMetadata(title);
    return metadata.season != null ||
        metadata.quality != null ||
        metadata.episode != null ||
        metadata.episodeStart != null ||
        metadata.videoSource != null ||
        metadata.videoCodec != null;
  }

  static bool _hasHandleCue(String label) =>
      RegExp(r'\d|[_&.-]|[A-Z].*[A-Z]').hasMatch(label) ||
      RegExp(
        r'(?:Sub|Subs|Group|Raws|ACG|Studio|Enc|Fansubs?)$',
        caseSensitive: false,
      ).hasMatch(label);

  static bool _looksLikeSourceLabel(String label) =>
      _hasRoleCue(label) ||
      (_hasHandleCue(label) &&
          RegExp(
            r'^[\p{L}\p{N}⁰¹²³⁴⁵⁶⁷⁸⁹._&-]{2,60}$',
            unicode: true,
          ).hasMatch(label));

  static bool _isReleaseTag(String label) {
    return RegExp(
      r'^(?:\d{3,4}\s*[x×]\s*\d{3,4}p?|\d{2,4}(?:年(?:\d{1,2}月)?)?|\d{1,2}月新番|S(?:eason)?\s*\d{1,2}|第\s*\d+\s*季|'
      r'(?:EP?|Episode)\s*[. #_-]*\d+(?:v\d+)?|第\s*\d+\s*[集话話]|\d{1,3}(?:v\d+)?|'
      r'\d{1,3}\s*[-~～–]\s*\d{1,3}|(?:480|720|1080|2160|4320)[pi]|[248]K|'
      r'BD(?:Rip|MV)?|WEB(?:-DL|Rip)?|TVRip|HEVC(?:[- ](?:8|10|12)bit)?|AVC|H\.?26[45]|x[ .-]?26[45]|AV1|(?:8|10|12)bit|'
      r'MP4|MKV|简(?:繁)?(?:日)?(?:内封|外挂)?|繁(?:日)?(?:内封|外挂)?|'
      r'CHS|CHT|JPN|GB|BIG5)$',
      caseSensitive: false,
    ).hasMatch(label);
  }

  static String? extractQualityHint(String title) {
    final match = RegExp(
      r'(?<!\d)(?:7680|4320|3840|2560|2160|1920|1440|1280|1080|720|480)\s*[x×]\s*(?:4320|2160|1440|1080|720|480)|'
      r'(?<!\d)(?:4320|2160|1080|720|480)[pi](?!\w)|(?<!\w)[248]K(?!\w)',
      caseSensitive: false,
    ).firstMatch(title);
    if (match == null) return null;
    final dimension = RegExp(
      r'(\d{3,4})\s*[x×]\s*(\d{3,4})',
      caseSensitive: false,
    ).firstMatch(match.group(0)!);
    if (dimension != null) return '${dimension.group(2)}p';
    return match.group(0)!.replaceAll(RegExp(r'\s+'), '');
  }

  static _ParsedRelease _parseMetadata(String title) {
    final seasonTokens =
        RegExp(
              r'\bS(?:eason)?\s*0?(\d{1,2})(?=E|\b)|\b(\d{1,2})(?:st|nd|rd|th)\s+Season\b|第\s*(\d{1,2}|[一二三四五六七八九十]{1,3})\s*季',
              caseSensitive: false,
            )
            .allMatches(title)
            .map(
              (match) => _parseNumber(
                match.group(1) ?? match.group(2) ?? match.group(3)!,
              ),
            )
            .whereType<int>()
            .toSet();
    final season = seasonTokens.length == 1 ? seasonTokens.single : null;

    final rangeMatch = RegExp(
      r'(?:\[|【|\()\s*(\d{1,3})\s*[-~～–]\s*(\d{1,3})(?:v\d+)?|'
      r'(?<![A-Za-z0-9])\d{0,2}[| ]+(\d{1,3})\s*[-~～–]\s*(\d{1,3})(?=\+SP|\s|$)',
      caseSensitive: false,
    ).firstMatch(title);
    final rangeStart = rangeMatch == null
        ? null
        : int.tryParse(rangeMatch.group(1) ?? rangeMatch.group(3)!);
    final rangeEnd = rangeMatch == null
        ? null
        : int.tryParse(rangeMatch.group(2) ?? rangeMatch.group(4)!);
    final isValidRange =
        rangeStart != null &&
        rangeEnd != null &&
        rangeStart > 0 &&
        rangeEnd >= rangeStart &&
        rangeEnd - rangeStart <= 200;

    final videoSource = _firstMatch(title, [
      (r'BD(?:Rip|MV|Remux)?|Blu[ -]?ray', 'Blu-ray'),
      (r'\bWEB(?:[ -]?(?:DL|Rip))?\b', 'WEB'),
      (r'HDTV|TVRip', 'TV'),
    ]);
    final videoCodec = _firstMatch(title, [
      (r'HEVC|H\.?265|x[ .-]?265', 'H.265/HEVC'),
      (r'AVC|H\.?264|x[ .-]?264', 'H.264/AVC'),
      (r'AV1', 'AV1'),
      (r'VP9', 'VP9'),
    ]);
    final bitDepthMatch = RegExp(
      r'yuv\d+p(8|10|12)\b|(?<!\d)(8|10|12)\s*[- ]?bit\b',
      caseSensitive: false,
    ).firstMatch(title);
    final audioCodec = _firstMatch(title, [
      (r'DTS[ .-]?HD(?:[ .-]?MA)?|DTS:X', 'DTS-HD'),
      (r'TrueHD|Dolby[ .-]?Atmos', 'Dolby TrueHD/Atmos'),
      (r'E-?AC-?3|DDP', 'E-AC-3'),
      (r'FLAC', 'FLAC'),
      (r'OPUS', 'Opus'),
      (r'AAC', 'AAC'),
      (r'AC-?3|DOLBY DIGITAL', 'AC-3'),
      (r'LPCM|PCM', 'PCM'),
      (r'MP3', 'MP3'),
    ]);
    final subtitleHint = _firstMatch(title, [
      (r'简繁日|繁简日|简日繁|繁日简', '简繁日'),
      (r'简繁|繁简', '简繁'),
      (r'繁日|日繁', '繁日'),
      (r'简日|日简', '简日'),
      (r'简体|简中|CHS', '简中'),
      (r'繁体|繁中|CHT|BIG5', '繁中'),
      (r'内封|内嵌|外挂', '字幕'),
    ]);
    final container = _firstMatch(title, [
      (r'\bMKV\b', 'MKV'),
      (r'MP4', 'MP4'),
      (r'WEBM', 'WebM'),
      (r'AVI', 'AVI'),
      (r'\bM2TS\b|\bTS\b', 'TS'),
    ]);

    return _ParsedRelease(
      season: season,
      episode: isValidRange ? null : extractEpisode(title),
      episodeStart: isValidRange ? rangeStart : null,
      episodeEnd: isValidRange ? rangeEnd : null,
      quality: extractQualityHint(title),
      videoSource: videoSource,
      videoCodec: videoCodec,
      bitDepth: bitDepthMatch == null
          ? null
          : int.parse(bitDepthMatch.group(1) ?? bitDepthMatch.group(2)!),
      audioCodec: audioCodec,
      subtitleHint: subtitleHint,
      container: container,
    );
  }

  static String? _firstMatch(String input, List<(String, String)> patterns) {
    for (final (pattern, value) in patterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(input)) return value;
    }
    return null;
  }

  static int? _parseNumber(String value) {
    final numeric = int.tryParse(value);
    if (numeric != null) return numeric;
    const digits = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (value == '十') return 10;
    if (value.startsWith('十')) return 10 + (digits[value.substring(1)] ?? 0);
    if (value.endsWith('十')) {
      return (digits[value.substring(0, value.length - 1)] ?? 0) * 10;
    }
    if (value.contains('十')) {
      final parts = value.split('十');
      return (digits[parts.first] ?? 0) * 10 + (digits[parts.last] ?? 0);
    }
    return digits[value];
  }

  /// Only recognises explicit episode markers or isolated numeric groups.
  /// Ranges, batches, and ambiguous multi-episode titles require manual choice.
  static int? extractEpisode(String title) {
    if (RegExp(
          r'剧场版|劇場版|电影|電影|Movie|合集|全集|Batch|Complete',
          caseSensitive: false,
        ).hasMatch(title) ||
        RegExp(r'(?<!\d)\d{1,3}\s*[-~～–]\s*\d{1,3}(?!\d)').hasMatch(title)) {
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
      RegExp(r'[-–]\s*(\d{1,3})\s*(?:END|FIN)(?!\w)', caseSensitive: false),
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
