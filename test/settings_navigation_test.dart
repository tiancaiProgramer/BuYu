// Community maintenance and new features: tiancaiProgramer.
import 'dart:ui' as ui;
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/common/display_mode.dart';
import 'package:bujuan/common/music/qq_music.dart';
import 'package:bujuan/pages/home/drawer_navigation.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/pages/index/index_controller.dart';
import 'package:bujuan/pages/index/main_view.dart';
import 'package:bujuan/pages/local/local_controller.dart';
import 'package:bujuan/pages/local/local_view.dart';
import 'package:bujuan/pages/setting/settring_view.dart';
import 'package:bujuan/pages/user/user_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'download_preferences_test.dart' show MemoryBox;
import 'landscape_pages_test.dart' show OfflineDiscovery, OfflineLocal;
import 'phone_rotation_test.dart' show OfflineHome;
import 'playback_regression_test.dart' show FakePlayer;

class _Qq extends QqMusic {
  @override
  bool get loggedIn => true;
}

void main() {
  testWidgets('navigation waits for actual drawer completion beyond 200ms',
      (tester) async {
    final state = ValueNotifier(DrawerState.open);
    final drawer = ZoomDrawerController()
      ..stateNotifier = state
      ..close = () => state.value = DrawerState.closing;
    var completed = false;
    final closing = closeDrawerForNavigation(drawer)
        .then((ready) => completed = ready);
    await tester.pump(const Duration(milliseconds: 500));
    expect(completed, false);
    state.value = DrawerState.closed;
    await closing;
    expect(completed, true);
    state.dispose();
  });

  testWidgets('a drawer that cannot close does not start route navigation',
      (tester) async {
    final state = ValueNotifier(DrawerState.open);
    final drawer = ZoomDrawerController()..stateNotifier = state;
    final closing = closeDrawerForNavigation(drawer);
    await tester.pump(const Duration(seconds: 3));
    expect(await closing, false);
    state.dispose();
  });

  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    for (final dark in [false, true]) {
      testWidgets('QQ-only avatars and settings surface at $size, dark=$dark',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final box = MemoryBox();
        final audio = (await tester.runAsync(() async => BujuanAudioHandler(
            player: FakePlayer(), box: box, restoreQueue: false)))!;
        final drawer = ZoomDrawerController();
        final qq = _Qq();
        GetIt.I.registerSingleton<Box>(box);
        GetIt.I.registerSingleton<BujuanAudioHandler>(audio);
        GetIt.I.registerSingleton<ZoomDrawerController>(drawer);
        GetIt.I.registerSingleton<QqMusic>(qq);
        GetIt.I.registerSingleton<OnAudioQuery>(OnAudioQuery());
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/package_info'),
            (_) async => {
                  'appName': 'BuYu', 'packageName': 'test',
                  'version': '2.0.8', 'buildNumber': '2114'
                });
        final theme = dark ? AppTheme.dark : AppTheme.light;
        Home? home;
        var opened = 0;
        drawer.open = () => opened++;
        final boundary = GlobalKey();
        Widget app(Widget page) => ScreenUtilInit(
            designSize: DisplayMode.designSize(size),
            builder: (_, __) {
              home ??= Get.put<Home>(OfflineHome());
              home!.loginStatus.value = LoginStatus.noLogin;
              // A missing custom image must still cover old route text.
              home!.background.value = '/missing-wallpaper.png';
              if (!Get.isRegistered<IndexController>()) {
                Get.put<IndexController>(OfflineDiscovery()..loading.value = false);
                Get.put<Local>(OfflineLocal()..loading.value = false);
              }
              return GetMaterialApp(theme: theme,
                  home: RepaintBoundary(key: boundary,
                      child: Stack(fit: StackFit.expand, children: [
                        const ColoredBox(color: Color(0xffff00ff)), page
                      ])));
            });
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          Get.reset();
          await GetIt.I.reset();
          qq.dispose();
          await tester.runAsync(audio.dispose);
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              const MethodChannel('dev.fluttercommunity.plus/package_info'), null);
        });
        for (final page in [
          (const SettingViewL(), 'settings-account-avatar'),
          (const MainView(), 'discovery-account-avatar'),
          (const LocalView(), 'local-account-avatar'),
        ]) {
          await tester.pumpWidget(app(page.$1));
          await tester.pump(const Duration(milliseconds: 400));
          expect(home!.hasMusicAccount, true);
          await tester.tap(find.byKey(ValueKey(page.$2)));
          expect(opened, [
            'settings-account-avatar', 'discovery-account-avatar', 'local-account-avatar'
          ].indexOf(page.$2) + 1);
          if (page.$1 is SettingViewL) {
            await tester.pumpAndSettle();
            final pixel = await tester.runAsync(() async {
              final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary).toImage();
              final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
              final offset = ((size.height - 5).toInt() * image.width +
                  (size.width - 5).toInt()) * 4;
              final bytes = data!.buffer.asUint8List();
              final result = Color.fromARGB(bytes[offset + 3], bytes[offset],
                  bytes[offset + 1], bytes[offset + 2]);
              image.dispose();
              return result;
            });
            expect(pixel, theme.scaffoldBackgroundColor);
          }
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
