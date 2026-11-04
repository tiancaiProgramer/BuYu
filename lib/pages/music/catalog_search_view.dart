// Community maintenance and new features: tiancaiProgramer.
import 'package:audio_service/audio_service.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import '../../common/music/catalog_search.dart';
import '../../common/music/mixed_search.dart';
import '../../common/music/music_source.dart';
import '../../common/music/qq_music.dart';
import '../../common/netease_api/src/api/play/bean.dart';
import '../../routes/router.gr.dart' as routes;
import '../../widget/buyu_components.dart';
import '../../widget/landscape_cards.dart';
import '../../widget/simple_extended_image.dart';
import '../home/home_controller.dart';
import '../play_list/playlist_view.dart';
import 'source_access.dart';

class CatalogSearchView extends StatefulWidget {
  const CatalogSearchView(
      {super.key,
      required this.query,
      required this.kind,
      this.search,
      this.onOpen});
  final String query;
  final CatalogKind kind;
  final MixedSearch? search;
  final ValueChanged<MediaItem>? onOpen;
  @override
  State<CatalogSearchView> createState() => _CatalogSearchViewState();
}

class _CatalogSearchViewState extends State<CatalogSearchView> {
  late final search = widget.search ??
      MixedSearch(providers: {
        MusicSource.netease: (q, p) => CatalogSearch.netease(widget.kind, q, p),
        MusicSource.qq: (q, p) =>
            CatalogSearch.qq(QqMusic.instance, widget.kind, q, p),
      });
  late final SourceAccess access;
  MusicSource? filter;
  void reload() {
    if (filter != null && !access.sources.contains(filter)) filter = null;
    search.search(widget.query, sources: access.sources);
  }

  @override
  void initState() {
    super.initState();
    access = SourceAccess()..addListener(reload);
    reload();
  }

  @override
  void didUpdateWidget(CatalogSearchView old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) reload();
  }

  @override
  void dispose() {
    access.removeListener(reload);
    access.dispose();
    if (widget.search == null) search.dispose();
    super.dispose();
  }

  void open(MediaItem item) {
    if (widget.onOpen != null) {
      widget.onOpen!(item);
      return;
    }
    if (sourceOf(item) == MusicSource.qq) {
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => QqCatalogSongsView(item: item)));
    } else {
      final raw = Map<String, dynamic>.from(item.extras!['catalogRaw'] as Map);
      switch (widget.kind) {
        case CatalogKind.playlist:
          context.router.push(
              const routes.PlayListView().copyWith(args: Play.fromJson(raw)));
        case CatalogKind.album:
          context.router.push(const routes.AlbumDetails()
              .copyWith(queryParams: {'album': Album.fromJson(raw)}));
        case CatalogKind.artist:
          context.router
              .push(routes.ArtistsView(artist: Artists.fromJson(raw)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: search,
      builder: (context, _) {
        final sources = filter == null ? access.sources : [filter!];
        final items =
            search.songs.where((s) => sources.contains(sourceOf(s))).toList();
        final busy = sources.any(search.busy.contains),
            ended = sources.every(search.ended.contains);
        return Column(children: [
          Wrap(spacing: 8, children: [
            BuYuChoiceChip(
                label: const Text('全部'),
                selected: filter == null,
                onSelected: (_) => setState(() => filter = null)),
            for (final s in access.sources)
              BuYuChoiceChip(
                  label: Text(s.label),
                  selected: filter == s,
                  onSelected: (_) => setState(() => filter = s)),
          ]),
          if (busy) const LinearProgressIndicator(minHeight: 2),
          for (final s in sources.where(search.errors.containsKey))
            TextButton(
                onPressed: () => search.load(s),
                child: Text(search.errors[s]!)),
          Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(busy
                          ? '正在搜索…'
                          : access.sources.isEmpty
                              ? '请先登录音乐账号'
                              : '暂无${widget.kind.label}'))
                  : ListView.builder(
                      itemCount: items.length + 1,
                      itemExtent: 80,
                      itemBuilder: (context, i) {
                        if (i == items.length)
                          return TextButton(
                              onPressed: busy || ended
                                  ? null
                                  : () {
                                      for (final s in sources) {
                                        search.load(s);
                                      }
                                    },
                              child: Text(ended ? '没有更多结果' : '加载更多'));
                        final item = items[i];
                        return ListTile(
                            leading: SimpleExtendedImage.avatar(
                                item.artUri?.toString() ?? '',
                                width: 52,
                                height: 52),
                            title: Text(item.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                '${sourceOf(item).label}${item.artist?.isNotEmpty == true ? ' · ${item.artist}' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            onTap: () => open(item));
                      })),
        ]);
      });
}

class QqCatalogSongsView extends StatefulWidget {
  const QqCatalogSongsView({super.key, required this.item, this.loadSongs});
  final MediaItem item;
  final Future<List<MediaItem>> Function(int)? loadSongs;
  @override
  State<QqCatalogSongsView> createState() => _QqCatalogSongsViewState();
}

class _QqCatalogSongsViewState extends State<QqCatalogSongsView> {
  final items = <MediaItem>[];
  int page = 0;
  bool busy = false, ended = false;
  String? error;
  Future<void> load() async {
    if (busy || ended) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final songs = await (widget.loadSongs?.call(page + 1) ??
          CatalogSearch.qqSongs(QqMusic.instance, widget.item, page + 1));
      if (!mounted) return;
      final ids = items.map(sourceKey).toSet();
      setState(() {
        items.addAll(songs.where((s) => ids.add(sourceKey(s))));
        page++;
        ended = songs.length < 100;
      });
    } catch (_) {
      if (mounted) setState(() => error = '歌曲加载失败，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(widget.item.title)),
      body: Column(children: [
        if (busy) const LinearProgressIndicator(),
        Expanded(
            child: GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: phoneLandscape(context) ? 3 : 1,
                    mainAxisExtent: 80),
                itemCount: items.length,
                itemBuilder: (context, i) => SongItem(
                    index: i,
                    mediaItem: items[i],
                    showArtwork: true,
                    onTap: () => Home.to
                        .playByIndex(i, widget.item.title, mediaItem: items)))),
        if (error != null)
          TextButton(onPressed: busy ? null : load, child: Text(error!))
        else if (!busy && items.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('暂无可用歌曲'))
        else if (!ended)
          TextButton(onPressed: busy ? null : load, child: const Text('加载更多')),
      ]));
}
