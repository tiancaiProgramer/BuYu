// Community maintenance and new features: tiancaiProgramer.
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import '../../common/music/qq_music.dart';
import '../../widget/landscape_cards.dart';
import '../../widget/simple_extended_image.dart';
import '../home/home_controller.dart';
import '../play_list/playlist_view.dart';

class QqArtistView extends StatefulWidget {
  const QqArtistView({super.key, required this.song});
  final MediaItem song;
  @override
  State<QqArtistView> createState() => _QqArtistViewState();
}

class _QqArtistViewState extends State<QqArtistView> {
  late Future<List<MediaItem>> songs;
  void load() {
    songs = QqMusic.instance
        .search(widget.song.artist?.split(' / ').first ?? widget.song.title);
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(QqArtistView old) {
    super.didUpdateWidget(old);
    if (old.song.artist != widget.song.artist) load();
  }

  @override
  Widget build(BuildContext context) {
    final artists = (widget.song.extras?['qqArtists'] as List? ?? [])
        .whereType<Map>()
        .toList();
    return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 12, runSpacing: 8, children: [
            for (final artist in artists)
              Row(mainAxisSize: MainAxisSize.min, children: [
                SimpleExtendedImage.avatar(
                    'https://y.gtimg.cn/music/photo_new/T001R150x150M000${artist['mid']}.jpg',
                    width: 42,
                    height: 42),
                const SizedBox(width: 8),
                Text('${artist['name']}'),
              ])
          ]),
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('QQ音乐 · 歌手相关歌曲')),
          Expanded(
              child: FutureBuilder<List<MediaItem>>(
                  future: songs,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done)
                      return const Center(child: CircularProgressIndicator());
                    if (snapshot.hasError)
                      return Center(
                          child: TextButton(
                              onPressed: () => setState(load),
                              child: const Text('加载失败，重试')));
                    final items = snapshot.data ?? [];
                    return GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: phoneLandscape(context) ? 2 : 1,
                            mainAxisExtent: 78),
                        itemCount: items.length,
                        itemBuilder: (context, index) => SongItem(
                            index: index,
                            mediaItem: items[index],
                            showArtwork: true,
                            onTap: () => Home.to.playByIndex(index, 'QQ歌手相关歌曲',
                                mediaItem: items)));
                  })),
        ]));
  }
}
