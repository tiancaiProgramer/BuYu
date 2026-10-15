import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/pages/index/cound_controller.dart';
import 'package:bujuan/widget/my_get_view.dart';
import 'package:bujuan/widget/request_widget/request_loadmore_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../common/netease_api/src/api/play/bean.dart';
import '../../widget/app_bar.dart';
import '../../widget/song_collection.dart';

class AlbumView extends GetWidget<CloudController> {
  const AlbumView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MyGetView(
        child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: MyAppBar(
        backgroundColor: Colors.transparent,
        title: RichText(
            text: TextSpan(
                style: TextStyle(
                    fontSize: 42.sp,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold),
                text: 'Here  ',
                children: [
              TextSpan(
                  text: '云盘～',
                  style: TextStyle(
                      color: Theme.of(context).primaryColor.withOpacity(.9))),
            ])),
      ),
      body: RequestLoadMoreWidget<CloudSongListWrap, CloudSongItem>(
          listKey: const ['data'],
          dioMetaData: controller.cloudSongDioMetaData(),
          childBuilder: (List<CloudSongItem> data) {
            controller.mediaItems
              ..clear()
              ..addAll(data
                  .map((e) => MediaItem(
                      id: e.simpleSong.id,
                      duration: Duration(milliseconds: e.simpleSong.dt ?? 0),
                      artUri: Uri.parse(
                          '${e.simpleSong.al?.picUrl ?? ''}?param=500y500'),
                      extras: {
                        'url': '',
                        'image': e.simpleSong.al?.picUrl ?? '',
                        'type': '',
                        'liked': Home.to.likeIds
                            .contains(int.tryParse(e.simpleSong.id)),
                        'artist': (e.simpleSong.ar ?? [])
                            .map((e) => jsonEncode(e.toJson()))
                            .toList()
                            .join(' / ')
                      },
                      title: e.simpleSong.name ?? "",
                      album: jsonEncode(e.simpleSong.al?.toJson()),
                      artist: (e.simpleSong.ar ?? [])
                          .map((e) => e.name)
                          .toList()
                          .join(' / ')))
                  .toList());
            return buildSongCollection(context,
                songs: controller.mediaItems,
                storageId: 'cloud',
                portraitShrinkWrap: true,
                portraitPadding: EdgeInsets.symmetric(horizontal: 20.w),
                onPlay: (index) => Home.to.playByIndex(index, 'queueTitle',
                    mediaItem: controller.mediaItems));
          }),
    ));
  }
}
