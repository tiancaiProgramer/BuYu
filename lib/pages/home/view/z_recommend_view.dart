import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../common/netease_api/src/netease_api.dart';
import '../../../common/netease_api/src/api/play/bean.dart';
import '../../../routes/router.gr.dart' as routes;
import 'playing_artist_panel.dart';
import '../home_controller.dart';

class RecommendView extends GetView<Home> {
  const RecommendView({super.key, this.artistLoader, this.songsLoader});
  final ArtistLoader? artistLoader;
  final ArtistSongsLoader? songsLoader;

  Future<void> _open(BuildContext context, Artists artist) async {
    final router = AutoRouter.of(context);
    try {
      if (int.tryParse(artist.id) == null || int.tryParse(artist.id)! <= 0) {
        final response =
            await NeteaseMusicApi().searchArtists(artist.name ?? '');
        final exact = response.result.artists
            .where((a) => a.name == artist.name)
            .toList();
        if (exact.isEmpty) throw StateError('not found');
        artist = exact.first;
      }
      if (controller.panelController.isAttached &&
          controller.panelController.isPanelOpen) {
        await controller.panelController.close();
      }
      if (controller.panelControllerHome.isAttached)
        await controller.panelControllerHome.close();
      router.push(routes.ArtistsView(artist: artist));
    } catch (_) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('暂时无法打开歌手信息，请稍后重试')));
    }
  }

  @override
  Widget build(BuildContext context) => Obx(() => PlayingArtistPanel(
      song: controller.mediaItem.value, artistLoader: artistLoader, songsLoader: songsLoader,
      onOpen: (artist) => _open(context, artist)));
}
