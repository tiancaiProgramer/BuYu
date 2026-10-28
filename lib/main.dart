import 'common/music/qq_music.dart';
import 'common/music/qq_discovery_probe.dart';
import 'common/music/unified_library.dart';
import 'common/music/favorites_auto_sync.dart';
import 'common/constants/key.dart';
import 'common/appearance_store.dart';
import 'common/display_mode.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:on_audio_edit/on_audio_edit.dart';
import 'pages/local/local_controller.dart';
import 'pages/local/netease_controller.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:auto_route/auto_route.dart';

import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/constants/platform_utils.dart';
import 'package:bujuan/common/netease_api/netease_music_api.dart';
import 'package:bujuan/pages/album/controller.dart';
import 'package:bujuan/pages/home/home_binding.dart';
import 'package:bujuan/pages/index/cound_controller.dart';
import 'package:bujuan/pages/index/index_controller.dart';
import 'package:bujuan/pages/play_list/playlist_controller.dart';
import 'package:bujuan/pages/playlist_manager/playlist_manager_controller.dart';
import 'package:bujuan/pages/user/user_controller.dart';
import 'package:bujuan/routes/router.gr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:window_manager/window_manager.dart';

import 'common/constants/colors.dart';

main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final getIt = GetIt.instance;
  await _initAudioServer(getIt);
  final rootRouter = getIt<RootRouter>();
  if (PlatformUtils.isAndroid) {
    // await FlutterDisplayMode.setHighRefreshRate();
    // SystemChrome.setEnabledSystemUIMode(
    //   SystemUiMode.edgeToEdge,
    // );
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark.copyWith(
      // 沉浸式状态栏（仅安卓）
      statusBarColor: Colors.transparent,
      // 沉浸式导航指示器
      systemNavigationBarColor: Colors.transparent,
    ));
  }
  await DisplayMode.applyOrientation(
      getIt<Box>().get(landscapeAdaptationSp, defaultValue: true));
  //外部
  // final rootNavigatorKey = GlobalKey<NavigatorState>();
  // final shellNavigatorKey = GlobalKey<NavigatorState>();
  // final router = GoRouter(
  //   navigatorKey: rootNavigatorKey,
  //   routes: [
  //     ShellRoute(navigatorKey: shellNavigatorKey, builder: (BuildContext context, GoRouterState state, Widget child) => Outside(child: child), routes: [
  //       GoRoute(path: '/', builder: (c, s) => const HomePage(), routes: [
  //         GoRoute(path: 'playlist', builder: (c, s) => PlayList(s.extra! as Play)),
  //       ]),
  //       GoRoute(path: '/user', builder: (c, s) => const User()),
  //       GoRoute(path: '/login', builder: (c, s) => const LoginViewPage()),
  //     ])
  //   ],
  // );
  // SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge).then((value) => runApp(ProviderScope(
  //     child: ScreenUtilInit(
  //         designSize: const Size(750, 1334),
  //         minTextAdapt: true,
  //         splitScreenMode: true,
  //         builder: (context, child) {
  //           return MaterialApp.router(
  //             // showPerformanceOverlay: true,
  //             theme: AppTheme.light,
  //             routerConfig: router,
  //           );
  //         }))));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge).then((value) => runApp(AdaptiveBujuanApp(builder: (land) => ScreenUtilInit(
        designSize: DisplayMode.designSize(DisplayMode.windowSize),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (BuildContext context, Widget? child) {
          HomeBinding().dependencies();
          return GetMaterialApp.router(
            title: "BuYu",
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            // showPerformanceOverlay: true,
            // checkerboardOffscreenLayers: true,
            // checkerboardRasterCacheImages: true,
            themeMode: ThemeMode.system,
            routerDelegate: rootRouter.delegate(navigatorObservers: () => [MyObserver()]),
            routeInformationParser: rootRouter.defaultRouteParser(),
            debugShowCheckedModeBanner: false,
            builder: (_, router) => MediaQuery(data: DisplayMode.safeMedia(MediaQuery.of(_), View.of(_).devicePixelRatio), child: router!),
          );
        },
      ))));
}

class MyObserver extends AutoRouterObserver {
  _clearOrPutController(String name, {bool del = false}) {
    if (name.isEmpty) return;
    switch (name) {
      case 'AlbumView':
        del ? Get.delete<CloudController>() : Get.lazyPut<CloudController>(() => CloudController());
        break;
      case 'MainView':
        del ? Get.delete<IndexController>() : Get.lazyPut<IndexController>(() => IndexController());
        break;
      case 'UserView':
        del ? Get.delete<UserController>() : Get.lazyPut<UserController>(() => UserController());
        break;
      case 'PlayListView':
        del ? Get.delete<PlayListController>() : Get.lazyPut<PlayListController>(() => PlayListController());
        break;
      case 'AlbumDetails':
        del ? Get.delete<AlbumController>() : Get.lazyPut<AlbumController>(() => AlbumController());
        break;
      case 'LocalView':
        del ? Get.delete<Local>() : Get.lazyPut<Local>(() => Local());
        break;
      case 'NeteaseCacheView':
        del ? Get.delete<Netease>() : Get.lazyPut<Netease>(() => Netease());
        break;
      case 'PlaylistManagerView':
        del ? Get.delete<PlaylistManager>() : Get.lazyPut<PlaylistManager>(() => PlaylistManager());
        break;
    }
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    _clearOrPutController(route.settings.name ?? '');
    print('New route pushed: ${route.settings.name}');
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    // TODO: implement didRemove
    super.didRemove(route, previousRoute);
    _clearOrPutController(route.settings.name ?? '', del: true);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    // TODO: implement didPop
    super.didPop(route, previousRoute);
    _clearOrPutController(route.settings.name ?? '', del: true);
  }


  // only override to observer tab routes
  @override
  void didInitTabRoute(TabPageRoute route, TabPageRoute? previousRoute) {}

  @override
  void didChangeTabRoute(TabPageRoute route, TabPageRoute previousRoute) {}
}

Future<void> _initAudioServer(getIt) async {
  getIt.registerSingleton<RootRouter>(RootRouter(Get.key));
  getIt.registerSingleton<AudioPlayer>(AudioPlayer());
  final audioSession = await AudioSession.instance;
  await audioSession.configure(const AudioSessionConfiguration.music());
  getIt.registerSingleton<OnAudioQuery>(OnAudioQuery());
  getIt.registerSingleton<OnAudioEdit>(OnAudioEdit());
  getIt.registerSingleton<ZoomDrawerController>(ZoomDrawerController());
  await Hive.initFlutter('BuJuan');
  getIt.registerSingleton<Box>(await Hive.openBox('cache'));
  await AppearanceStore(getIt<Box>()).migrate();
  await NeteaseMusicApi.init(debug: false);
  final qq = QqMusic.instance;
  await qq.restore();
  if (qq.loggedIn) qq.refreshProfile().catchError((_) {});
  if (const bool.fromEnvironment('BUYU_DISCOVERY_PROBE')) {
    runQqDiscoveryProbe(qq);
  }
  final favoritesSync = FavoritesAutoSync(UnifiedLibrary.instance);
  getIt.registerSingleton<FavoritesAutoSync>(favoritesSync, dispose: (sync) => sync.dispose());
  favoritesSync.start();
  if (qq.loggedIn) qq.userPlaylists().catchError((_) => qq.playlists);
  getIt.registerSingleton<BujuanAudioHandler>(await AudioService.init<BujuanAudioHandler>(
    builder: () => BujuanAudioHandler(),
    config: const AudioServiceConfig(
      androidStopForegroundOnPause: false,
      androidNotificationChannelId: 'com.sixbugs.bujuan.channel.audio',
      androidNotificationChannelName: 'Music playback',
      androidNotificationIcon: 'drawable/audio_service_icon',
    ),
  ));
}

Future<void> _initWindowManager() async {
  if (PlatformUtils.isWindows || PlatformUtils.isMacOS) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1080, 720),
      minimumSize: Size(1080, 720),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
}
