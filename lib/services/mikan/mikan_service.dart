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
  });

  final String title;
  final Uri torrentUrl;
  final int? episode;
}

class MikanService {
  MikanService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const int _maxFeedBytes = 5 * 1024 * 1024;

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

  /// Only recognises explicit episode markers or isolated numeric groups.
  /// Ranges, batches, and ambiguous multi-episode titles require manual choice.
  static int? extractEpisode(String title) {
    if (RegExp(r'(?<!\d)\d{1,3}\s*[-~～–]\s*\d{1,3}(?!\d)').hasMatch(title)) {
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
