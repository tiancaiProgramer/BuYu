import 'package:bujuan/pages/play_list/playlist_view.dart';
import 'package:bujuan/pages/playlist_manager/playlist_manager_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:auto_route/auto_route.dart';
import '../../routes/router.gr.dart' as routes;
import '../../widget/landscape_cards.dart';

class PlaylistManagerView extends GetView<PlaylistManager> {
  const PlaylistManagerView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('我的歌单')),
      body: SafeArea(
          top: false,
          child: Obx(() {
            if (!phoneLandscape(context)) {
              return ListView.builder(
                  itemBuilder: (context, index) =>
                      PlayListItem(play: controller.playlist[index]),
                  itemCount: controller.playlist.length);
            }
            return GridView.builder(
                key: const ValueKey('playlist-manager-landscape'),
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisExtent: 89.6,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 10),
                itemCount: controller.playlist.length,
                itemBuilder: (context, index) {
                  final play = controller.playlist[index];
                  return LandscapeCard(
                      title: play.name ?? '',
                      subtitle: '${play.trackCount ?? 0} 首',
                      image: play.coverImgUrl ?? play.picUrl ?? '',
                      onTap: () { context.router.push(
                          const routes.PlayListView().copyWith(args: play)); });
                });
          })),
    );
  }
}
