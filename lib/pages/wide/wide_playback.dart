import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../common/constants/key.dart';
import '../../common/lyric_parser/lyrics_reader_model.dart';
import '../home/home_controller.dart';

class WidePlaybackData {
  const WidePlaybackData(
      {this.song = const MediaItem(id: '', title: '选择一首歌曲'),
      this.queue = const [],
      this.lyrics = const [],
      this.position = Duration.zero,
      this.playing = false,
      this.loading = false,
      this.repeat = AudioServiceRepeatMode.all,
      this.error});
  final MediaItem song;
  final List<MediaItem> queue;
  final List<LyricsLineModel> lyrics;
  final Duration position;
  final bool playing;
  final bool loading;
  final AudioServiceRepeatMode repeat;
  final String? error;
}

class WidePlayback extends ValueNotifier<WidePlaybackData> {
  WidePlayback({
    WidePlaybackData initial = const WidePlaybackData(),
    required this.playSongs,
    required this.toggle,
    required this.previous,
    required this.next,
    required this.seek,
    required this.repeat,
    required this.playQueueIndex,
    required this.playNext,
    required this.favorite,
  }) : super(initial);

  final Future<void> Function(List<MediaItem>, int) playSongs;
  final Future<void> Function() toggle;
  final Future<void> Function() previous;
  final Future<void> Function() next;
  final Future<void> Function(Duration) seek;
  final VoidCallback repeat;
  final Future<void> Function(int) playQueueIndex;
  final Future<void> Function(MediaItem) playNext;
  final Future<void> Function() favorite;
  final _subscriptions = <StreamSubscription>[];

  factory WidePlayback.connect(Home home) {
    final handler = home.audioServeHandler;
    final model = WidePlayback(
      playSongs: (songs, index) async {
        home.fm.value = false;
        await home.box.put(fmSp, false);
        await handler.changeQueueLists(songs, index: index);
      },
      toggle: () => home.playing.value ? handler.pause() : handler.play(),
      previous: handler.skipToPrevious,
      next: handler.skipToNext,
      seek: handler.seek,
      repeat: home.changeRepeatMode,
      playQueueIndex: handler.skipToQueueItem,
      playNext: (song) async {
        final current = handler.queue.value
            .indexWhere((e) => e.id == handler.mediaItem.value?.id);
        await handler.insertQueueItem(current + 1, song);
      },
      favorite: () async {
        await home.likeSong();
      },
    );
    void update() {
      final state = handler.playbackState.value;
      model.value = WidePlaybackData(
          song: home.mediaItem.value,
          queue: List.of(home.mediaItems),
          lyrics: List.of(home.lyricsLineModels),
          position: home.duration.value,
          playing: state.playing,
          loading: state.processingState == AudioProcessingState.loading ||
              state.processingState == AudioProcessingState.buffering,
          repeat: home.audioServiceRepeatMode.value,
          error: state.errorMessage);
    }

    model._subscriptions.addAll([
      home.mediaItem.listen((_) => update()),
      home.mediaItems.listen((_) => update()),
      home.duration.listen((_) => update()),
      home.playing.listen((_) => update()),
      home.audioServiceRepeatMode.listen((_) => update()),
      (home.lyricsLineModels as RxList<LyricsLineModel>)
          .listen((_) => update()),
      handler.playbackState.listen((_) => update()),
    ]);
    update();
    return model;
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }
}
