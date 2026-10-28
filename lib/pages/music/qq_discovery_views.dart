// Community maintenance and new features: tiancaiProgramer.
import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../common/music/music_source.dart';
import '../../common/music/qq_discovery.dart';
import '../../common/music/qq_music.dart';
import '../../widget/landscape_cards.dart';
import '../../widget/simple_extended_image.dart';
import '../../widget/song_collection.dart';
import '../home/home_controller.dart';

class QqDailyView extends StatefulWidget {
  const QqDailyView({super.key, this.discovery});
  final QqDiscovery? discovery;
  @override
  State<QqDailyView> createState() => _QqDailyViewState();
}

class _QqDailyViewState extends State<QqDailyView> {
  late final api = widget.discovery ?? QqDiscovery(QqMusic.instance);
  final cancel = CancelToken();
  late Future<List<MediaItem>> future;
  void load() {
    future = api.dailySongs(refresh: true, cancelToken: cancel);
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    cancel.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<MediaItem>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return _retry(snapshot.error, () => setState(load));
        final tracks = snapshot.data ?? [];
        return buildSongCollection(context,
            songs: tracks,
            showArtwork: true,
            storageId: 'daily:qq',
            onPlay: (index) =>
                Home.to.playByIndex(index, 'QQ音乐每日推荐', mediaItem: tracks));
      });
}

Widget _retry(Object? error, VoidCallback retry) => Center(
    child: Padding(
        padding: const EdgeInsets.all(20),
        child: TextButton(
            onPressed: retry,
            child: Text(
                '${error is MusicServiceError ? error.message : '内容加载失败'} · 重试',
                textAlign: TextAlign.center))));

class QqPodcastsView extends StatefulWidget {
  const QqPodcastsView({super.key, this.discovery});
  final QqDiscovery? discovery;
  @override
  State<QqPodcastsView> createState() => _QqPodcastsViewState();
}

class _QqPodcastsViewState extends State<QqPodcastsView> {
  late final api = widget.discovery ?? QqDiscovery(QqMusic.instance);
  final input = TextEditingController();
  CancelToken? cancel;
  final items = <QqPodcast>[];
  String query = '播客';
  Object? error;
  int page = 1, generation = 0;
  bool busy = false, more = true;
  Future<void> load({bool reset = false}) async {
    if (busy && !reset) return;
    final request = ++generation;
    cancel?.cancel();
    cancel = CancelToken();
    setState(() {
      if (reset) {
        page = 1;
        items.clear();
        more = true;
      }
      busy = true;
      error = null;
    });
    try {
      final result =
          await api.podcasts(query: query, page: page, cancelToken: cancel);
      if (!mounted || request != generation) return;
      final ids = items.map((p) => p.id).toSet();
      setState(() {
        items.addAll(result.where((p) => ids.add(p.id)));
        page++;
        more = api.podcastsHaveMore;
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
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
                controller: input,
                decoration: const InputDecoration(
                    hintText: '搜索QQ音乐播客', prefixIcon: Icon(Icons.search)),
                textInputAction: TextInputAction.search,
                onSubmitted: (value) {
                  query = value.trim().isEmpty ? '播客' : value.trim();
                  load(reset: true);
                })),
        if (busy) const LinearProgressIndicator(),
        Expanded(
            child: items.isEmpty
                ? error != null
                    ? _retry(error, () => load(reset: true))
                    : Center(child: Text(busy ? '正在加载…' : '暂无QQ播客，可更换搜索词'))
                : LayoutBuilder(builder: (context, box) {
                    final wide = phoneLandscape(context);
                    return GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: wide ? 3 : 1,
                            mainAxisExtent: 76,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 10),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final podcast = items[index];
                          final row = InkWell(
                              onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                      builder: (_) => QqPodcastEpisodesView(
                                          podcast: podcast, discovery: api))),
                              child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Row(children: [
                                    SimpleExtendedImage(podcast.image,
                                        width: 48,
                                        height: 48,
                                        borderRadius: BorderRadius.circular(8)),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(podcast.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 15)),
                                          if (podcast.author.isNotEmpty)
                                            Text(podcast.author,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 12)),
                                        ])),
                                  ])));
                          return wide ? LandscapeCardSurface(child: row) : row;
                        });
                  })),
        if (error != null && items.isNotEmpty)
          TextButton(onPressed: () => load(), child: const Text('加载失败，重试')),
        if (more && !busy && items.isNotEmpty && error == null)
          TextButton(onPressed: () => load(), child: const Text('加载更多')),
      ]);
}

class QqPodcastEpisodesView extends StatefulWidget {
  const QqPodcastEpisodesView(
      {super.key, required this.podcast, this.discovery});
  final QqPodcast podcast;
  final QqDiscovery? discovery;
  @override
  State<QqPodcastEpisodesView> createState() => _QqPodcastEpisodesState();
}

class _QqPodcastEpisodesState extends State<QqPodcastEpisodesView> {
  late final api = widget.discovery ?? QqDiscovery(QqMusic.instance);
  final cancel = CancelToken();
  final tracks = <MediaItem>[];
  int page = 1;
  bool busy = false, more = true;
  Object? error;
  Future<void> load() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await api.podcastEpisodes(widget.podcast,
          page: page, cancelToken: cancel);
      if (!mounted) return;
      final ids = tracks.map((s) => s.id).toSet();
      setState(() {
        tracks.addAll(result.where((s) => ids.add(s.id)));
        page++;
        more = result.length >= 50;
      });
    } catch (e) {
      if (mounted) setState(() => error = e);
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
  void dispose() {
    cancel.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text(widget.podcast.name,
              maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
          top: false,
          child: Column(children: [
            if (busy) const LinearProgressIndicator(),
            Expanded(
                child: tracks.isEmpty
                    ? error != null
                        ? _retry(error, load)
                        : Center(child: Text(busy ? '正在加载…' : '暂无节目'))
                    : buildSongCollection(context,
                        songs: tracks,
                        storageId: 'qq:podcast:${widget.podcast.id}',
                        showArtwork: true,
                        onPlay: (index) => Home.to.playByIndex(
                            index, widget.podcast.name,
                            mediaItem: tracks))),
            if (error != null && tracks.isNotEmpty)
              TextButton(onPressed: load, child: const Text('加载失败，重试')),
            if (more && !busy && tracks.isNotEmpty && error == null)
              TextButton(onPressed: load, child: const Text('加载更多')),
          ])));
}
