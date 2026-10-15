import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../pages/play_list/playlist_view.dart';
import 'landscape_cards.dart';

/// Returns a ScrollView directly so cloud pull-to-refresh can reuse its slivers.
ScrollView buildSongCollection(BuildContext context,
    {required List<MediaItem> songs,
    required ValueChanged<int> onPlay,
    required String storageId,
    bool showArtwork = false,
    EdgeInsetsGeometry? portraitPadding,
    bool portraitShrinkWrap = false}) {
  Widget song(BuildContext context, int index) => SongItem(
      index: index,
      mediaItem: songs[index],
      showArtwork: showArtwork,
      onTap: () => onPlay(index));
  if (phoneLandscape(context)) {
    return GridView.builder(
        key: PageStorageKey('$storageId:landscape'),
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisExtent: 112 * 2 / 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 10),
        itemCount: songs.length,
        itemBuilder: (context, index) =>
            LandscapeCardSurface(child: song(context, index)));
  }
  return ListView.builder(
      key: PageStorageKey('$storageId:portrait'),
      shrinkWrap: portraitShrinkWrap,
      padding: portraitPadding,
      itemExtent: 130.w,
      itemCount: songs.length,
      itemBuilder: song);
}
