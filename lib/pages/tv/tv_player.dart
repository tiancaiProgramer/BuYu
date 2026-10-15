import 'dart:io';
import 'dart:math' as math;
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import '../wide/remote_button.dart';
import '../wide/wide_playback.dart';
import '../wide/wide_player.dart';

/// Progress updates only rebuild the widget whose selected value changed.
class PlaybackSlice<T> extends StatefulWidget {
  const PlaybackSlice(
      {super.key,
      required this.playback,
      required this.select,
      required this.builder});
  final WidePlayback playback;
  final T Function(WidePlaybackData) select;
  final Widget Function(BuildContext, WidePlaybackData) builder;
  @override
  State<PlaybackSlice<T>> createState() => _PlaybackSliceState<T>();
}

class _PlaybackSliceState<T> extends State<PlaybackSlice<T>> {
  late T _selection;
  void _update() {
    final next = widget.select(widget.playback.value);
    if (next != _selection) setState(() => _selection = next);
  }

  @override
  void initState() {
    super.initState();
    _selection = widget.select(widget.playback.value);
    widget.playback.addListener(_update);
  }

  @override
  void didUpdateWidget(PlaybackSlice<T> old) {
    super.didUpdateWidget(old);
    if (old.playback != widget.playback) {
      old.playback.removeListener(_update);
      widget.playback.addListener(_update);
    }
    _selection = widget.select(widget.playback.value);
  }

  @override
  void dispose() {
    widget.playback.removeListener(_update);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.playback.value);
}

class TvArtwork extends StatelessWidget {
  const TvArtwork({super.key, required this.url, required this.size});
  final String url;
  final double size;
  static const requestHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36 Edg/117.0.2045.35'
  };

  static String forSong(MediaItem song) {
    final image = song.extras?['image'];
    final source = image is String && image.trim().isNotEmpty
        ? image.trim()
        : song.artUri?.toString() ?? '';
    final uri = Uri.tryParse(source);
    return uri?.scheme == 'file' ? uri!.toFilePath() : source;
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
        color: Theme.of(context).primaryColor.withOpacity(.14),
        child: Icon(TablerIcons.music,
            size: size * .35, color: Theme.of(context).primaryColor));
    // Bound decoding even for large original album images on a 4K display.
    final pixels =
        (size * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(64, 512);
    var source = url;
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host.endsWith('.music.126.net') && !uri.hasQuery) {
      source = uri
          .replace(queryParameters: {'param': '${pixels}y$pixels'}).toString();
    }
    final image = url.isEmpty
        ? placeholder
        : url.startsWith('http')
            ? CachedNetworkImage(
                imageUrl: source,
                httpHeaders: requestHeaders,
                fit: BoxFit.cover,
                memCacheWidth: pixels,
                memCacheHeight: pixels,
                placeholder: (_, __) => placeholder,
                errorWidget: (_, __, error) {
                  debugPrint('Artwork load failed ($source): $error');
                  return placeholder;
                })
            : Image.file(File(uri?.scheme == 'file' ? uri!.toFilePath() : url),
                fit: BoxFit.cover,
                cacheWidth: pixels,
                cacheHeight: pixels,
                errorBuilder: (_, __, ___) => placeholder);
    return RepaintBoundary(
        child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(width: size, height: size, child: image)));
  }
}

class TvControls extends StatelessWidget {
  const TvControls(
      {super.key,
      required this.playback,
      required this.perform,
      this.mini = false,
      this.compact = false});
  final WidePlayback playback;
  final WidePerform perform;
  final bool mini, compact;
  @override
  Widget build(BuildContext context) => PlaybackSlice(
      playback: playback,
      select: (d) => (d.playing, d.repeat),
      builder: (_, data) =>
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (!mini) _button('收藏', TablerIcons.heart, playback.favorite),
            _button('上一首', TablerIcons.player_skip_back, playback.previous),
            _button(
                'toggle',
                data.playing
                    ? TablerIcons.player_pause
                    : TablerIcons.player_play,
                playback.toggle,
                label: data.playing ? '暂停' : '播放',
                autofocus: !mini),
            _button('下一首', TablerIcons.player_skip_forward, playback.next),
            if (!mini)
              _button(
                  'repeat',
                  data.repeat == AudioServiceRepeatMode.one
                      ? TablerIcons.repeat_once
                      : data.repeat == AudioServiceRepeatMode.none
                          ? TablerIcons.arrows_shuffle
                          : TablerIcons.repeat,
                  () async => playback.repeat(),
                  label: '循环模式'),
          ]));
  Widget _button(String id, IconData icon, Future<void> Function() action,
          {String? label, bool autofocus = false}) =>
      Tooltip(
          message: label ?? id,
          child: RemoteButton(
              key: ValueKey('control:$id'),
              autofocus: autofocus,
              padding: EdgeInsets.all(compact
                  ? 6
                  : mini
                      ? 10
                      : 14),
              onPressed: () => perform(action),
              child: Icon(icon,
                  size: compact
                      ? 24
                      : mini
                          ? 26
                          : 30)));
}

/// Uses the surrounding theme so the phone keeps its original colours.
class TvPlayer extends StatelessWidget {
  const TvPlayer(
      {super.key,
      required this.playback,
      required this.perform,
      this.onBack,
      this.phone = false});
  final WidePlayback playback;
  final WidePerform perform;
  final VoidCallback? onBack;
  final bool phone;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (_, constraints) {
        final compact = constraints.maxHeight < 460;
        final accent = Theme.of(context).primaryColor;
        return Padding(
            padding: EdgeInsets.all(compact ? 8 : 24),
            child: Column(children: [
              if (onBack != null)
                Align(
                    alignment: Alignment.centerLeft,
                    child: RemoteButton(
                        key: const ValueKey('player-back'),
                        onPressed: onBack,
                        child: const Icon(TablerIcons.arrow_left))),
              Expanded(
                  child: Row(children: [
                Expanded(
                    flex: 4,
                    child: PlaybackSlice(
                        playback: playback,
                        select: (d) => (d.song, d.loading, d.error),
                        builder: (_, data) => Column(children: [
                              Expanded(child:
                                  Center(child: LayoutBuilder(builder: (_, c) {
                                final size = math.max(0.0,
                                    math.min(c.maxWidth, c.maxHeight) - 12);
                                return _Vinyl(
                                    url:
                                        data.song.extras?['image'] as String? ??
                                            '',
                                    size: size);
                              }))),
                              if (data.loading || data.error != null)
                                Text(
                                    data.error == null
                                        ? '正在加载音频…'
                                        : '播放失败，可切歌或重试',
                                    maxLines: 1,
                                    style:
                                        TextStyle(color: accent, fontSize: 13)),
                            ]))),
                SizedBox(width: compact ? 12 : 40),
                Expanded(
                    flex: 5,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PlaybackSlice(
                              playback: playback,
                              select: (d) => d.song,
                              builder: (_, data) => Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(data.song.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: compact ? 20 : 30,
                                                fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 6),
                                        Text(data.song.artist ?? '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: compact ? 13 : 18)),
                                      ])),
                          const SizedBox(height: 12),
                          Expanded(
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
                                      fontSize: compact ? 16 : 24,
                                      onSeek: (p) =>
                                          perform(() => playback.seek(p))))),
                        ])),
              ])),
              RepaintBoundary(
                  child: PlaybackSlice(
                      playback: playback,
                      select: (d) => (d.song, d.position),
                      builder: (_, data) => RemoteSeek(
                          data: data,
                          accent: accent,
                          onSeek: (p) => perform(() => playback.seek(p))))),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                TvControls(playback: playback, perform: perform),
                if (!phone)
                  Tooltip(
                      message: '播放队列',
                      child: RemoteButton(
                          key: const ValueKey('player-queue'),
                          onPressed: () => _queue(context),
                          child: const Icon(TablerIcons.playlist))),
              ]),
            ]));
      });

  Future<void> _queue(BuildContext context) => showDialog<void>(
      context: context,
      builder: (context) => RemoteInputScope(
              child: AlertDialog(
                  title: const Text('播放队列'),
                  content: SizedBox(
                      width: 560,
                      height: 280,
                      child: PlaybackSlice(
                          playback: playback,
                          select: (d) => (d.queue, d.song.id),
                          builder: (_, data) => ListView.builder(
                              itemCount: data.queue.length,
                              itemBuilder: (_, i) => RemoteButton(
                                  key: ValueKey('player-queue:${data.queue[i].id}'),
                                  autofocus: data.queue[i].id == data.song.id,
                                  selected: data.queue[i].id == data.song.id,
                                  onPressed: () =>
                                      perform(() => playback.playQueueIndex(i)),
                                  child: Text(data.queue[i].title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis))))),
                  actions: [
                RemoteButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'))
              ])));
}

class _Vinyl extends StatelessWidget {
  const _Vinyl({required this.url, required this.size});
  final String url;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
      dimension: size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(size: Size.square(size), painter: _VinylPainter()),
        ClipOval(child: TvArtwork(url: url, size: size * .52)),
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                shape: BoxShape.circle)),
      ]));
}

class _VinylPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xff171717));
    final groove = Paint()
      ..color = Colors.white.withOpacity(.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var r = radius * .58; r < radius * .98; r += 5)
      canvas.drawCircle(center, r, groove);
  }

  @override
  bool shouldRepaint(_VinylPainter oldDelegate) => false;
}
