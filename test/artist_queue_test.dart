import 'dart:convert';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/common/display_mode.dart';
import 'package:bujuan/common/downloads.dart';
import 'package:bujuan/common/song_artists.dart';
import 'package:bujuan/common/netease_api/src/api/play/bean.dart';
import 'package:bujuan/pages/artists/artists_view.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/pages/home/view/z_recommend_view.dart';
import 'package:bujuan/pages/home/view/z_playlist_view.dart';
import 'package:bujuan/widget/landscape_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'phone_rotation_test.dart' show OfflineHome;
import 'playback_regression_test.dart' show FakePlayer, TestApiPaths;
import 'package:bujuan/common/netease_api/src/netease_api.dart';

void main() {
  test('artist metadata supports old queues, multiple artists and slashes inside names', () {
    final song = MediaItem(id: '1', title: '歌', extras: {'artist': [
      {'id': 1, 'name': 'AC / DC'}, {'id': 2, 'name': '歌手二'}].map(jsonEncode).join(' / ')});
    expect(SongArtists.fromSong(song).map((a) => a.name), ['AC / DC', '歌手二']);
    expect(SongArtists.fromSong(const MediaItem(id: '1', title: '歌', artist: '歌手', extras: {'artist': 'bad json'})).single.name, '歌手');
  });
  for (final size in [const Size(390, 844), const Size(844, 390), const Size(640, 300)]) {
    testWidgets('artist entries, details and playing queue work at $size', (tester) async {
      tester.view.devicePixelRatio = 1; tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio); addTearDown(tester.view.resetPhysicalSize);
      final resources = await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('bujuan-artist-ui');
        Hive.init(dir.path); final box = await Hive.openBox('artists');
        await NeteaseMusicApi.init(provider: TestApiPaths(dir.path));
        final handler = BujuanAudioHandler(player: FakePlayer(), box: box, restoreQueue: false,
            urlResolver: (_) async => '/tmp/audio-test.flac');
        return (dir, box, handler);
      });
      final (dir, box, handler) = resources!;
      GetIt.instance.registerSingleton<Box>(box);
      GetIt.instance.registerSingleton<BujuanAudioHandler>(handler);
      GetIt.instance.registerSingleton<ZoomDrawerController>(ZoomDrawerController());
      Home? home;
      Future<void> mount(Widget page) async {
        await tester.pumpWidget(ScreenUtilInit(designSize: DisplayMode.designSize(size), builder: (_, __) {
          home ??= Get.put<Home>(OfflineHome());
          return GetMaterialApp(theme: AppTheme.light, home: Scaffold(body: page));
        }));
        await tester.pumpAndSettle();
      }
      await mount(RecommendView(artistLoader: (a) async => a, songsLoader: (_) async => List.generate(6, (i) => MediaItem(id: 'recommended:$i', title: '推荐歌曲 $i', artist: '推荐歌手'))));
      home!.mediaItem.value = MediaItem(id: '123', title: '播放中的歌', extras: {'artist': List.generate(3, (i) => jsonEncode({'id': '$i', 'name': '歌手 $i'})).join(' / ')});
      await tester.pumpAndSettle();
      expect(find.text('歌手 0'), findsOneWidget);
      expect(find.text('歌手 2'), findsOneWidget);
      if (size.width > size.height) {
        expect(find.text('歌手歌曲推荐'), findsOneWidget);
      }
      if (size.width > size.height) {
        expect(tester.getRect(find.text('推荐歌曲 0')).top, tester.getRect(find.text('推荐歌曲 1')).top);
      }
      final artist = Artists()..id = '1'..name = '歌手详情'..briefDesc = List.filled(10, '歌手介绍内容。').join();
      await mount(ArtistDetailBody(artist: artist));
      expect(find.text('歌手详情'), findsOneWidget); expect(tester.takeException(), isNull);
      final songs = List.generate(8, (i) => MediaItem(id: '$i', title: '队列歌曲 $i', artist: '歌手'));
      await tester.runAsync(() => handler.changeQueueLists(songs));
      home!.mediaItems.assignAll(songs); home!.mediaItem.value = songs.first; home!.fm.value = true;
      await mount(const ZPlayListView());
      if (size.width > size.height) {
        expect(tester.getRect(find.text('队列歌曲 0')).top, tester.getRect(find.text('队列歌曲 2')).top);
      }
      await tester.runAsync(() => tester.tap(find.text('队列歌曲 1'))); await tester.pump();
      expect(handler.mediaItem.value!.id, '1');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink()); Get.reset(); await GetIt.instance.reset();
      await tester.runAsync(() async { await handler.dispose(); await box.close(); await dir.delete(recursive: true); });
    });
  }
}
