
import 'package:audio_service/audio_service.dart';
import 'package:auto_route/auto_route.dart';
import 'package:bujuan/common/netease_api/src/api/play/bean.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/pages/play_list/playlist_view.dart';
import 'package:bujuan/widget/my_get_view.dart';
import 'package:bujuan/widget/request_widget/request_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../common/netease_api/src/dio_ext.dart';
import '../../common/netease_api/src/netease_handler.dart';
import '../../widget/app_bar.dart';
import '../../widget/request_widget/request_loadmore_view.dart';
import '../../widget/simple_extended_image.dart';
import '../../widget/landscape_cards.dart';
import '../../widget/song_collection.dart';
import '../../routes/router.gr.dart' as routes;

class ArtistsView extends StatefulWidget {
  const ArtistsView({Key? key, this.artist}) : super(key: key);
  final Artists? artist;

  @override
  State<ArtistsView> createState() => _ArtistsViewState();
}

class _ArtistsViewState extends State<ArtistsView>
    with SingleTickerProviderStateMixin {
  Artists? artists;
  final List<MediaItem> _items = [];
  final List<Tab> _tabs = [
    const Tab(text: '详情'),
    const Tab(text: '单曲'),
    const Tab(text: '专辑'),
  ];
  TabController? _tabController;

  DioMetaData artistDetailDioMetaData(String artistId) {
    var params = {'id': artistId};
    return DioMetaData(joinUri('/api/artist/head/info/get'),
        data: params, options: joinOptions());
  }

  DioMetaData artistTopSongListDioMetaData(String artistId) {
    var params = {'id': artistId};
    return DioMetaData(joinUri('/api/artist/top/song'),
        data: params, options: joinOptions());
  }

  DioMetaData artistAlbumListDioMetaData(String artistId,
      {int offset = 0, int limit = 30, bool total = true}) {
    var params = {'total': total, 'limit': limit, 'offset': offset};
    return DioMetaData(joinUri('/weapi/artist/albums/$artistId'),
        data: params, options: joinOptions());
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    artists ??= widget.artist ?? (context.routeData.args as Artists);
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MyGetView(
        child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: MyAppBar(
        backgroundColor: Colors.transparent,
        title: Text(artists?.name ?? ''),
        bottom: TabBar(
          tabs: _tabs,
          controller: _tabController,
          labelColor: Theme.of(context).primaryColor,
          unselectedLabelColor: Theme.of(context).iconTheme.color,
          indicatorSize: TabBarIndicatorSize.label,
          indicatorColor: Theme.of(context).primaryColor,
          indicatorPadding: EdgeInsets.symmetric(horizontal: 15.w, vertical: 0),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildDetails(), _buildSongList(), _buildAlbumView()],
      ),
    ));
  }

  Widget _buildDetails() {
    return RequestWidget<ArtistDetailWrap>(
        dioMetaData: artistDetailDioMetaData(artists?.id ?? '-1'),
        childBuilder: (artistDetails) {
          return ArtistDetailBody(
              artist: artistDetails.data?.artist ?? artists!);
        });
  }

  Widget _buildSongList() {
    return RequestWidget<ArtistSongListWrap>(
        dioMetaData: artistTopSongListDioMetaData(artists?.id ?? '-1'),
        childBuilder: (artistDetails) {
          _items
            ..clear()
            ..addAll(Home.to.song2ToMedia(artistDetails.songs ?? []));
          return buildSongCollection(context,
              songs: _items,
              showArtwork: true,
              storageId: 'artist-songs:${artists!.id}',
              onPlay: (index) => Home.to.playByIndex(index, 'queueTitle',
                  mediaItem: List.of(_items)));
        });
  }

  Widget _buildAlbumView() {
    return RequestLoadMoreWidget<ArtistAlbumListWrap, Album>(
      dioMetaData: artistAlbumListDioMetaData(artists?.id ?? '-1'),
      pageSize: 30,
      childBuilder: (List<Album> playlist) {
        if (phoneLandscape(context))
          return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: landscapeCardGrid,
              itemCount: playlist.length,
              itemBuilder: (context, index) {
                final album = playlist[index];
                return LandscapeCard(
                    title: album.name ?? '',
                    subtitle: '${album.size ?? 0} 首',
                    image: album.picUrl ?? '',
                    onTap: () {
                      context.router.push(
                          const routes.AlbumDetails().copyWith(args: album));
                    });
              });
        return ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          itemExtent: 130.w,
          itemBuilder: (context, index) =>
              AlbumItem(index: index, album: playlist[index]),
          itemCount: playlist.length,
        );
      },
      listKey: const ['hotAlbums'],
    );
  }
}

class ArtistDetailBody extends StatelessWidget {
  const ArtistDetailBody({super.key, required this.artist});
  final Artists artist;
  @override
  Widget build(BuildContext context) {
    final wide = phoneLandscape(context);
    final info = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(artist.name ?? '',
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(spacing: 20, runSpacing: 8, children: [
            Text('${artist.albumSize ?? 0} 专辑'),
            Text('${artist.musicSize ?? 0} 单曲'),
            Text('${artist.mvSize ?? 0} MV')
          ]),
          const SizedBox(height: 16),
          Text((artist.briefDesc ?? '').isEmpty ? '暂无歌手简介' : artist.briefDesc!,
              style: const TextStyle(fontSize: 15, height: 1.6)),
        ]);
    final image = SimpleExtendedImage.avatar(
        artist.cover ?? artist.picUrl ?? artist.img1v1Url ?? '',
        width: wide ? 150 : 120,
        height: wide ? 150 : 120);
    return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                image,
                const SizedBox(width: 24),
                Expanded(child: info)
              ])
            : Column(children: [image, const SizedBox(height: 20), info]));
  }
}
