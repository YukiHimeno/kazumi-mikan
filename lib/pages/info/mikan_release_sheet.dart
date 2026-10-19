import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/services/mikan/mikan_service.dart';

/// Mikan releases are not guaranteed to correspond to Bangumi episodes.
/// Always let the viewer choose the actual fansub / resolution / release.
class MikanReleaseSheet extends StatefulWidget {
  const MikanReleaseSheet({super.key, required this.bangumi});

  final BangumiItem bangumi;

  @override
  State<MikanReleaseSheet> createState() => _MikanReleaseSheetState();
}

class _MikanReleaseSheetState extends State<MikanReleaseSheet> {
  final MikanService _service = MikanService();
  final TextEditingController _query = TextEditingController();
  List<MikanRelease> _releases = [];
  String? _error;
  bool _loading = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _query.text = widget.bangumi.nameCn.isNotEmpty
        ? widget.bangumi.nameCn
        : widget.bangumi.name;
    _search();
  }

  Future<void> _search() async {
    final request = ++_request;
    final query = _query.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _releases = [];
    });
    try {
      final releases = await _service.search(query);
      if (mounted && request == _request) setState(() => _releases = releases);
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = '检索失败：$e');
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    ++_request;
    _query.dispose();
    _service.close();
    super.dispose();
  }

  void _play(int index) {
    context.pushNamed(
      '/video/',
      arguments: MikanVideoPlaybackArgs(
        bangumiItem: widget.bangumi,
        titles: [_releases[index].title],
        torrentUrls: [_releases[index].torrentUrl.toString()],
        selectedIndex: 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text('蜜柑计划 · BT 发布列表', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _query,
            decoration: InputDecoration(
              labelText: '搜索番剧名（可尝试别名）',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _search,
              ),
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (!_loading && _error == null && _releases.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('没有找到发布版本，可换用其他名称搜索'),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _releases.length,
              itemBuilder: (context, index) {
                final release = _releases[index];
                return ListTile(
                  title: Text(
                    release.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    release.episode == null
                        ? '请确认集数和版本'
                        : '可能是第 ${release.episode} 集 · 请确认版本',
                  ),
                  trailing: const Icon(Icons.play_arrow),
                  onTap: () => _play(index),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
