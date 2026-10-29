// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/common/music/local_folders.dart';
import 'package:bujuan/common/music/mixed_search.dart';
import 'package:bujuan/common/music/music_source.dart';
import 'package:bujuan/common/music/qq_music.dart';
import 'package:bujuan/common/netease_api/src/api/play/bean.dart';
import 'package:bujuan/common/netease_api/src/dio_ext.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/pages/music/discovery_sources.dart';
import 'package:bujuan/pages/music/mixed_search_view.dart';
import 'package:bujuan/pages/music/playlist_source_filter.dart';
import 'package:bujuan/pages/playlist_manager/playlist_manager_view.dart';
import 'package:bujuan/pages/search/search_view.dart';
import 'package:bujuan/pages/user/user_controller.dart';
import 'package:bujuan/pages/play_list/playlist_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:get/get.dart' hide Response;
import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'download_preferences_test.dart' show MemoryBox;
import 'phone_rotation_test.dart' show OfflineHome;
import 'playback_regression_test.dart' show FakePlayer;

class Account extends QqMusic {
  bool active = true;
  @override
  bool get loggedIn => active;
  @override
  String get account => active ? '123' : '';
  @override
  Future<List<MediaItem>> search(String keyword,
          {int page = 1, int limit = 20}) async =>
      [qqSong];
  void setActive(bool value) {
    active = value;
    notifyListeners();
  }
}

class User extends UserController {
  @override
  void onReady() {}
}

const neSong = MediaItem(id: '1', title: '网易测试歌曲');
const qqSong = MediaItem(id: 'qq:1', title: 'QQ测试歌曲', extras: {'source': 'qq'});

void main() {
  late MemoryBox box;
  late BujuanAudioHandler handler;
  late Account qq;
  Home? home;

  setUp(() {
    Get.testMode = true;
    box = MemoryBox();
    handler =
        BujuanAudioHandler(player: FakePlayer(), box: box, restoreQueue: false);
    qq = Account();
    GetIt.I.registerSingleton<Box>(box);
    GetIt.I.registerSingleton<BujuanAudioHandler>(handler);
    GetIt.I.registerSingleton<ZoomDrawerController>(ZoomDrawerController());
    GetIt.I.registerSingleton<QqMusic>(qq);
    home = null;
  });
  tearDown(() async {
    Get.reset();
    await GetIt.I.reset();
    qq.dispose();
    await handler.dispose();
  });
  Widget app(Widget page, Size size) => ScreenUtilInit(
      designSize: Size(
          size.width > size.height ? size.width / size.height * 750 : 750,
          size.width > size.height ? 750 : 1334),
      builder: (_, __) {
        home ??= Get.put<Home>(OfflineHome());
        if (!Get.isRegistered<UserController>())
          Get.put<UserController>(User());
        return GetMaterialApp(
            theme: AppTheme.light, home: Scaffold(body: page));
      });
  void screen(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    for (final id in ['daily', 'podcast', 'home']) {
      testWidgets(
          '$id obeys hide preference, logout and empty accounts at $size',
          (tester) async {
        screen(tester, size);
        var neLoads = 0, qqLoads = 0;
        Widget page() => DiscoverySources(
            id: id,
            publicSources: id == 'home'
                ? const {MusicSource.netease, MusicSource.qq}
                : const {},
            netease: (_) {
              neLoads++;
              return const Text('网易内容');
            },
            qq: (_) {
              qqLoads++;
              return const Text('QQ内容');
            });
        await tester.pumpWidget(app(page(), size));
        await tester.pumpAndSettle();
        home!.loginStatus.value = LoginStatus.login;
        await tester.pumpAndSettle();
        await tester
            .tap(find.byKey(const ValueKey('discovery-source:netease')));
        await tester.pumpAndSettle();
        await home!.setHideUnlogged(true);
        await tester.pumpAndSettle();
        home!.loginStatus.value = LoginStatus.noLogin;
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('discovery-source:netease')),
            findsNothing);
        expect(
            find.byKey(const ValueKey('discovery-source:qq')), findsOneWidget);
        expect(find.text('QQ内容'), findsOneWidget);
        final beforeEmpty = (neLoads, qqLoads);
        qq.setActive(false);
        await tester.pumpAndSettle();
        expect(find.byType(ChoiceChip), findsNothing);
        expect(find.text('暂无已登录的平台，请先登录音乐账号'), findsOneWidget);
        expect((neLoads, qqLoads), beforeEmpty);
        await home!.setHideUnlogged(false);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('discovery-source:netease')),
            findsOneWidget);
        expect(
            find.byKey(const ValueKey('discovery-source:qq')), findsOneWidget);
        await home!.setHideUnlogged(true);
        qq.setActive(true);
        await tester.pumpAndSettle();
        expect(find.text('QQ内容'), findsOneWidget);
        // An obsolete saved choice cannot reopen a now-hidden public source.
        await box.put('DISCOVERY_SOURCE_$id', 'netease');
        await tester.pumpWidget(app(const SizedBox(), size));
        await tester.pumpAndSettle();
        await tester.pumpWidget(app(page(), size));
        await tester.pumpAndSettle();
        expect(find.text('QQ内容'), findsOneWidget);
        expect(find.byKey(const ValueKey('discovery-source:netease')),
            findsNothing);
        home!.loginStatus.value = LoginStatus.login;
        qq.setActive(false);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('discovery-source:qq')), findsNothing);
        expect(find.byKey(const ValueKey('discovery-source:netease')),
            findsOneWidget);
        expect(find.text('网易内容'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets(
        'search hides old results and late responses, then restores sources at $size',
        (tester) async {
      screen(tester, size);
      var neCalls = 0, qqCalls = 0;
      final lateResult = Completer<List<MediaItem>>();
      final search = MixedSearch(providers: {
        MusicSource.netease: (_, __) {
          neCalls++;
          return lateResult.future;
        },
        MusicSource.qq: (_, __) async {
          qqCalls++;
          return [qqSong];
        },
      });
      await tester.pumpWidget(
          app(MixedSongSearchView(query: '测试', search: search), size));
      await tester.pump();
      expect(neCalls, 1);
      await tester.tap(find.widgetWithText(ChoiceChip, '网易云'));
      await tester.pump();
      await home!.setHideUnlogged(true);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ChoiceChip, '网易云'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'QQ音乐'), findsOneWidget);
      expect(find.byType(SongItem), findsOneWidget);
      lateResult.complete([neSong]);
      await tester.pumpAndSettle();
      expect(find.textContaining('网易测试歌曲'), findsNothing);
      expect(neCalls, 1);
      expect(qqCalls, 2);
      qq.setActive(false);
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(SongItem), findsNothing);
      expect(find.text('暂无已登录的平台，请先登录音乐账号'), findsOneWidget);
      expect(qqCalls, 2);
      await home!.setHideUnlogged(false);
      await tester.pumpAndSettle();
      expect(neCalls, 2);
      expect(qqCalls, 3);
      expect(find.byType(SongItem), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      search.dispose();
    });

    testWidgets(
        'full search hides NetEase tabs and hot words, then falls back on logout at $size',
        (tester) async {
      screen(tester, size);
      var netRequests = 0;
      final offline = InterceptorsWrapper(onRequest: (options, handler) {
        netRequests++;
        handler.resolve(Response(requestOptions: options, data: {
          'code': 200,
          'result': {
            'hots': [],
            'songs': [],
            'playlists': [],
            'albums': [],
            'artists': []
          }
        }));
      });
      Https.dio.interceptors.add(offline);
      addTearDown(() => Https.dio.interceptors.remove(offline));
      await tester.pumpWidget(app(const SizedBox(), size));
      await home!.setHideUnlogged(true);
      final search = MixedSearch(providers: {
        MusicSource.netease: (_, __) async => [neSong],
        MusicSource.qq: (_, __) async => [qqSong],
      });
      await tester.pumpWidget(app(SearchView(songSearch: search), size));
      await tester.pumpAndSettle();
      expect(netRequests, 0);
      expect(find.text('输入关键词搜索QQ音乐'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'test');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('网易歌单'), findsNothing);
      expect(find.text('网易专辑'), findsNothing);
      expect(find.text('网易歌手'), findsNothing);
      expect(netRequests, 0);
      home!.loginStatus.value = LoginStatus.login;
      await tester.pumpAndSettle();
      expect(find.text('网易专辑'), findsOneWidget);
      tester.widget<TabBar>(find.byType(TabBar)).controller!.index = 2;
      home!.loginStatus.value = LoginStatus.noLogin;
      await tester.pumpAndSettle();
      expect(find.text('网易专辑'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'QQ音乐'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      search.dispose();
    });

    testWidgets(
        'manager hides cached cloud lists and create options, preserving local folders at $size',
        (tester) async {
      screen(tester, size);
      qq.playlists = [
        const SourcePlaylist(
            id: 'qq-list', name: '缓存QQ歌单', source: MusicSource.qq)
      ];
      await tester.pumpWidget(app(const PlaylistManagerView(), size));
      await tester.pumpAndSettle();
      final user = UserController.to;
      user.playlist.add(Play()
        ..id = 'ne-list'
        ..name = '缓存网易歌单');
      user.playlistSource.value = PlaylistSource.netease;
      await LocalFolders.instance.create('我的本地分类');
      await home!.setHideUnlogged(true);
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('playlist-source:netease')), findsNothing);
      expect(find.text('缓存网易歌单'), findsNothing);
      expect(find.text('缓存QQ歌单'), findsOneWidget);
      expect(find.text('我的本地分类'), findsOneWidget);
      expect(find.text('聚合收藏'), findsOneWidget);
      await tester.tap(find.byTooltip('新建文件夹或歌单'));
      await tester.pumpAndSettle();
      expect(find.text('新建本地文件夹'), findsOneWidget);
      expect(find.text('新建网易云歌单'), findsNothing);
      expect(find.text('新建QQ音乐歌单'), findsOneWidget);
      qq.setActive(false);
      await tester.pumpAndSettle();
      expect(find.text('新建QQ音乐歌单'), findsNothing);
      expect(find.text('新建本地文件夹'), findsOneWidget);
      Navigator.of(tester.element(find.text('新建本地文件夹'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('缓存QQ歌单'), findsNothing);
      expect(find.text('我的本地分类'), findsOneWidget);
      await home!.setHideUnlogged(false);
      await tester.pumpAndSettle();
      expect(find.text('缓存网易歌单'), findsOneWidget);
      expect(find.byKey(const ValueKey('playlist-source:netease')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
