import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/common/display_mode.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/pages/home/view/home_view.dart';
import 'package:bujuan/pages/home/view/body_view.dart';
import 'package:bujuan/widget/app_bar.dart';
import 'package:bujuan/widget/my_get_view.dart';
import 'package:bujuan/widget/song_collection.dart';
import 'package:bujuan/pages/play_list/playlist_view.dart';
import 'package:bujuan/widget/simple_extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'phone_rotation_test.dart' show OfflineHome;
import 'playback_regression_test.dart' show FakePlayer;

void main() {
  testWidgets('daily artwork keeps the portrait song row size', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var played = -1;
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(750, 1334),
        builder: (_, __) => MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
                body: Builder(
                    builder: (context) => buildSongCollection(context,
                        songs: const [
                          MediaItem(id: '1', title: '每日歌曲', artist: '歌手')
                        ],
                        storageId: 'daily',
                        showArtwork: true,
                        onPlay: (i) => played = i))))));
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.itemExtent, closeTo(130 * 390 / 750, .001));
    expect(tester.widget<SongItem>(find.byType(SongItem)).showArtwork, isTrue);
    expect(find.byType(SimpleExtendedImage), findsOneWidget);
    await tester.tap(find.text('每日歌曲'));
    await tester.pump();
    expect(played, 0);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(844, 390), const Size(640, 300)]) {
    testWidgets(
        'cold landscape daily returns without creating portrait player at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final resources = await tester.runAsync(() async {
        final dir =
            await Directory.systemTemp.createTemp('bujuan-cold-landscape');
        Hive.init(dir.path);
        final box = await Hive.openBox('cold-navigation');
        final handler = BujuanAudioHandler(
            player: FakePlayer(), box: box, restoreQueue: false);
        return (dir, box, handler);
      });
      final (dir, box, handler) = resources!;
      GetIt.instance.registerSingleton<Box>(box);
      GetIt.instance.registerSingleton<BujuanAudioHandler>(handler);
      GetIt.instance
          .registerSingleton<ZoomDrawerController>(ZoomDrawerController());
      final navigator = GlobalKey<NavigatorState>();
      final songs = List.generate(
          30, (i) => MediaItem(id: '$i', title: '歌曲 $i', artist: '歌手'));
      var played = -1;
      Home? home;
      await tester.pumpWidget(ScreenUtilInit(
          designSize: DisplayMode.designSize(size),
          builder: (_, __) {
            home ??= Get.put<Home>(OfflineHome());
            home!.pages = List.generate(4, (i) => Text('播放页 $i'));
            return GetMaterialApp(
                theme: AppTheme.light,
                home: HomeView(
                    body: BodyView(
                        child: Navigator(
                            key: navigator,
                            onGenerateRoute: (settings) => MaterialPageRoute(
                                settings: settings,
                                builder: (context) => settings.name == '/daily'
                                    ? MyGetView(
                                        child: Scaffold(
                                            appBar: MyAppBar(
                                                title: const Text('每日')),
                                            body: buildSongCollection(context,
                                                songs: songs,
                                                storageId: 'daily',
                                                showArtwork: true,
                                                onPlay: (i) => played = i)))
                                    : const Scaffold(body: Text('首页')))))));
          }));
      await tester.pump(const Duration(milliseconds: 600));
      expect(home!.panelController.isAttached, false);
      for (var attempt = 0; attempt < 2; attempt++) {
        navigator.currentState!.pushNamed('/daily');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        final grid = tester.widget<GridView>(find.byType(GridView));
        final delegate =
            grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
        expect(delegate.crossAxisCount, 3);
        expect(
            tester
                .widgetList<SongItem>(find.byType(SongItem))
                .every((item) => item.showArtwork),
            isTrue);
        expect(
            find.descendant(
                of: find.byType(GridView),
                matching: find.byType(SimpleExtendedImage)),
            findsWidgets);
        expect(delegate.mainAxisExtent, closeTo(112 * 2 / 3, .001));
        await tester.tap(find.text('歌曲 0'));
        await tester.pump();
        expect(played, 0);
        if (attempt == 0) {
          await tester.tap(find.byType(BackButton));
        } else {
          await navigator.currentState!.maybePop();
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('每日'), findsNothing);
        expect(find.text('首页'), findsOneWidget);
        expect(home!.panelController.isAttached, false);
        expect(tester.takeException(), isNull);
      }
      final refresh = RefreshController();
      var loadCount = 0;
      await tester.pumpWidget(ScreenUtilInit(
          designSize: DisplayMode.designSize(size),
          builder: (_, __) => MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                  body: StatefulBuilder(
                      builder: (context, update) => SmartRefresher(
                          controller: refresh,
                          enablePullUp: true,
                          onLoading: () {
                            update(() {
                              songs.addAll(List.generate(
                                  30,
                                  (i) => MediaItem(
                                      id: 'more:$i', title: '新增歌曲 $i')));
                              loadCount++;
                            });
                            refresh.loadComplete();
                          },
                          child: buildSongCollection(context,
                              songs: songs,
                              storageId: 'cloud',
                              portraitShrinkWrap: true,
                              onPlay: (i) => played = i)))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      refresh.position!.jumpTo(refresh.position!.maxScrollExtent);
      await tester.pumpAndSettle();
      refresh.requestLoading(needMove: false);
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(
          tester
              .widgetList<SongItem>(find.byType(SongItem))
              .every((item) => !item.showArtwork),
          isTrue);
      expect(loadCount, 1);
      expect(songs.length, 60);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      refresh.dispose();
      Get.reset();
      await GetIt.instance.reset();
      await tester.runAsync(() async {
        await handler.dispose();
        await box.close();
        await dir.delete(recursive: true);
      });
    });
  }
}
