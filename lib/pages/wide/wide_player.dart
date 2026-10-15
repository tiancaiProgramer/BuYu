import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common/lyric_parser/lyrics_reader_model.dart';
import 'remote_button.dart';
import 'wide_artwork.dart';
import 'wide_playback.dart';

typedef WidePerform = Future<void> Function(Future<void> Function());

Duration clampSeek(Duration position, Duration? total) => Duration(
    milliseconds: position.inMilliseconds
        .clamp(0, math.max(0, total?.inMilliseconds ?? 0)));

int activeLyric(List<LyricsLineModel> lines, Duration position) => lines
    .lastIndexWhere((line) => (line.startTime ?? 0) <= position.inMilliseconds);

String wideTime(Duration duration) {
  final seconds = math.max(0, duration.inSeconds);
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class WidePlayer extends StatefulWidget {
  const WidePlayer({super.key, required this.playback, required this.perform});
  final WidePlayback playback;
  final WidePerform perform;
  @override
  State<WidePlayer> createState() => _WidePlayerState();
}

class _WidePlayerState extends State<WidePlayer> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<WidePlaybackData>(
        valueListenable: widget.playback,
        builder: (context, data, _) => LayoutBuilder(
          builder: (context, constraints) {
            final body = Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: const Color(0xff1a2632),
                  borderRadius: BorderRadius.circular(16)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(data.song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(data.song.artist ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 13)),
                    if (data.loading || data.error != null)
                      Text(data.error == null ? '正在加载音频…' : '播放失败，可切歌或重试',
                          style: TextStyle(
                              fontSize: 12,
                              color: data.error == null
                                  ? wideAccent
                                  : Colors.orangeAccent)),
                    const SizedBox(height: 6),
                    WideControls(
                        playback: widget.playback,
                        data: data,
                        perform: widget.perform),
                    const SizedBox(height: 4),
                    RemoteSeek(
                        data: data,
                        onSeek: (position) => widget
                            .perform(() => widget.playback.seek(position))),
                    const SizedBox(height: 6),
                    Row(children: [
                      for (var i = 0; i < 3; i++)
                        Expanded(
                            child: RemoteButton(
                          selected: i == _tab,
                          onPressed: () => setState(() => _tab = i),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                              child: Text(['封面', '歌词', '队列'][i],
                                  style: const TextStyle(fontSize: 13))),
                        ))
                    ]),
                    const SizedBox(height: 8),
                    Expanded(
                        child: _tab == 0
                            ? _cover(data)
                            : _tab == 1
                                ? WideLyrics(
                                    data: data,
                                    onSeek: (position) => widget.perform(
                                        () => widget.playback.seek(position)))
                                : _queue(data)),
                  ]),
            );
            if (constraints.maxHeight < 280) {
              return SingleChildScrollView(
                  child: SizedBox(height: 340, child: body));
            }
            return body;
          },
        ),
      );

  Widget _cover(WidePlaybackData data) => Column(children: [
        Expanded(child: LayoutBuilder(builder: (_, constraints) {
          final size = math.min(constraints.maxWidth, constraints.maxHeight);
          return Center(
              child: WideArtwork(
                  url: data.song.extras?['image'] as String? ?? '',
                  size: size));
        })),
        if (data.lyrics.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                data
                        .lyrics[math.max(
                            0, activeLyric(data.lyrics, data.position))]
                        .mainText ??
                    '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: wideAccent, fontSize: 15),
              )),
      ]);

  Widget _queue(WidePlaybackData data) {
    if (data.queue.isEmpty) return const Center(child: Text('暂无歌曲'));
    return ListView.builder(
        itemCount: data.queue.length,
        itemBuilder: (_, i) {
          final song = data.queue[i];
          return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: RemoteButton(
                key: ValueKey('player-queue:${song.id}'),
                selected: song.id == data.song.id,
                onPressed: () =>
                    widget.perform(() => widget.playback.playQueueIndex(i)),
                child: Text(song.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ));
        });
  }
}

class WideControls extends StatelessWidget {
  const WideControls(
      {super.key,
      required this.playback,
      required this.data,
      required this.perform,
      this.compact = false});
  final WidePlayback playback;
  final WidePlaybackData data;
  final WidePerform perform;
  final bool compact;

  Widget _button(String label, IconData icon, Future<void> Function() action) =>
      Tooltip(
        message: label,
        child: RemoteButton(
            key: ValueKey(
                'control:${label == '播放' || label == '暂停' ? 'toggle' : label}'),
            onPressed: () => perform(action),
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: compact ? 25 : 28)),
      );

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _button('上一首', Icons.skip_previous, playback.previous),
        _button(
            data.playing ? '暂停' : '播放',
            data.playing
                ? Icons.pause_circle_outline
                : Icons.play_circle_outline,
            playback.toggle),
        _button('下一首', Icons.skip_next, playback.next),
        if (!compact)
          Tooltip(
              message: '循环模式',
              child: RemoteButton(
                key: const ValueKey('control:repeat'),
                onPressed: () {
                  playback.repeat();
                },
                padding: const EdgeInsets.all(10),
                child: Icon(
                    data.repeat == AudioServiceRepeatMode.one
                        ? Icons.repeat_one
                        : data.repeat == AudioServiceRepeatMode.none
                            ? Icons.shuffle
                            : Icons.repeat,
                    size: 25),
              )),
      ]);
}

class WideMiniPlayer extends StatelessWidget {
  const WideMiniPlayer(
      {super.key, required this.playback, required this.perform});
  final WidePlayback playback;
  final WidePerform perform;
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<WidePlaybackData>(
        valueListenable: playback,
        builder: (_, data, __) => Container(
          decoration: BoxDecoration(
              color: const Color(0xff1a2632),
              borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Row(children: [
            Expanded(
                child: Text(data.song.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
            SizedBox(
                width: 160,
                child: WideControls(
                    playback: playback,
                    data: data,
                    perform: perform,
                    compact: true))
          ]),
        ),
      );
}

class RemoteSeek extends StatefulWidget {
  const RemoteSeek(
      {super.key,
      required this.data,
      required this.onSeek,
      this.accent = wideAccent,
      this.showHint = true});
  final Color accent;
  final bool showHint;
  final WidePlaybackData data;
  final Future<void> Function(Duration) onSeek;
  @override
  State<RemoteSeek> createState() => _RemoteSeekState();
}

class _RemoteSeekState extends State<RemoteSeek> {
  Duration? _target;
  Timer? _timer;
  int _revision = 0;

  void _schedule(Duration target) {
    setState(() => _target = clampSeek(target, widget.data.song.duration));
    _timer?.cancel();
    final revision = ++_revision;
    final position = _target!;
    _timer = Timer(const Duration(milliseconds: 120), () async {
      try {
        await widget.onSeek(position);
      } finally {
        if (mounted && revision == _revision) setState(() => _target = null);
      }
    });
  }

  @override
  void didUpdateWidget(RemoteSeek oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.song.id != widget.data.song.id) {
      _timer?.cancel();
      ++_revision;
      _target = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.data.song.duration ?? Duration.zero;
    final position = clampSeek(_target ?? widget.data.position, total);
    return Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if ([LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight]
              .contains(event.logicalKey)) {
            if (event is KeyDownEvent || event is KeyRepeatEvent) {
              _schedule((_target ?? widget.data.position) +
                  Duration(
                      seconds: event.logicalKey == LogicalKeyboardKey.arrowRight
                          ? 10
                          : -10));
            }
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: RemoteButton(
          key: const ValueKey('seek'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          onPressed: total > Duration.zero ? () {} : null,
          child: Column(children: [
            ExcludeFocus(
                child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 12)),
                    child: Slider(
                        min: 0,
                        max: math.max(1, total.inMilliseconds).toDouble(),
                        value: position.inMilliseconds.toDouble(),
                        activeColor: widget.accent,
                        onChanged: total > Duration.zero
                            ? (value) =>
                                _schedule(Duration(milliseconds: value.round()))
                            : null))),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(wideTime(position), style: const TextStyle(fontSize: 12)),
              if (widget.showHint)
                Text('左右调整进度',
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.color
                            ?.withOpacity(.54))),
              Text(wideTime(total), style: const TextStyle(fontSize: 12)),
            ]),
          ]),
        ));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class WideLyrics extends StatefulWidget {
  const WideLyrics(
      {super.key,
      required this.data,
      required this.onSeek,
      this.accent = wideAccent,
      this.fontSize = 15,
      this.lineExtent = 94});
  final Color accent;
  final double fontSize, lineExtent;
  final WidePlaybackData data;
  final Future<void> Function(Duration) onSeek;
  @override
  State<WideLyrics> createState() => _WideLyricsState();
}

class _WideLyricsState extends State<WideLyrics> {
  final _scroll = ScrollController();
  bool _manual = false;
  double get _extent => widget.lineExtent;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  void _follow() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients || _manual) return;
        final index =
            math.max(0, activeLyric(widget.data.lyrics, widget.data.position));
        final offset =
            (index * _extent - _scroll.position.viewportDimension / 3)
                .clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.animateTo(offset,
            duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      });

  @override
  void didUpdateWidget(WideLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.song.id != widget.data.song.id) _manual = false;
    if (!_manual &&
        (activeLyric(oldWidget.data.lyrics, oldWidget.data.position) !=
                activeLyric(widget.data.lyrics, widget.data.position) ||
            oldWidget.data.lyrics.length != widget.data.lyrics.length)) {
      _follow();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.lyrics.isEmpty) return const Center(child: Text('暂无歌词'));
    final current = activeLyric(widget.data.lyrics, widget.data.position);
    return Column(children: [
      if (_manual)
        RemoteButton(
            onPressed: () {
              setState(() => _manual = false);
              _follow();
            },
            child: const Text('恢复歌词跟随', style: TextStyle(fontSize: 12))),
      Expanded(
          child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (focus) {
                if (focus) {
                  setState(() => _manual = true);
                } else {
                  setState(() => _manual = false);
                  _follow();
                }
              },
              child: Listener(
                onPointerDown: (_) => setState(() => _manual = true),
                child: ListView.builder(
                    controller: _scroll,
                    itemExtent: _extent,
                    itemCount: widget.data.lyrics.length,
                    itemBuilder: (_, i) {
                      final line = widget.data.lyrics[i];
                      return RemoteButton(
                        key: ValueKey('lyric:${widget.data.song.id}:$i'),
                        selected: i == current,
                        padding: const EdgeInsets.all(6),
                        onPressed: () => widget.onSeek(clampSeek(
                            Duration(milliseconds: line.startTime ?? 0),
                            widget.data.song.duration)),
                        child: Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              Text(line.mainText ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: widget.fontSize,
                                      color: i == current
                                          ? widget.accent
                                          : Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.color
                                              ?.withOpacity(.65))),
                              if ((line.extText ?? '').isNotEmpty)
                                Text(line.extText!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.color
                                            ?.withOpacity(.54))),
                            ])),
                      );
                    }),
              ))),
    ]);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }
}
