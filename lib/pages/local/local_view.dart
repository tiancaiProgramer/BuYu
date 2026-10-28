import 'package:auto_route/auto_route.dart';
import 'package:bujuan/routes/router.gr.dart';
import 'package:bujuan/widget/data_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../routes/router.dart';
import '../../widget/app_bar.dart';
import '../../widget/landscape_cards.dart';
import '../../widget/simple_extended_image.dart';
import '../home/home_controller.dart';
import 'local_controller.dart';
import '../downloads/downloads_view.dart';

class LocalView extends StatefulWidget {
  const LocalView({super.key});

  @override
  State<LocalView> createState() => _LocalViewState();
}

class _LocalViewState extends State<LocalView> {
  Local get controller => Get.find<Local>();
  bool _openingCache = false;

  @override
  Widget build(BuildContext context) {
    controller.context = context;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: MyAppBar(
        backgroundColor: Colors.transparent,
        leadingWidth: phoneLandscape(context) ? 68 : null,
        leading: IconButton(
            key: const ValueKey('local-account-avatar'),
            onPressed: () {
              if (Home.to.hasMusicAccount) {
                Home.to.myDrawerController.open!();
                return;
              }
              AutoRouter.of(context).pushNamed(Routes.login);
            },
            icon: Obx(() => SimpleExtendedImage.avatar(
                  Home.to.displayAvatarUrl,
                  width: 80.w,
                ))),
        title: RichText(
            text: TextSpan(
                style: TextStyle(
                    fontSize: 36.sp,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold),
                text: 'Here  ',
                children: [
              TextSpan(
                  text: '本地音乐～',
                  style: TextStyle(
                      color: Theme.of(context).primaryColor.withOpacity(.9))),
            ])),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.w),
        child: Obx(() => Visibility(
              visible: !controller.loading.value,
              replacement: const LoadingView(),
              child: phoneLandscape(context)
                  ? _buildLandscape(context)
                  : Column(
                      children: [
                        _buildTopWidget('本地SDCard歌曲',
                            'assets/images/local_song.svg', context,
                            onTap: () => context.router.push(
                                const LocalSongView().copyWith(
                                    queryParams: {'id': 0, 'type': 'all'}))),
                        _buildTopWidget('网易云缓存歌曲',
                            'assets/images/netease_cache.svg', context,
                            onTap: () => _openCache(context)),
                        ListTile(
                            leading: const Icon(Icons.download_outlined),
                            title: const Text('下载管理'),
                            onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => const DownloadsView()))),
                        _buildHeader('本地歌手', context,
                            onTap: () => context.router
                                .push(LocalAr(artists: controller.artistsAll))),
                        _buildArtists(),
                        _buildHeader('本地专辑', context,
                            onTap: () => context.router.push(
                                LocalAlbum(albums: controller.albumsAll))),
                        _buildAlbum()
                      ],
                    ),
            )),
      ),
    );
  }

  Future<void> _openCache(BuildContext context) async {
    if (_openingCache) return;
    _openingCache = true;
    void message(String text) {
      if (!mounted || !context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(text),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
                label: '重新授权', onPressed: () => _openCache(context))));
    }

    try {
      final sdk = await const MethodChannel('bujuan/downloads')
          .invokeMethod<int>('sdk');
      if (sdk == null) throw StateError('Storage access is unavailable');
      final permission =
          sdk >= 30 ? Permission.manageExternalStorage : Permission.storage;
      if (!await permission.isGranted) {
        if (!mounted || !context.mounted) return;
        final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialog) => AlertDialog(
                    scrollable: true,
                    title: const Text('读取网易云缓存'),
                    content: Text(sdk >= 30
                        ? '读取共享存储中的网易云缓存，需要在系统设置中开启 BuYu 的“所有文件访问权限”。开启后返回本页即可继续。\n\n普通歌曲下载和播放不需要此权限；部分受系统保护的缓存目录仍可能无法读取。'
                        : '读取网易云缓存需要文件读取权限。授权后即可继续，取消不会影响在线播放。'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialog, false),
                          child: const Text('暂不开启')),
                      TextButton(
                          onPressed: () => Navigator.pop(dialog, true),
                          child: Text(sdk >= 30 ? '前往授权' : '允许读取')),
                    ]));
        if (confirmed != true || !mounted || !context.mounted) return;
        await permission.request();
        if (!mounted || !context.mounted) return;
        // Special permission settings can return without enabling access.
        // Read the current state again instead of treating the return as consent.
        if (!await permission.isGranted) {
          message('尚未开启文件访问权限，暂时无法读取网易云缓存');
          return;
        }
      }
      if (mounted && context.mounted) {
        await context.router.push(const NeteaseCacheView());
      }
    } catch (_) {
      message('无法完成文件访问授权，请检查系统设置后重试');
    } finally {
      _openingCache = false;
    }
  }

  Widget _buildLandscape(BuildContext context) => Column(children: [
        GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: landscapeCardGrid,
            children: [
              LandscapeCard(
                  title: '下载管理',
                  artwork: const Icon(Icons.download_outlined, size: 32),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const DownloadsView()))),
              LandscapeCard(
                  title: '本地SDCard歌曲',
                  artwork: SvgPicture.asset('assets/images/local_song.svg'),
                  onTap: () => context.router.push(const LocalSongView()
                      .copyWith(queryParams: {'id': 0, 'type': 'all'}))),
              LandscapeCard(
                  title: '网易云缓存歌曲',
                  artwork: SvgPicture.asset('assets/images/netease_cache.svg'),
                  onTap: () => _openCache(context)),
              LandscapeCard(
                  title: '本地歌手',
                  subtitle: '${controller.artistsAll.length} 位',
                  artwork: const Icon(Icons.person_outline, size: 32),
                  onTap: () => context.router
                      .push(LocalAr(artists: controller.artistsAll))),
              LandscapeCard(
                  title: '本地专辑',
                  subtitle: '${controller.albumsAll.length} 张',
                  artwork: const Icon(Icons.album_outlined, size: 32),
                  onTap: () => context.router
                      .push(LocalAlbum(albums: controller.albumsAll))),
            ]),
        _buildHeader('本地歌手', context,
            onTap: () =>
                context.router.push(LocalAr(artists: controller.artistsAll))),
        GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: landscapeCardGrid,
            itemCount: controller.artists.length,
            itemBuilder: (_, index) {
              final artist = controller.artists[index];
              return LandscapeCard(
                  title: artist.artist,
                  image:
                      '${controller.directory?.path}/artists/${artist.id}.jpeg',
                  onTap: () => context.router.push(const LocalSongView()
                      .copyWith(
                          queryParams: {'id': artist.id, 'type': 'artist'})));
            }),
        _buildHeader('本地专辑', context,
            onTap: () =>
                context.router.push(LocalAlbum(albums: controller.albumsAll))),
        GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: landscapeCardGrid,
            itemCount: controller.albums.length,
            itemBuilder: (_, index) {
              final album = controller.albums[index];
              return LandscapeCard(
                  title: album.album,
                  subtitle: '${album.numOfSongs} 首 · ${album.artist ?? ''}',
                  image:
                      '${controller.directory?.path}/albums/${album.id}.jpeg',
                  onTap: () => context.router.push(const LocalSongView()
                      .copyWith(
                          queryParams: {'id': album.id, 'type': 'album'})));
            }),
      ]);

  Widget _buildHeader(String title, BuildContext context,
      {VoidCallback? onTap}) {
    return InkWell(
      child: Container(
        padding: phoneLandscape(context)
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 12)
            : EdgeInsets.symmetric(horizontal: 30.w, vertical: 30.w),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: BorderRadius.circular(6.w)),
              width: 10.w,
              height: 10.w,
            ),
            Padding(padding: EdgeInsets.symmetric(horizontal: 15.w)),
            Text(
              title,
              style: TextStyle(
                  fontSize: 34.sp, color: Theme.of(context).iconTheme.color),
            ),
            const Expanded(child: SizedBox.shrink()),
            Icon(Icons.keyboard_arrow_right_outlined,
                color: Colors.black87.withOpacity(.4))
          ],
        ),
      ),
      onTap: () => onTap?.call(),
    );
  }

  Widget _buildTopWidget(String title, String path, BuildContext context,
      {VoidCallback? onTap}) {
    return InkWell(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 25.w, vertical: 20.w),
        padding: EdgeInsets.symmetric(vertical: 30.w),
        child: Row(
          children: [
            Container(
              height: 130.w,
              width: 130.w,
              decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(.9),
                  borderRadius: BorderRadius.circular(65.w)),
              child: SvgPicture.asset(
                path,
                height: 130.w,
              ),
            ),
            Padding(padding: EdgeInsets.symmetric(horizontal: 15.w)),
            Text(
              title,
              style: TextStyle(fontSize: 34.sp),
            ),
          ],
        ),
      ),
      onTap: () => onTap?.call(),
    );
  }

  Widget _buildArtists() {
    return Obx(() => GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 1,
            crossAxisSpacing: 10.w,
          ),
          itemBuilder: (context, index) =>
              _buildItem(controller.artists[index], context, index),
          itemCount: controller.artists.length,
        ));
  }

  Widget _buildItem(ArtistModel play, BuildContext context, index) {
    return InkWell(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 14.w),
        child: Stack(
          alignment: Alignment.bottomLeft,
          children: [
            SimpleExtendedImage(
              '${controller.directory?.path}/artists/${play.id}.jpeg',
              width: (750.w - 120.w) / 3,
              borderRadius: BorderRadius.circular(25.w),
            ),
            Container(
              decoration: BoxDecoration(
                  color:
                      Theme.of(context).scaffoldBackgroundColor.withOpacity(.8),
                  borderRadius: BorderRadius.circular(25.w)),
              height: 60.w,
              width: (750.w - 120.w) / 3,
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    play.artist,
                    maxLines: 1,
                    style: TextStyle(fontSize: 26.sp),
                  ),
                  // Padding(padding: EdgeInsets.symmetric(vertical: 2.w)),
                ],
              ),
            )
          ],
        ),
      ),
      onTap: () {
        context.router.push(const LocalSongView()
            .copyWith(queryParams: {'id': play.id, 'type': 'artist'}));
      },
    );
  }

  Widget _buildAlbum() {
    return Obx(() => GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.only(left: 20.w, right: 20.w),
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 2.5,
            crossAxisSpacing: 20.w,
          ),
          itemBuilder: (context, index) =>
              _buildItem1(controller.albums[index], context, index),
          itemCount: controller.albums.length,
        ));
  }

  Widget _buildItem1(AlbumModel play, BuildContext context, int index) {
    return InkWell(
      child: SizedBox(
        height: 120.w,
        child: Row(
          children: [
            SimpleExtendedImage(
              '${controller.directory?.path}/albums/${play.id}.jpeg',
              width: 85.w,
              borderRadius: BorderRadius.circular(10.w),
            ),
            Expanded(
                child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 15.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    play.album,
                    maxLines: 1,
                    style: TextStyle(fontSize: 28.sp),
                  ),
                  Padding(padding: EdgeInsets.symmetric(vertical: 3.w)),
                  Text(
                    '${play.artist}',
                    maxLines: 1,
                    style: TextStyle(fontSize: 26.sp, color: Colors.grey),
                  )
                ],
              ),
            )),
            Text(
              '${play.numOfSongs}首',
              style: TextStyle(fontSize: 22.sp, color: Colors.grey),
            )
          ],
        ),
      ),
      onTap: () {
        context.router.push(const LocalSongView()
            .copyWith(queryParams: {'id': play.id, 'type': 'album'}));
      },
    );
  }
}

// class _LocalViewState extends State<LocalView> {
//   OnAudioQuery query = GetIt.instance<OnAudioQuery>();
//   final List<MediaItem> _items = [];
//   Directory? directory;
//   bool loading = true;
//   List<ArtistModel> artistList = [];
//   List<AlbumModel> albumList = [];
//
//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
//       directory = await getApplicationSupportDirectory();
//       bool permissionsRequest = await query.permissionsRequest();
//       if (permissionsRequest) {
//         _getAlbum();
//         _getLocalSong();
//       }
//     });
//   }
//
//   _getLocalSong() async {
//     directory = await getApplicationSupportDirectory();
//     List<SongModel> songs = await query.querySongs();
//     for (var e in songs) {
//       String path = '${directory?.path}/${e.id}.jpeg';
//       File file = File(path);
//       if (!await file.exists()) {
//         Uint8List? byteData = await query.queryArtwork(e.id, ArtworkType.AUDIO, size: 300, format: ArtworkFormat.JPEG);
//         if (byteData != null) {
//           await file.writeAsBytes(byteData);
//         } else {
//           path = '';
//         }
//       }
//       _items.add(MediaItem(
//           id: '${e.id}',
//           duration: Duration(milliseconds: e.duration ?? 0),
//           artUri: Uri.file(path),
//           displayDescription: 'local',
//           extras: {'url': e.data, 'image': path, 'liked': false, 'artist': '', 'mv': 0},
//           title: e.title,
//           album: e.album,
//           artist: e.artist));
//     }
//   }
//
//   _getAlbum() async {
//     List<ArtistModel> artists = await query.queryArtists();
//     for (var e in artists) {
//       String path = '${directory?.path}/${e.id}.jpeg';
//       File file = File(path);
//       if (!await file.exists()) {
//         Uint8List? byteData = await query.queryArtwork(e.id, ArtworkType.ARTIST, size: 200, format: ArtworkFormat.JPEG);
//         if (byteData != null) {
//           await file.writeAsBytes(byteData);
//         } else {
//           path = '';
//         }
//       }
//     }
//     if (artists.length > 3) artists = artists.sublist(0, 3);
//     artistList
//       ..clear()
//       ..addAll(artists);
//     List<AlbumModel> albums = await query.queryAlbums();
//     for (var e in albums) {
//       String path = '${directory?.path}/${e.id}.jpeg';
//       File file = File(path);
//       if (!await file.exists()) {
//         Uint8List? byteData = await query.queryArtwork(e.id, ArtworkType.ALBUM, size: 100, format: ArtworkFormat.JPEG);
//         if (byteData != null) {
//           await file.writeAsBytes(byteData);
//         } else {
//           path = '';
//         }
//       }
//     }
//     if (albums.length > 8) albums = albums.sublist(0, 8);
//     albumList
//       ..clear()
//       ..addAll(albums);
//     loading = false;
//     setState(() {});
//   }
//
//   @override
//   void dispose() {
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.transparent,
//       appBar: MyAppBar(
//         backgroundColor: Colors.transparent,
//         centerTitle: false,
//         leading: IconButton(
//             onPressed: () {
//               Home.to.myDrawerController.open!();
//             },
//             icon: Obx(() => SimpleExtendedImage.avatar(
//                   Home.to.userData.value.profile?.avatarUrl ?? '',
//                   width: 80.w,
//                 ))),
//         title: RichText(
//             text: TextSpan(style: TextStyle(fontSize: 42.sp, color: Colors.grey, fontWeight: FontWeight.bold), text: 'Here  ', children: [
//           TextSpan(text: '本地歌曲～', style: TextStyle(color: Theme.of(context).primaryColor.withOpacity(.9))),
//         ])),
//       ),
//       body: SingleChildScrollView(
//         padding: EdgeInsets.symmetric(horizontal: 10.w),
//         child: Visibility(
//           visible: !loading,
//           replacement: Visibility(
//             visible: artistList.isEmpty && !loading,
//             replacement: const LoadingView(),
//             child: const EmptyView(),
//           ),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               ListTile(
//                   contentPadding: EdgeInsets.symmetric(horizontal: 18.w),
//                   leading:  Icon(TablerIcons.list_details,color: Theme.of(context).cardColor,),
//                   trailing: const Icon(TablerIcons.chevron_right),
//                   title: const Text('全部单曲',style: TextStyle(fontWeight: FontWeight.bold),),
//                   onTap: () {
//                     context.router.push(const NeteaseCacheView());
//                   }),
//               _buildHeader('艺术家', context),
//               _buildArtists(),
//               _buildHeader('专辑', context),
//               _buildAlbum(),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
//
//   Widget _buildArtists() {
//     return SizedBox(
//       height: (750.w - 120.w) / 3,
//       child: ListView.builder(
//         shrinkWrap: true,
//         padding: const EdgeInsets.all(0),
//         scrollDirection: Axis.horizontal,
//         itemBuilder: (c, i) => _buildItem(artistList[i], c, i),
//         itemCount: artistList.length,
//       ),
//     );
//   }
//
//   Widget _buildItem(ArtistModel play, BuildContext context, index) {
//     return InkWell(
//       child: Container(
//         margin: EdgeInsets.symmetric(horizontal: 14.w),
//         height: (750.w - 120.w) / 3,
//         child: Stack(
//           alignment: Alignment.bottomLeft,
//           children: [
//             SimpleExtendedImage(
//               '${directory?.path}/${play.id}.jpeg',
//               width: (750.w - 120.w) / 3,
//               borderRadius: BorderRadius.circular(25.w),
//             ),
//             Container(
//               height: 60.w,
//               width: (750.w - 120.w) / 3,
//               color: Theme.of(context).bottomAppBarColor.withOpacity(.8),
//               padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.w),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   Text(
//                     play.artist,
//                     maxLines: 1,
//                     style: TextStyle(fontSize: 26.sp),
//                   ),
//                   // Padding(padding: EdgeInsets.symmetric(vertical: 2.w)),
//                 ],
//               ),
//             )
//           ],
//         ),
//       ),
//       onTap: () {
//         context.router.push(const LocalSongView().copyWith(queryParams: {'id': play.id, 'type': 'artist'}));
//       },
//     );
//   }
//
//   Widget _buildAlbum() {
//     return GridView.builder(
//       shrinkWrap: true,
//       padding: EdgeInsets.only(left: 20.w, right: 20.w),
//       physics: const NeverScrollableScrollPhysics(),
//       gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
//         crossAxisCount: 2,
//         childAspectRatio: 2.5,
//         crossAxisSpacing: 20.w,
//       ),
//       itemBuilder: (context, index) => _buildItem1(albumList[index], context, index),
//       itemCount: albumList.length,
//     );
//   }
//
//   Widget _buildItem1(AlbumModel play, BuildContext context, int index) {
//     return InkWell(
//       child: SizedBox(
//         height: 120.w,
//         child: Row(
//           children: [
//             SimpleExtendedImage(
//               '${directory?.path}/${play.id}.jpeg',
//               width: 85.w,
//               borderRadius: BorderRadius.circular(10.w),
//             ),
//             Expanded(
//                 child: Padding(
//                   padding: EdgeInsets.symmetric(horizontal: 15.w),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: [
//                       Text(
//                         play.album ?? '',
//                         maxLines: 1,
//                         style: TextStyle(fontSize: 28.sp),
//                       ),
//                       Padding(padding: EdgeInsets.symmetric(vertical: 3.w)),
//                       Text(
//                         '${play.artist}',
//                         maxLines: 1,
//                         style: TextStyle(fontSize: 26.sp, color: Colors.grey),
//                       )
//                     ],
//                   ),
//                 )),
//             Text(
//               '${play.numOfSongs}首',
//               style: TextStyle(fontSize: 22.sp, color: Colors.grey),
//             )
//           ],
//         ),
//       ),
//       onTap: () {
//         context.router.push(const LocalSongView().copyWith(queryParams: {'id': play.id, 'type': 'album'}));
//       },
//     );
//   }
//
//   Widget _buildHeader(String title, context) {
//     return Container(
//       padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 30.w),
//       alignment: Alignment.centerLeft,
//       child: Row(
//         children: [
//           Container(
//             decoration: BoxDecoration(color: Theme.of(context).primaryColor, borderRadius: BorderRadius.circular(6.w)),
//             width: 10.w,
//             height: 10.w,
//           ),
//           Padding(padding: EdgeInsets.symmetric(horizontal: 6.w)),
//           Expanded(
//               child: Text(
//                 title,
//                 style: TextStyle(fontSize: 32.sp, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyText1?.color?.withOpacity(.8)),
//               )),
//           const Icon(TablerIcons.chevron_right)
//         ],
//       ),
//     );
//   }
// }
