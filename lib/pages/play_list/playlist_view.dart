import '../../widget/landscape_cards.dart';
import '../../widget/download_song_button.dart';
import '../../widget/adaptive_option_sheet.dart';
import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:audio_service/audio_service.dart';
import 'package:auto_route/auto_route.dart';
import 'package:bujuan/common/constants/other.dart';
import 'package:bujuan/common/netease_api/netease_music_api.dart';
import 'package:bujuan/pages/play_list/playlist_controller.dart';
import 'package:bujuan/routes/router.gr.dart' as gr;
import 'package:bujuan/widget/custom_filed.dart';
import 'package:bujuan/widget/data_widget.dart';
import 'package:bujuan/widget/my_get_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:get/get.dart';

import '../../widget/app_bar.dart';
import '../../widget/simple_extended_image.dart';
import 'package:bujuan/common/constants/enmu.dart' as type;
import '../home/home_controller.dart';

class PlayListView extends GetView<PlayListController> {
  const PlayListView({super.key});

  @override
  Widget build(BuildContext context) {
    controller.context = context;
    return Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: MyGetView(
            child: Obx(
          () => Visibility(
            visible: !controller.loading.value,
            replacement: const LoadingView(),
            child: CustomScrollView(
              slivers: [
                MySliverAppBar(
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor.withOpacity(Home.to.background.value.isEmpty ? 1 : 0),
                  pinned: true,
                  leading: IconButton(
                      padding: EdgeInsets.only(left: 20.w),
                      onPressed: () => AutoRouter.of(context).pop(),
                      icon: SimpleExtendedImage.avatar(
                        '${(context.routeData.args as Play).picUrl ?? (context.routeData.args as Play).coverImgUrl}?param=100y100',
                        width: 75.w,
                        height: 75.w,
                      )),
                  title: Obx(() => Visibility(
                        visible: !controller.search.value,
                        replacement: CustomFiled(
                          textEditingController: controller.textEditingController,
                          autoFocus: true,
                          hitText: '请输入关键字',
                        ),
                        child: Text((context.routeData.args as Play).name ?? ''),
                        // child: AutoSizeText(
                        //   (context.routeData.args as Play).name ?? '',
                        //   maxLines: 1,
                        // ),
                      )),
                  actions: [
                    IconButton(
                        onPressed: () {
                          controller.search.value = !controller.search.value;
                          if (!controller.search.value) controller.textEditingController.text = '';
                        },
                        icon: Obx(() => Icon(!controller.search.value ? TablerIcons.search : TablerIcons.x)))
                  ],
                ),
                _buildTopItem(context),
                Obx(() {
                  final songs = controller.isSearch.value ? controller.searchItems : controller.mediaItems;
                  Widget item(BuildContext context, int index) => SongItem(
                      index: index, mediaItem: songs[index],
                      showArtwork: phoneLandscape(context),
                      onTap: () => Home.to.playByIndex(index, 'queueTitle', mediaItem: List.of(songs)));
                  if (phoneLandscape(context)) {
                    return SliverPadding(padding: const EdgeInsets.all(12), sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3, mainAxisExtent: 112 * 2 / 3,
                            mainAxisSpacing: 8, crossAxisSpacing: 10),
                        delegate: SliverChildBuilderDelegate((context, index) =>
                            LandscapeCardSurface(child: item(context, index)), childCount: songs.length)));
                  }
                  return SliverFixedExtentList(itemExtent: 130.w,
                      delegate: SliverChildBuilderDelegate(item, childCount: songs.length,
                          addAutomaticKeepAlives: false, addRepaintBoundaries: false));
                })
              ],
            ),
          ),
        )));
  }

  Widget _buildTopItem(BuildContext context) {
    return SliverToBoxAdapter(
      child: Container(
        margin: EdgeInsets.only(left: 20.w, right: 20.w, bottom: 10.w),
        padding: EdgeInsets.only(left: 15.w, right: 15.w, top: 10.w, bottom: 25.w),
        alignment: Alignment.center,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                    onPressed: () {},
                    icon: SimpleExtendedImage.avatar(
                      '${(context.routeData.args as Play).creator?.avatarUrl ?? ''}?param=80y80',
                      width: 80.w,
                    )),
                Expanded(
                  child: Text(
                    (context.routeData.args as Play).creator?.nickname ?? '',
                    style: TextStyle(fontSize: 28.sp),
                  ),
                ),
                IconButton(onPressed: () => controller.subscribePlayList(), icon: Obx(() => Icon(controller.sub.value ? TablerIcons.hearts : TablerIcons.heart))),
                IconButton(
                    onPressed: () {
                      context.router.push(const gr.TalkView()
                          .copyWith(queryParams: {'id': (context.routeData.args as Play).id, 'type': 'playlist', 'name': (context.routeData.args as Play).name}));
                    },
                    icon: const Icon(TablerIcons.message_2)),
              ],
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Text(
                ((context.routeData.args as Play).description ?? '暂无描述').replaceAll('\n', ''),
                maxLines: phoneLandscape(context) ? 2 : 5,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 24.sp, height: 1.6, color: Theme.of(context).cardColor.withOpacity(.6)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SongItem extends StatelessWidget {
  final int index;
  final MediaItem mediaItem;
  final VoidCallback? onTap;
  final bool showArtwork;

  const SongItem({Key? key, required this.index, required this.mediaItem, this.onTap, this.showArtwork = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    List<SheetAction<ActionType>> sheet = [const SheetAction<ActionType>(label: '下一首播放', icon: TablerIcons.player_play, key: ActionType.next)];
    if (mediaItem.extras?['type'] == type.MediaType.local.name) {
      sheet.add(const SheetAction<ActionType>(label: '修改歌曲标签', icon: TablerIcons.edit, key: ActionType.edit));
    } else {
      sheet.add(const SheetAction<ActionType>(label: '查看歌曲评论', icon: TablerIcons.message_2, key: ActionType.talk));
    }
    if (mediaItem.extras?['type'] != type.MediaType.local.name) {
      sheet.add(const SheetAction<ActionType>(label: '下载歌曲', icon: TablerIcons.download, key: ActionType.download));
    }
    return ListTile(
      visualDensity: VisualDensity.compact,
      leading: showArtwork
          ? SimpleExtendedImage('${mediaItem.extras?['image'] ?? ''}?param=120y120',
              width: 85.w, height: 85.w, cacheWidth: 256,
              borderRadius: BorderRadius.circular(8))
          : Text('${index + 1}'),
      horizontalTitleGap: showArtwork ? 10 : 0.w,
      title: Text(
        mediaItem.title,
        maxLines: 1,
      ),
      subtitle: Text(
        mediaItem.artist ?? '',
        maxLines: 1,
      ),
      trailing: IconButton(
          onPressed: () {
            showSongActions(
              context: context,
              title: mediaItem.title,
              message: mediaItem.artist,
              actions: sheet,
            ).then((value) {
              if (value != null) {
                switch (value) {
                  case ActionType.download:
                    downloadSong(context, mediaItem);
                    break;
                  case ActionType.next:
                    if (Home.to.audioServeHandler.playbackState.value.queueIndex != null) {
                      Home.to.audioServeHandler.insertQueueItem(Home.to.audioServeHandler.playbackState.value.queueIndex! + 1, mediaItem);
                      WidgetUtil.showToast('已添加到下一曲');
                    } else {
                      WidgetUtil.showToast('未知错误');
                    }
                    break;
                  case ActionType.edit:
                    context.router.push(const gr.EditSongView().copyWith(args: mediaItem));
                    break;
                  case ActionType.talk:
                    context.router.push(const gr.TalkView().copyWith(queryParams: {'id': mediaItem.id, 'type': 'song', 'name': mediaItem.title}));
                    break;
                }
              }
            });
          },
          icon: const Icon(
            TablerIcons.dots_vertical,
          )),
      onTap: () => onTap?.call(),
    );
  }

  getSongFeeType(int fee) {
    String feeStr = '';
    switch (fee) {
      case 1:
        feeStr = '  vip';
        break;
      case 4:
        feeStr = '  need buy';
        break;
    }
    return feeStr;
  }
}

class SongItemShowImage extends StatelessWidget {
  final int index;
  final MediaItem mediaItem;
  final VoidCallback? onTap;

  const SongItemShowImage({Key? key, required this.index, required this.mediaItem, this.onTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    List<SheetAction<ActionType>> sheet = [const SheetAction<ActionType>(label: '下一首播放', icon: TablerIcons.player_play, key: ActionType.next)];
    if (mediaItem.extras?['type'] == type.MediaType.local.name) {
      sheet.add(const SheetAction<ActionType>(label: '修改歌曲标签', icon: TablerIcons.edit, key: ActionType.edit));
    } else {
      sheet.add(const SheetAction<ActionType>(label: '查看歌曲评论', icon: TablerIcons.message_2, key: ActionType.talk));
    }
    if (mediaItem.extras?['type'] != type.MediaType.local.name) {
      sheet.add(const SheetAction<ActionType>(label: '下载歌曲', icon: TablerIcons.download, key: ActionType.download));
    }
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 10.w),
      leading: SimpleExtendedImage.avatar(
        '${mediaItem.extras?['image'] ?? ''}?param=120y120',
        width: 85.w,
        height: 85.w,
        fit: BoxFit.cover,
      ),
      title: RichText(
          maxLines: phoneLandscape(context) ? 2 : null,
          overflow: phoneLandscape(context) ? TextOverflow.ellipsis : TextOverflow.clip,
          text: TextSpan(text: mediaItem.title, style: TextStyle(fontSize: 30.sp, color: Theme.of(context).cardColor), children: [
        TextSpan(text: mediaItem.extras?['fee'] == 1 ? '   vip' : '', style: TextStyle(color: Theme.of(context).primaryColor.withOpacity(.9), fontSize: 26.sp)),
      ])),
      subtitle: Text(
        mediaItem.artist ?? '',
        maxLines: 1,
      ),
      trailing: IconButton(
          onPressed: () {
            showSongActions(
              context: context,
              title: mediaItem.title,
              message: mediaItem.artist,
              actions: sheet,
            ).then((value) {
              if (value != null) {
                switch (value) {
                  case ActionType.download:
                    downloadSong(context, mediaItem);
                    break;
                  case ActionType.next:
                    if (Home.to.audioServeHandler.playbackState.value.queueIndex != null) {
                      Home.to.audioServeHandler.insertQueueItem(Home.to.audioServeHandler.playbackState.value.queueIndex! + 1, mediaItem);
                      WidgetUtil.showToast('已添加到下一曲');
                    } else {
                      WidgetUtil.showToast('未知错误');
                    }
                    break;
                  case ActionType.edit:
                    context.router.push(const gr.EditSongView().copyWith(args: mediaItem));
                    break;
                  case ActionType.talk:
                    context.router.push(const gr.TalkView().copyWith(queryParams: {'id': mediaItem.id, 'type': 'song', 'name': mediaItem.title}));
                    break;
                }
              }
            });
          },
          icon: const Icon(
            TablerIcons.dots_vertical,
          )),
      onTap: () => onTap?.call(),
    );
  }
}

class AlbumItem extends StatelessWidget {
  final int index;
  final Album album;

  const AlbumItem({Key? key, required this.index, required this.album}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.symmetric(horizontal: 10.w),
      leading: SimpleExtendedImage.avatar(
        '${album.picUrl ?? ''}?param=100y100',
        width: 85.w,
        height: 85.w,
      ),
      title: Text(
        album.name ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${album.size} 单曲',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        context.router.push(const gr.AlbumDetails().copyWith(queryParams: {'album': album}));
      },
    );
  }
}

class PlayListItem extends StatelessWidget {
  final Play play;

  const PlayListItem({Key? key, required this.play}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.symmetric(horizontal: 10.w),
      leading: SimpleExtendedImage.avatar(
        '${play.coverImgUrl ?? ''}?param=300y300',
        width: 85.w,
        height: 85.w,
      ),
      title: Text(
        play.name ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${play.trackCount} 单曲',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        context.router.push(const gr.PlayListView().copyWith(args: play));
      },
    );
  }
}

// Artists
class ArtistsItem extends StatelessWidget {
  final int index;
  final Artists artists;

  const ArtistsItem({Key? key, required this.index, required this.artists}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.symmetric(horizontal: 10.w),
      leading: SimpleExtendedImage.avatar(
        '${artists.picUrl ?? ''}?param=100y100',
        width: 85.w,
        height: 85.w,
      ),
      title: Text(
        artists.name ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${artists.albumSize ?? 0} 专辑',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        context.router.push(gr.ArtistsView(artist: artists));
      },
    );
  }
}

enum ActionType { next, edit, talk, download }

Future<ActionType?> showSongActions({required BuildContext context, required String title,
    String? message, required List<SheetAction<ActionType>> actions}) =>
    showModalBottomSheet<ActionType>(context: context, isScrollControlled: true,
        builder: (sheet) => AdaptiveOptionSheet(title: title, children: [
          for (final action in actions) ListTile(title: Text(action.label),
              leading: action.icon == null ? null : Icon(action.icon),
              onTap: () => Navigator.pop(sheet, action.key)),
        ], footer: Text(message ?? '')));
