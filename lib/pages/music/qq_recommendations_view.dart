// Community maintenance and new features: tiancaiProgramer.
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../common/music/music_source.dart';
import '../../common/music/qq_discovery.dart';
import '../../common/music/qq_music.dart';
import '../../widget/landscape_cards.dart';
import '../../widget/simple_extended_image.dart';
import 'mixed_library_view.dart';

class QqRecommendationsView extends StatefulWidget {
  const QqRecommendationsView({super.key, this.discovery, this.onOpenPlaylist});
  final QqDiscovery? discovery;
  final ValueChanged<SourcePlaylist>? onOpenPlaylist;
  @override
  State<QqRecommendationsView> createState() => _QqRecommendationsViewState();
}

class _QqRecommendationsViewState extends State<QqRecommendationsView> {
  late final api = widget.discovery ?? QqDiscovery(QqMusic.instance);
  final items = <SourcePlaylist>[];
  CancelToken? cancel;
  Object? error;
  int offset = 0, generation = 0;
  bool busy = false, more = true;

  Future<void> load({bool reset = false}) async {
    if (busy && !reset) return;
    final request = ++generation;
    cancel?.cancel();
    cancel = CancelToken();
    setState(() {
      if (reset) {
        items.clear();
        offset = 0;
        more = true;
      }
      busy = true;
      error = null;
    });
    try {
      final page =
          await api.recommendedPlaylists(offset: offset, cancelToken: cancel);
      if (!mounted || request != generation) return;
      setState(() {
        final ids = items.map((p) => p.id).toSet();
        items.addAll(page.playlists.where((p) => ids.add(p.id)));
        offset = page.nextOffset;
        more = page.hasMore;
      });
    } catch (e) {
      if (mounted && request == generation) setState(() => error = e);
    } finally {
      if (mounted && request == generation) setState(() => busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    generation++;
    cancel?.cancel();
    super.dispose();
  }

  void open(SourcePlaylist playlist) {
    if (widget.onOpenPlaylist != null) {
      widget.onOpenPlaylist!(playlist);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => MixedLibraryView(playlist: playlist, readOnly: true)));
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            child: Row(children: [
              const Expanded(
                  child: Text('歌单推荐', style: TextStyle(fontSize: 18))),
              IconButton(
                  tooltip: '刷新QQ推荐歌单',
                  onPressed: busy ? null : () => load(reset: true),
                  icon: const Icon(Icons.refresh)),
            ])),
        if (busy) const LinearProgressIndicator(),
        Expanded(child: LayoutBuilder(builder: (context, box) {
          final wide = phoneLandscape(context);
          final columns = math.max(2, (box.maxWidth / 150).floor());
          return CustomScrollView(
              key: const PageStorageKey('discovery:qq:playlists'),
              slivers: [
                SliverPadding(
                    padding: const EdgeInsets.all(12),
                    sliver: SliverGrid(
                        gridDelegate: wide
                            ? landscapeCardGrid
                            : SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                childAspectRatio: .72,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final playlist = items[index];
                          if (wide)
                            return LandscapeCard(
                                title: playlist.name,
                                subtitle: '${playlist.count} 首 · QQ音乐',
                                image: playlist.image,
                                onTap: () => open(playlist));
                          return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                  onTap: () => open(playlist),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        AspectRatio(
                                            aspectRatio: 1,
                                            child: SimpleExtendedImage(
                                                playlist.image,
                                                borderRadius:
                                                    BorderRadius.circular(12))),
                                        const SizedBox(height: 6),
                                        Expanded(
                                            child: Text(playlist.name,
                                                maxLines: 2,
                                                overflow:
                                                    TextOverflow.ellipsis)),
                                        Text('${playlist.count} 首',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall),
                                      ])));
                        }, childCount: items.length))),
                SliverToBoxAdapter(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          if (error != null) ...[
                            Text(error is MusicServiceError
                                ? (error as MusicServiceError).message
                                : 'QQ推荐歌单加载失败，请重试'),
                            TextButton(
                                onPressed: busy ? null : () => load(),
                                child: const Text('重试')),
                          ] else if (!busy && items.isEmpty)
                            const Text('暂无QQ推荐歌单，点击右上角刷新'),
                          if (items.isNotEmpty && more && error == null)
                            TextButton(
                                onPressed: busy ? null : () => load(),
                                child: Text(busy ? '正在加载…' : '加载更多')),
                        ]))),
              ]);
        })),
      ]);
}
