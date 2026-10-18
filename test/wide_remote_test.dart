import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/display_mode.dart';
import 'package:bujuan/common/lyric_parser/lyrics_reader_model.dart';
import 'package:bujuan/pages/wide/remote_button.dart';
import 'package:bujuan/pages/wide/wide_catalog.dart';
import 'package:bujuan/pages/wide/wide_home.dart';
import 'package:bujuan/pages/wide/wide_playback.dart';
import 'package:bujuan/pages/wide/wide_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const song = MediaItem(
    id: '1', title: '试用歌曲', artist: '测试歌手', duration: Duration(minutes: 2));

class FakeCatalog implements WideCatalog {
  int localCalls = 0;
  Future<WidePage>? delayed;
  @override
  Future<WidePage> recommendations() async {
    if (delayed != null) return await delayed!;
    return const WidePage(playlists: [WidePlaylist('p1', '测试歌单', '')]);
  }

  @override
  Future<WidePage> playlistSongs(String id, {int offset = 0}) async =>
      const WidePage(songs: [song]);
  @override
  Future<WidePage> myPlaylists({int offset = 0}) async => const WidePage();
  @override
  Future<WidePage> search(String keyword, {int offset = 0}) async =>
      const WidePage(songs: [song]);
  @override
  Future<WidePage> localSongs() async {
    localCalls++;
    return const WidePage(songs: [MediaItem(id: 'local:2', title: '本地测试歌曲')]);
  }

  @override
  Future<String?> refreshAccount() async => null;
  @override
  Future<WideQr> loginQr() async =>
      WideQr('https://music.163.com/login?code=test', () async => 800);
  @override
  Future<void> logout() async {}
}

class PreviewCatalog extends FakeCatalog {
  @override
  Future<WidePage> recommendations() async => const WidePage(playlists: [
        WidePlaylist('demo1', '每日精选', ''),
        WidePlaylist('demo2', '旅途与夜晚', ''),
        WidePlaylist('demo3', '本地音乐收藏', ''),
        WidePlaylist('demo4', '喜欢的音乐', ''),
      ]);
}

WidePlayback playback(
        {VoidCallback? toggle,
        ValueChanged<Duration>? seek,
        ValueChanged<int>? playIndex}) =>
    WidePlayback(
      initial: const WidePlaybackData(
          song: song, queue: [song], position: Duration(seconds: 60)),
      playSongs: (_, index) async {
        playIndex?.call(index);
      },
      toggle: () async {
        toggle?.call();
      },
      previous: () async {},
      next: () async {},
      seek: (position) async {
        seek?.call(position);
      },
      repeat: () {},
      playQueueIndex: (index) async {
        playIndex?.call(index);
      },
      playNext: (_) async {},
      favorite: () async {},
    );

Future<void> mount(WidgetTester tester, Widget child,
    {Size size = const Size(1280, 720)}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

Future<void> activate(WidgetTester tester, String key) async {
  final button = tester.widget<RemoteButton>(find.byKey(ValueKey(key)));
  button.focusNode!.requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.select);
  await tester.pumpAndSettle();
}

void main() {
  if (const bool.fromEnvironment('BUJUAN_PREVIEW_CAPTURE')) {
    setUpAll(() async {
      final bytes =
          await File(const String.fromEnvironment('BUJUAN_PREVIEW_FONT'))
              .readAsBytes();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
      await (FontLoader('Roboto')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    });
    testWidgets('render actual wide widgets for visual inspection',
        (tester) async {
      final rootKey = GlobalKey();
      final model = playback();
      final lines = List.generate(
          8,
          (i) => LyricsLineModel()
            ..startTime = i * 8000
            ..mainText = [
              '本地音乐也能在大屏播放',
              '播放控制始终触手可及',
              '方向键选歌，确定键播放',
              '歌词随音乐同步滚动'
            ][i % 4]);
      model.value = WidePlaybackData(
        song: const MediaItem(
            id: 'preview',
            title: '横屏试用 · 本地音乐',
            artist: 'BuJuan',
            duration: Duration(minutes: 3)),
        position: const Duration(seconds: 12),
        lyrics: lines,
        playing: true,
      );
      addTearDown(model.dispose);
      for (final entry in [
        ('tv-preview.png', const Size(1280, 720), true),
        ('car-preview.png', const Size(1024, 600), false),
        ('car-compact-preview.png', const Size(640, 360), false),
      ]) {
        await mount(
            tester,
            RepaintBoundary(
                key: rootKey,
                child: WideHome(
                    catalog: PreviewCatalog(), playback: model, tv: entry.$3)),
            size: entry.$2);
        if (entry.$3) {
          await tester.tap(find.text('歌词'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        final boundary =
            rootKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final path =
            '${const String.fromEnvironment('BUJUAN_PREVIEW_PATH')}/${entry.$1}';
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(path).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });
  }

  test('layout follows the window rather than device diagonal', () {
    expect(DisplayMode.useWideLayout(const Size(390, 844)), isFalse);
    expect(DisplayMode.useWideLayout(const Size(844, 390)), isTrue);
    expect(DisplayMode.useWideLayout(const Size(800, 1280)), isFalse);
    expect(DisplayMode.useWideLayout(const Size(390, 844), tv: true), isTrue);
  });

  testWidgets('root adapts after rotation without replacing its state',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(AdaptiveBujuanApp(
        builder: (wide) => Directionality(
            textDirection: TextDirection.ltr,
            child: Text(wide ? 'wide' : 'portrait'))));
    expect(find.text('portrait'), findsOneWidget);
    tester.view.physicalSize = const Size(844, 390);
    await tester.pump();
    expect(find.text('wide'), findsOneWidget);
  });

  testWidgets('D-pad OK activates once and held OK does not repeat',
      (tester) async {
    var count = 0;
    await mount(
        tester,
        RemoteInputScope(
            child: Center(
                child: RemoteButton(
                    autofocus: true,
                    onPressed: () {
                      count++;
                    },
                    child: const Text('action')))));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(count, 1);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    expect(count, 1);
  });

  testWidgets('arrow navigation reaches local music and OK opens it',
      (tester) async {
    final catalog = FakeCatalog();
    final model = playback();
    addTearDown(model.dispose);
    await mount(tester, WideHome(catalog: catalog, playback: model, tv: true));
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(catalog.localCalls, 1);
    expect(find.text('本地测试歌曲'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('return from playlist restores focus to its original card',
      (tester) async {
    final model = playback();
    addTearDown(model.dispose);
    await mount(tester, WideHome(catalog: FakeCatalog(), playback: model));
    await activate(tester, 'playlist:p1');
    expect(find.byKey(const ValueKey('song:1')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final button =
        tester.widget<RemoteButton>(find.byKey(const ValueKey('playlist:p1')));
    expect(button.focusNode!.hasFocus, isTrue);
    expect(find.text('测试歌单'), findsOneWidget);
  });

  testWidgets('late network results cannot overwrite another section',
      (tester) async {
    final completer = Completer<WidePage>();
    final catalog = FakeCatalog()..delayed = completer.future;
    final model = playback();
    addTearDown(model.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        MaterialApp(home: WideHome(catalog: catalog, playback: model)));
    await tester.pump();
    await activate(tester, 'nav:3');
    completer.complete(
        const WidePage(playlists: [WidePlaylist('old', '过期搜索结果', '')]));
    await tester.pumpAndSettle();
    expect(find.text('本地测试歌曲'), findsOneWidget);
    expect(find.text('过期搜索结果'), findsNothing);
  });

  testWidgets('media key does not double-toggle on held key', (tester) async {
    var count = 0;
    final model = playback(toggle: () => count++);
    addTearDown(model.dispose);
    await mount(tester, WideHome(catalog: FakeCatalog(), playback: model));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pump();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pumpAndSettle();
    expect(count, 1);
  });

  testWidgets('focus stays on play button when it becomes pause',
      (tester) async {
    late WidePlayback model;
    model = playback(toggle: () {
      model.value = const WidePlaybackData(song: song, playing: true);
    });
    addTearDown(model.dispose);
    await mount(
        tester,
        RemoteInputScope(
            child: Center(
                child: SizedBox(
                    width: 400,
                    child: WidePlayer(
                        playback: model, perform: (action) => action())))));
    final button = find.byKey(const ValueKey('control:toggle'));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focus = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(model.value.playing, isTrue);
    expect(button, findsOneWidget);
    expect(FocusManager.instance.primaryFocus, same(focus));
  });

  for (final authenticated in [false, true]) {
    testWidgets('wide login returns from official web auth ($authenticated)',
        (tester) async {
      final pending = Completer<bool>();
      await mount(
          tester,
          Builder(
              builder: (context) => RemoteButton(
                    onPressed: () => showDialog<bool>(
                        context: context,
                        builder: (_) => WideLoginDialog(
                            catalog: FakeCatalog(),
                            webLogin: () => pending.future)),
                    child: const Text('open auth'),
                  )),
          size: const Size(640, 360));
      await tester.tap(find.text('open auth'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('官方网页登录'));
      await tester.pump();
      expect(find.text('正在认证…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('二维码过期，请刷新'), findsNothing);
      pending.complete(authenticated);
      await tester.pumpAndSettle();
      expect(find.byType(WideLoginDialog),
          authenticated ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
      if (!authenticated) {
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets('QR dialog fits short landscape and refresh is reachable',
      (tester) async {
    await mount(
        tester,
        Builder(
            builder: (context) => RemoteButton(
                autofocus: true,
                onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => WideLoginDialog(catalog: FakeCatalog())),
                child: const Text('login'))),
        size: const Size(640, 360));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('刷新二维码'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('刷新二维码'), findsNothing);
  });

  for (final size in [
    const Size(1280, 720),
    const Size(1920, 1080),
    const Size(1024, 600),
    const Size(640, 360),
    const Size(800, 300)
  ]) {
    testWidgets('wide screen has no overflow at $size', (tester) async {
      final model = playback();
      addTearDown(model.dispose);
      await mount(tester, WideHome(catalog: FakeCatalog(), playback: model),
          size: size);
      expect(tester.takeException(), isNull);
      if (size.width < 760 || size.height < 410) {
        await activate(tester, 'open-player');
        expect(find.byKey(const ValueKey('seek')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('progress arrows seek while keeping focus and clamp to duration',
      (tester) async {
    final positions = <Duration>[];
    await mount(
        tester,
        RemoteInputScope(
            child: Center(
                child: SizedBox(
                    width: 400,
                    child: RemoteSeek(
                        data: const WidePlaybackData(
                            song: song, position: Duration(seconds: 115)),
                        onSeek: (position) async {
                          positions.add(position);
                        })))));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focus = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 200));
    expect(positions, [const Duration(seconds: 120)]);
    expect(FocusManager.instance.primaryFocus, same(focus));
  });

  testWidgets('a pending seek is cancelled when the song changes',
      (tester) async {
    final positions = <Duration>[];
    Widget screen(MediaItem current) => RemoteInputScope(
        child: Center(
            child: SizedBox(
                width: 400,
                child: RemoteSeek(
                    key: const ValueKey('progress'),
                    data: WidePlaybackData(song: current),
                    onSeek: (position) async {
                      positions.add(position);
                    }))));
    await mount(tester, screen(song));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpWidget(MaterialApp(
        home: screen(const MediaItem(
            id: '2', title: '下一首', duration: Duration(minutes: 3)))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(positions, isEmpty);
  });

  test('lyric selection handles exact boundaries and seek bounds', () {
    final lines = [
      LyricsLineModel()..startTime = 1000,
      LyricsLineModel()..startTime = 2000
    ];
    expect(activeLyric(lines, const Duration(milliseconds: 999)), -1);
    expect(activeLyric(lines, const Duration(seconds: 2)), 1);
    expect(clampSeek(const Duration(seconds: -10), const Duration(minutes: 2)),
        Duration.zero);
    expect(clampSeek(const Duration(minutes: 5), const Duration(minutes: 2)),
        const Duration(minutes: 2));
  });
}
