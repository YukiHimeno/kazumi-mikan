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
  final TextEditingController _episodeFilter = TextEditingController();
  List<MikanRelease> _releases = [];
  String? _groupFilter;
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
      _episodeFilter.clear();
      _groupFilter = null;
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
    _episodeFilter.dispose();
    _service.close();
    super.dispose();
  }

  void _play(MikanRelease release) {
    context.pushNamed(
      '/video/',
      arguments: MikanVideoPlaybackArgs(
        bangumiItem: widget.bangumi,
        titles: [release.title],
        torrentUrls: [release.torrentUrl.toString()],
        selectedIndex: 0,
        sourceGroup: release.sourceGroup,
      ),
    );
  }

  List<MikanRelease> get _filteredReleases {
    final episode = int.tryParse(_episodeFilter.text.trim());
    return _releases.where((release) {
      if (_groupFilter != null && release.sourceGroup != _groupFilter) {
        return false;
      }
      if (episode != null && !release.matchesEpisode(episode)) {
        return false;
      }
      return true;
    }).toList();
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
          if (_releases.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _episodeFilter,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '按集数筛选',
                      hintText: '如 03',
                      prefixIcon: Icon(Icons.filter_list),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: '按字幕组筛选',
                  onSelected: (value) => setState(() {
                    _groupFilter = value == '__all__' ? null : value;
                  }),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: '__all__', child: Text('全部字幕组')),
                    ...(_releases
                            .map((release) => release.sourceGroup)
                            .toSet()
                            .toList()
                          ..sort())
                        .map(
                          (group) =>
                              PopupMenuItem(value: group, child: Text(group)),
                        ),
                  ],
                  child: SizedBox(
                    width: 142,
                    child: Chip(
                      avatar: const Icon(Icons.groups_outlined, size: 18),
                      label: Text(
                        _groupFilter ?? '全部字幕组',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (!_loading && _error == null && _releases.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('没有找到发布版本，可换用其他名称搜索'),
            ),
          Expanded(
            child: _filteredReleases.isEmpty && _releases.isNotEmpty
                ? const Center(child: Text('没有符合筛选条件的发布版本'))
                : ListView.builder(
                    itemCount: _filteredReleases.length,
                    itemBuilder: (context, index) {
                      final release = _filteredReleases[index];
                      final episodeHint = release.episode != null
                          ? '第 ${release.episode} 集'
                          : release.episodeStart != null &&
                                release.episodeEnd != null
                          ? '第 ${release.episodeStart}-${release.episodeEnd} 集'
                          : '集数未确认';
                      final details = <String>[
                        release.sourceGroup,
                        if (release.season != null) '第 ${release.season} 季',
                        episodeHint,
                        if (release.qualityHint != null) release.qualityHint!,
                        if (release.videoSource != null) release.videoSource!,
                        if (release.videoCodec != null) release.videoCodec!,
                        if (release.bitDepth != null) '${release.bitDepth}bit',
                        if (release.audioCodec != null) release.audioCodec!,
                        if (release.subtitleHint != null) release.subtitleHint!,
                        if (release.container != null) release.container!,
                      ];
                      return ListTile(
                        title: Text(
                          release.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${details.join(' · ')} · 请确认版本',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.play_arrow),
                        onTap: () => _play(release),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}
