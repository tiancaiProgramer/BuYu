// Community maintenance and new features: tiancaiProgramer.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../tv/tv_player.dart';
import '../../wide/wide_playback.dart';
import '../../wide/wide_player.dart';

/// Keeps the song and its controls together, reserving the full height for lyrics.
class PhoneLandscapePlayer extends StatelessWidget {
  const PhoneLandscapePlayer(
      {super.key, required this.playback, required this.perform});
  final WidePlayback playback;
  final WidePerform perform;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (_, constraints) {
        final accent = Theme.of(context).primaryColor;
        final leftWidth =
            math.min(300.0, math.max(190.0, constraints.maxWidth * .36));
        return Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(children: [
              SizedBox(
                  width: leftWidth,
                  child: Column(
                      key: const ValueKey('phone-player-song'),
                      children: [
                        Expanded(
                            child: PlaybackSlice(
                                playback: playback,
                                select: (d) => (d.song, d.loading, d.error),
                                builder: (_, data) => Column(children: [
                                      Expanded(
                                          child: Center(
                                              child: LayoutBuilder(
                                                  builder: (_, c) => TvArtwork(
                                                      url: TvArtwork.forSong(
                                                          data.song),
                                                      size: math.min(
                                                          160.0,
                                                          math.max(
                                                              0.0,
                                                              math.min(
                                                                      c.maxWidth,
                                                                      c.maxHeight) -
                                                                  6)))))),
                                      Text(data.song.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: Theme.of(context).textTheme.bodyMedium?.color,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 3),
                                      Text(data.song.artist ?? '',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.color
                                                  ?.withOpacity(.7))),
                                      if (data.loading || data.error != null)
                                        Text(
                                            data.error == null
                                                ? '正在加载音频…'
                                                : '播放失败，可切歌或重试',
                                            maxLines: 1,
                                            style: TextStyle(
                                                fontSize: 12, color: accent)),
                                    ]))),
                        RepaintBoundary(
                            child: PlaybackSlice(
                                playback: playback,
                                select: (d) => (d.song, d.position),
                                builder: (_, data) => RemoteSeek(
                                    data: data,
                                    accent: accent,
                                    showHint: false,
                                    onSeek: (p) =>
                                        perform(() => playback.seek(p))))),
                        TvControls(
                            playback: playback,
                            perform: perform,
                            compact: true),
                      ])),
              const SizedBox(width: 12),
              Expanded(
                  child: RepaintBoundary(
                      key: const ValueKey('phone-player-lyrics'),
                      child: PlaybackSlice(
                          playback: playback,
                          select: (d) => (
                                d.song.id,
                                d.lyrics,
                                activeLyric(d.lyrics, d.position)
                              ),
                          builder: (_, data) => WideLyrics(
                              data: data,
                              accent: accent,
                              fontSize: 17,
                              lineExtent: 68,
                              onSeek: (p) =>
                                  perform(() => playback.seek(p)))))),
            ]));
      });
}
