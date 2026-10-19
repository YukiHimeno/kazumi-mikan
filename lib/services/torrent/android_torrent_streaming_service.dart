import 'dart:async';
import 'dart:io';

import 'package:flutter_go_torrent_streamer/flutter_go_torrent_streamer.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'torrent_magnet.dart';

/// One active Android streaming session at a time. Call stop when playback ends.
class AndroidTorrentStreamingService {
  AndroidTorrentStreamingService({FlutterTorrentStreamer? streamer})
    : _streamer = streamer ?? FlutterTorrentStreamer();

  final FlutterTorrentStreamer _streamer;
  TorrentStreamSession? _session;
  Directory? _directory;
  Future<void> _pending = Future<void>.value();
  int _generation = 0;

  Future<String> start(String torrentUrl) {
    final generation = ++_generation;
    return _exclusive(() async {
      if (!Platform.isAndroid) {
        throw UnsupportedError(
          'Torrent streaming is only supported on Android',
        );
      }
      await _stopActive();
      _checkCurrent(generation);
      try {
        final magnet = torrentUrl.startsWith('magnet:?')
            ? torrentUrl
            : torrentToMagnet(await _fetchTorrent(torrentUrl));
        _checkCurrent(generation);
        final cacheRoot = Directory(
          '${(await getApplicationSupportDirectory()).path}/torrent_streams',
        );
        await cacheRoot.create(recursive: true);
        _checkCurrent(generation);
        final directory = await cacheRoot.createTemp('session_');
        _directory = directory;
        _checkCurrent(generation);
        final session = await _streamer.startStream(magnet, directory.path);
        _session = session;
        _checkCurrent(generation);

        final deadline = DateTime.now().add(const Duration(seconds: 75));
        while (DateTime.now().isBefore(deadline)) {
          _checkCurrent(generation);
          final status = await session.getStatus();
          _checkCurrent(generation);
          final state = status['state'];
          if (state == 'Error' || state == 'Stopped' || state == 'NotFound') {
            throw StateError('Torrent session failed: $state');
          }
          if (state == 'Ready' ||
              state == 'Downloading' ||
              state == 'Seeding') {
            final files = await session.getFiles();
            _checkCurrent(generation);
            final videos = files.where(
              (file) => RegExp(
                r'\.(mp4|mkv|webm|avi|mov|m4v|ts|mpg|mpeg|wmv|flv)$',
                caseSensitive: false,
              ).hasMatch(file.name),
            );
            if (videos.isEmpty) {
              throw StateError('Torrent contains no video file');
            }
            final video = videos.reduce((a, b) => a.size >= b.size ? a : b);
            await session.selectFile(video.index);
            _checkCurrent(generation);
            final url = Uri.tryParse(session.streamUrl);
            if (url == null ||
                url.scheme != 'http' ||
                url.host != '127.0.0.1' ||
                url.port == 0) {
              throw StateError(
                'Torrent streamer returned an invalid loopback URL',
              );
            }
            return url.toString();
          }
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        throw TimeoutException('Timed out waiting for torrent metadata');
      } catch (_) {
        await _stopActive();
        rethrow;
      }
    });
  }

  Future<void> stop() {
    ++_generation;
    return _exclusive(_stopActive);
  }

  void _checkCurrent(int generation) {
    if (generation != _generation) {
      throw StateError('Torrent request superseded');
    }
  }

  Future<void> _stopActive() async {
    final session = _session;
    _session = null;
    try {
      await session?.stop();
    } finally {
      final directory = _directory;
      _directory = null;
      if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace stackTrace) {},
    );
    return result;
  }

  Future<List<int>> _fetchTorrent(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const FormatException('Expected an HTTP torrent URL');
    }
    final client = http.Client();
    try {
      final response = await client
          .send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw HttpException(
          'Torrent download failed (${response.statusCode})',
          uri: uri,
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 20),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 16 * 1024 * 1024) {
          throw const FormatException('Torrent metainfo exceeds 16 MiB');
        }
      }
      return bytes;
    } finally {
      client.close();
    }
  }
}
