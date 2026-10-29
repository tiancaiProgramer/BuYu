// Community maintenance and new features: tiancaiProgramer.
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/common/constants/key.dart';
import 'package:bujuan/common/display_mode.dart';
import 'package:bujuan/common/music/local_folders.dart';
import 'package:bujuan/common/music/music_source.dart';
import 'package:bujuan/common/music/qq_music.dart';
import 'package:bujuan/common/netease_api/src/api/play/bean.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/pages/music/playlist_source_filter.dart';
import 'package:bujuan/pages/setting/settring_view.dart';
import 'package:bujuan/pages/user/home_account_visibility.dart';
import 'package:bujuan/pages/user/user_controller.dart';
import 'package:bujuan/pages/user/user_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'download_preferences_test.dart' show MemoryBox;
import 'phone_rotation_test.dart' show OfflineHome;
import 'playback_regression_test.dart' show FakePlayer;

class _User extends UserController {
  @override
  void onReady() {}
}

class _Qq extends QqMusic {
  bool signedIn = false;
  @override
  bool get loggedIn => signedIn;
  void update(bool value) {
    signedIn = value;
    notifyListeners();
  }
}

void main() {
  for (final hide in [false, true]) {
    for (final netease in [false, true]) {
      for (final qq in [false, true]) {
        test('homepage visibility hide=$hide, netease=$netease, qq=$qq', () {
          final policy = HomeAccountVisibility(
              hideUnlogged: hide, neteaseLoggedIn: netease, qqLoggedIn: qq);
          expect(policy.showNetease, !hide || netease);
          expect(policy.showQq, !hide || qq);
          expect(policy.showDiscovery, !hide || netease || qq);
          expect(policy.musicSources.contains(MusicSource.netease),
              !hide || netease);
          expect(policy.musicSources.contains(MusicSource.qq), !hide || qq);
          expect(policy.sources.contains(PlaylistSource.netease),
              !hide || netease);
          expect(policy.sources.contains(PlaylistSource.qq), !hide || qq);
          expect(policy.effectiveSource(PlaylistSource.netease),
              hide && !netease ? PlaylistSource.all : PlaylistSource.netease);
        });
      }
    }
  }
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets(
        'setting persists and the real homepage hides only unavailable platforms at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final box = MemoryBox();
      final handler = BujuanAudioHandler(
          player: FakePlayer(), box: box, restoreQueue: false);
      final qq = _Qq();
      qq.playlists = [
        const SourcePlaylist(
            id: 'qq-list',
            name: '缓存QQ歌单',
            image: '',
            count: 1,
            source: MusicSource.qq)
      ];
      GetIt.I.registerSingleton<Box>(box);
      GetIt.I.registerSingleton<BujuanAudioHandler>(handler);
      GetIt.I.registerSingleton<ZoomDrawerController>(ZoomDrawerController());
      GetIt.I.registerSingleton<QqMusic>(qq);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (_) async => {
                'appName': 'BuYu',
                'packageName': 'test',
                'version': '2.0.8',
                'buildNumber': '2107'
              });
      Home? home;
      await LocalFolders.instance.create('通勤收藏');
      Widget app(Widget page) => ScreenUtilInit(
          designSize: DisplayMode.designSize(size),
          builder: (_, __) {
            home ??= Get.put<Home>(OfflineHome());
            if (!Get.isRegistered<UserController>()) {
              final user = Get.put<UserController>(_User());
              user.loading.value = false;
              user.playlist.add(Play()
                ..id = 'ne-list'
                ..name = '缓存网易歌单');
              user.playlistSource.value = PlaylistSource.netease;
            }
            return GetMaterialApp(theme: AppTheme.light, home: page);
          });
      await tester.pumpWidget(app(const SettingView()));
      await tester.pumpAndSettle();
      expect(home!.hideUnlogged.value, false);
      await tester
          .ensureVisible(find.byKey(const ValueKey('hide-unlogged-setting')));
      await tester.tap(find.byKey(const ValueKey('hide-unlogged-setting')));
      await tester.pumpAndSettle();
      expect(box.get(hideUnloggedSp), true);
      await tester.pumpWidget(app(const UserViewP()));
      await tester.pumpAndSettle();
      expect(find.text('聚合收藏'), findsOneWidget);
      expect(find.text('通勤收藏'), findsOneWidget);
      expect(find.text('每日'), findsNothing);
      expect(find.text('云盘'), findsOneWidget);
      expect(find.textContaining('缓存网易歌单'), findsNothing);
      expect(find.textContaining('缓存QQ歌单'), findsNothing);
      expect(find.byType(PlaylistSourceFilter), findsNothing);
      // A newly available QQ account reappears; an old hidden NetEase filter
      // cannot leave the homepage looking empty.
      qq.update(true);
      await tester.pumpAndSettle();
      expect(find.textContaining('缓存QQ歌单'), findsOneWidget);
      expect(find.text('每日'), findsOneWidget);
      expect(find.text('FM'), findsOneWidget);
      expect(find.text('播客'), findsOneWidget);
      expect(find.byKey(const ValueKey('playlist-source:qq')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('playlist-source:netease')), findsNothing);
      await home!.setHideUnlogged(false);
      await tester.pumpAndSettle();
      expect(find.text('每日'), findsOneWidget);
      expect(find.byKey(const ValueKey('playlist-source:netease')),
          findsOneWidget);
      expect(find.textContaining('缓存网易歌单'), findsOneWidget);
      expect(find.text('聚合收藏'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      Get.reset();
      await GetIt.I.reset();
      qq.dispose();
      await tester.runAsync(handler.dispose);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'), null);
    });
  }
}
