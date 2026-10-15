import 'dart:io';
import 'dart:ui' as ui;
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/display_mode.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/pages/tv/tv_home.dart';
import 'package:bujuan/pages/tv/tv_player.dart';
import 'package:bujuan/pages/wide/remote_button.dart';
import 'package:bujuan/pages/wide/wide_playback.dart';
import 'package:bujuan/common/lyric_parser/lyrics_reader_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'wide_remote_test.dart' as fixture;

void main() {
  testWidgets('TV keeps existing entries and horizontal remote order',
      (tester) async {
    final catalog = fixture.FakeCatalog();
    final model = fixture.playback();
    addTearDown(model.dispose);
    await fixture.mount(tester, TvHome(catalog: catalog, playback: model));
    expect(find.text('随心唱'), findsNothing);
    expect(find.text('氛围空间'), findsNothing);
    expect(find.text('亲子'), findsNothing);
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(catalog.localCalls, 1);
    expect(find.text('本地测试歌曲'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('playlist return restores card focus', (tester) async {
    final model = fixture.playback();
    addTearDown(model.dispose);
    await fixture.mount(
        tester, TvHome(catalog: fixture.FakeCatalog(), playback: model));
    await fixture.activate(tester, 'playlist:p1');
    expect(find.byKey(const ValueKey('song:1')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<RemoteButton>(find.byKey(const ValueKey('playlist:p1')))
            .focusNode!
            .hasFocus,
        isTrue);
  });
  testWidgets('player returns to its opener and queue operates with OK',
      (tester) async {
    var index = -1;
    final model = fixture.playback(playIndex: (i) => index = i);
    addTearDown(model.dispose);
    await fixture.mount(
        tester, TvHome(catalog: fixture.FakeCatalog(), playback: model));
    await fixture.activate(tester, 'open-player');
    expect(find.byType(TvPlayer), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('player-queue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('player-queue:1')));
    await tester.pumpAndSettle();
    expect(index, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<RemoteButton>(find.byKey(const ValueKey('open-player')))
            .focusNode!
            .hasFocus,
        isTrue);
  });
  testWidgets('position ticks do not rebuild metadata or lose play focus',
      (tester) async {
    final model = fixture.playback();
    addTearDown(model.dispose);
    var builds = 0;
    await fixture.mount(
        tester,
        PlaybackSlice(
            playback: model,
            select: (d) => d.song,
            builder: (_, data) {
              builds++;
              return Text(data.song.title);
            }));
    final before = builds;
    for (var i = 0; i < 8; i++) {
      model.value =
          WidePlaybackData(song: fixture.song, position: Duration(seconds: i));
      await tester.pump();
    }
    expect(builds, before);
    model.value =
        const WidePlaybackData(song: MediaItem(id: 'other', title: '下一首'));
    await tester.pump();
    expect(builds, before + 1);
  });
  for (final size in [
    const Size(1920, 1080),
    const Size(1280, 720),
    const Size(960, 540)
  ]) {
    testWidgets('TV layout and player fit $size', (tester) async {
      final model = fixture.playback();
      addTearDown(model.dispose);
      await fixture.mount(
          tester, TvHome(catalog: fixture.PreviewCatalog(), playback: model),
          size: size);
      expect(tester.takeException(), isNull);
      await fixture.activate(tester, 'open-player');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('phone landscape keeps original theme at compact heights',
      (tester) async {
    final model = fixture.playback();
    addTearDown(model.dispose);
    for (final size in [const Size(844, 390), const Size(640, 300)]) {
      await fixture.mount(
          tester, TvPlayer(playback: model, perform: (a) => a(), phone: true),
          size: size);
      expect(tester.takeException(), isNull);
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.activeColor,
          Theme.of(tester.element(find.byType(TvPlayer))).primaryColor);
    }
  });
  test('phone icons use the same short-edge scale after rotation', () {
    final portrait = DisplayMode.designSize(const Size(390, 844));
    final landscape = DisplayMode.designSize(const Size(844, 390));
    expect(390 / portrait.width, closeTo(844 / landscape.width, .00001));
  });
  testWidgets(
      'landscape setting restores system rotation and supports portrait only',
      (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await DisplayMode.applyOrientation(false);
    expect(calls.last.arguments,
        ['DeviceOrientation.portraitUp', 'DeviceOrientation.portraitDown']);
    await DisplayMode.applyOrientation(true);
    expect(
        calls.last.arguments,
        unorderedEquals([
          'DeviceOrientation.portraitUp',
          'DeviceOrientation.portraitDown',
          'DeviceOrientation.landscapeLeft',
          'DeviceOrientation.landscapeRight'
        ]));
    await DisplayMode.applyOrientation(true, tv: true);
    expect(calls.last.arguments, [
      'DeviceOrientation.landscapeLeft',
      'DeviceOrientation.landscapeRight'
    ]);
  });

  if (const bool.fromEnvironment('BUJUAN_PREVIEW_CAPTURE')) {
    setUpAll(() async {
      final bytes =
          await File(const String.fromEnvironment('BUJUAN_PREVIEW_FONT'))
              .readAsBytes();
      await (FontLoader('Roboto')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
      await (FontLoader('packages/flutter_tabler_icons/tabler-icons')
            ..addFont(rootBundle.load(
                'packages/flutter_tabler_icons/assets/fonts/tabler-icons.ttf')))
          .load();
    });
    testWidgets('render TV and themed landscape widgets', (tester) async {
      final model = fixture.playback();
      addTearDown(model.dispose);
      model.value = WidePlaybackData(
          song: const MediaItem(
              id: 'preview',
              title: '不倦 · 音乐时光',
              artist: 'BuJuan',
              duration: Duration(minutes: 3)),
          queue: [fixture.song],
          lyrics: List.generate(
              8,
              (i) => LyricsLineModel()
                ..startTime = i * 8000
                ..mainText = [
                  '熟悉的按钮，换一种大屏布局',
                  '用遥控器寻找喜欢的歌',
                  '让音乐与歌词同步',
                  '本地音乐也在这里'
                ][i % 4]),
          position: const Duration(seconds: 12),
          playing: true);
      final root = GlobalKey();
      await fixture.mount(
          tester,
          RepaintBoundary(
              key: root,
              child:
                  TvHome(catalog: fixture.PreviewCatalog(), playback: model)));
      Future<void> capture(String name) async {
        expect(tester.takeException(), isNull);
        final boundary =
            root.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
                  '${const String.fromEnvironment('BUJUAN_PREVIEW_PATH')}/$name')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('tv-home.png');
      await fixture.activate(tester, 'open-player');
      await capture('tv-player.png');
      await tester.pumpWidget(const SizedBox.shrink());
      await fixture.mount(
          tester,
          RepaintBoundary(
              key: root,
              child: Theme(
                  data: AppTheme.light.copyWith(
                      textTheme:
                          AppTheme.light.textTheme.apply(fontFamily: "Roboto")),
                  child: RemoteFocusStyle(
                      color: AppTheme.light.primaryColor,
                      fill: AppTheme.light.primaryColor.withOpacity(.12),
                      selection: AppTheme.light.primaryColor.withOpacity(.06),
                      child: Scaffold(
                          body: Column(children: [
                        Expanded(
                            child: TvPlayer(
                                playback: model,
                                perform: (a) => a(),
                                phone: true))
                      ]))))),
          size: const Size(844, 390));
      await capture('phone-player-landscape.png');
    });
  }
}
