import '../../widget/buyu_components.dart';
// Community maintenance and new features: tiancaiProgramer.
import 'package:flutter/material.dart';
import '../../common/music/mixed_search.dart';
import '../../widget/landscape_cards.dart';
import '../../common/music/music_source.dart';
import '../../common/music/qq_music.dart';
import '../../common/netease_api/src/netease_api.dart';
import '../../common/netease_api/src/dio_ext.dart';
import '../../common/netease_api/src/api/play/bean.dart';
import '../home/home_controller.dart';
import '../play_list/playlist_view.dart';
import 'source_access.dart';

class MixedSongSearchView extends StatefulWidget {
  const MixedSongSearchView({super.key, required this.query, this.search});
  final String query;
  final MixedSearch? search;
  @override
  State<MixedSongSearchView> createState() => _MixedSongSearchViewState();
}

class _MixedSongSearchViewState extends State<MixedSongSearchView> {
  late final MixedSearch search = widget.search ??
      MixedSearch(providers: {
        MusicSource.netease: (query, page) async {
          final response = await Https.dioProxy.postUri(NeteaseMusicApi()
              .searchSongDioMetaData(query,
                  cloudSearch: true, offset: (page - 1) * 20, limit: 20));
          final body = response.data;
          if (body is! Map || body['code'] != 200)
            throw const MusicServiceError('网易云搜索失败');
          final result = body['result'] as Map? ?? {};
          return Home.to.song2ToMedia((result['songs'] as List? ?? [])
              .whereType<Map>()
              .map((m) => Song2.fromJson(Map<String, dynamic>.from(m)))
              .toList());
        },
        MusicSource.qq: (query, page) =>
            QqMusic.instance.search(query, page: page),
      });
  MusicSource? filter;
  late final SourceAccess _access;
  void _reload() => search.search(widget.query, sources: _access.sources);
  void _accountsChanged() {
    if (!mounted) return;
    setState(() {
      if (filter != null && !_access.sources.contains(filter)) filter = null;
    });
    _reload();
  }

  @override
  void initState() {
    super.initState();
    _access = SourceAccess()..addListener(_accountsChanged);
    _reload();
  }

  @override
  void didUpdateWidget(MixedSongSearchView old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _reload();
  }

  @override
  void dispose() {
    _access.removeListener(_accountsChanged);
    _access.dispose();
    if (widget.search == null) search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: search,
      builder: (context, _) {
        final visible = _access.sources;
        final songs = search.songs
            .where((s) =>
                visible.contains(sourceOf(s)) &&
                (filter == null || sourceOf(s) == filter))
            .toList();
        final sources = filter == null ? visible : [filter!];
        final busy = search.busy.any(sources.contains);
        final ended = sources.every(search.ended.contains);
        return Column(children: [
          if (visible.isNotEmpty)
            Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Wrap(spacing: 8, children: [
                  BuYuChoiceChip(
                      label: const Text('全部'),
                      selected: filter == null,
                      onSelected: (_) => setState(() => filter = null)),
                  for (final source in visible)
                    BuYuChoiceChip(
                        label: Text(source.label),
                        selected: filter == source,
                        onSelected: (_) => setState(() => filter = source)),
                ])),
          for (final source in search.errors.keys.where(sources.contains))
            TextButton(
                onPressed: () => search.load(source),
                child: Text(search.errors[source]!)),
          if (busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
              child: songs.isEmpty
                  ? Center(
                      child: Text(visible.isEmpty
                          ? '暂无已登录的平台，请先登录音乐账号'
                          : busy
                              ? '正在搜索…'
                              : '暂无歌曲，可切换来源或重试'))
                  : ListView.builder(
                      itemCount: songs.length + 1,
                      itemExtent: 78,
                      itemBuilder: (context, index) {
                        if (index == songs.length)
                          return Center(
                              child: TextButton(
                                  onPressed: ended || busy
                                      ? null
                                      : () {
                                          for (final source in sources) {
                                            search.load(source);
                                          }
                                        },
                                  child: Text(ended ? '没有更多歌曲' : '加载更多')));
                        return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            child: LandscapeCardSurface(
                                child: SongItem(
                                    index: index,
                                    mediaItem: songs[index],
                                    showArtwork: true,
                                    onTap: () => Home.to.playByIndex(
                                        index, '搜索',
                                        mediaItem: songs))));
                      })),
        ]);
      });
}
