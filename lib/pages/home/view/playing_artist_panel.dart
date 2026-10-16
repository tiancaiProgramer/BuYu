// Community maintenance and new features: tiancaiProgramer.
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import '../../../common/song_artists.dart';
import '../../../common/netease_api/src/netease_api.dart';
import '../../../common/netease_api/src/api/play/bean.dart';
import '../../../widget/landscape_cards.dart';
import '../../../widget/simple_extended_image.dart';
import '../../../widget/download_song_button.dart';
import '../../play_list/playlist_view.dart';
import '../home_controller.dart';

typedef ArtistLoader = Future<Artists> Function(Artists artist);
typedef ArtistSongsLoader = Future<List<MediaItem>> Function(Artists artist);
class PlayingArtistPanel extends StatefulWidget {
  const PlayingArtistPanel({super.key, required this.song, required this.onOpen, this.artistLoader, this.songsLoader});
  final MediaItem song;
  final void Function(Artists) onOpen;
  final ArtistLoader? artistLoader;
  final ArtistSongsLoader? songsLoader;
  @override
  State<PlayingArtistPanel> createState() => _PlayingArtistPanelState();
}
class _PlayingArtistPanelState extends State<PlayingArtistPanel> {
  late List<Artists> artists;
  late List<Future<Artists>> details;
  Future<List<MediaItem>>? songs;
  static Future<Artists> resolve(Artists artist) async {
    if ((int.tryParse(artist.id) ?? 0) > 0) return artist;
    final response = await NeteaseMusicApi().searchArtists(artist.name ?? '');
    return response.result.artists.firstWhere((a) => a.name == artist.name);
  }
  static Future<Artists> loadArtist(Artists artist) async {
    artist = await resolve(artist);
    return (await NeteaseMusicApi().artistDetail(artist.id)).data?.artist ?? artist;
  }
  static Future<List<MediaItem>> loadSongs(Artists artist) async {
    artist = await resolve(artist);
    return Home.to.song2ToMedia((await NeteaseMusicApi().artistTopSongList(artist.id)).songs ?? []);
  }
  void load() {
    artists = SongArtists.fromSong(widget.song);
    details = artists.map((a) => (widget.artistLoader ?? loadArtist)(a).timeout(const Duration(seconds: 10)).catchError((_) => a)).toList();
    songs = artists.isEmpty ? null : (widget.songsLoader ?? loadSongs)(artists.first).timeout(const Duration(seconds: 10));
  }
  @override
  void initState() { super.initState(); load(); }
  @override
  void didUpdateWidget(PlayingArtistPanel old) {
    super.didUpdateWidget(old);
    if (old.song.id != widget.song.id || old.song.extras?['artist'] != widget.song.extras?['artist']) load();
  }
  Widget artist(int index) => FutureBuilder<Artists>(future: details[index], initialData: artists[index], builder: (context, snapshot) {
    final artist = snapshot.data ?? artists[index];
    return SizedBox(height: 92, child: LandscapeCard(title: artist.name ?? artists[index].name ?? '',
        artwork: ClipOval(child: SimpleExtendedImage(artist.cover ?? artist.picUrl ?? artist.img1v1Url ?? '', width: 56, height: 56,
            replacement: const Icon(Icons.person_outline, size: 32))), onTap: () => widget.onOpen(artist)));
  });
  Widget recommendations(bool wide) {
    if (songs == null) return const Center(child: Text('当前歌曲暂无歌手信息'));
    return FutureBuilder<List<MediaItem>>(future: songs, builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: TextButton(onPressed: () => setState(load), child: const Text('歌手歌曲加载失败，点击重试')));
      final items = snapshot.data ?? [];
      if (items.isEmpty) return const Center(child: Text('暂无歌手歌曲推荐'));
      return GridView.builder(key: const PageStorageKey('artist-recommended-songs'),
          shrinkWrap: !wide, physics: wide ? null : const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: wide ? 2 : 1, mainAxisExtent: 78, crossAxisSpacing: 12, mainAxisSpacing: 8),
          itemCount: items.length, itemBuilder: (context, index) => LandscapeCardSurface(child: SongItem(index: index, mediaItem: items[index], showArtwork: true,
              onTap: () => Home.to.playByIndex(index, '歌手推荐', mediaItem: items))));
    });
  }
  @override
  Widget build(BuildContext context) {
    final wide = phoneLandscape(context);
    final header = Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('歌手', style: TextStyle(fontSize: 18, color: Theme.of(context).textTheme.bodyMedium?.color, fontWeight: FontWeight.bold)));
    final heading = Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('歌手歌曲推荐', style: TextStyle(fontSize: 17, color: Theme.of(context).textTheme.bodyMedium?.color, fontWeight: FontWeight.w600)));
    final profile = [header, for (var i = 0; i < artists.length; i++) Padding(padding: const EdgeInsets.only(bottom: 8), child: artist(i)), DownloadSongButton(song: widget.song)];
    return DefaultTextStyle.merge(style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: wide
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 190, child: ListView(children: profile)), const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [heading, Expanded(child: recommendations(true))])),
          ])
        : ListView(children: [...profile, heading, recommendations(false)])));
  }
}
