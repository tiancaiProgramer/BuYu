import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/common/display_mode.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/pages/home/view/home_view.dart';
import 'package:bujuan/pages/home/view/phone_landscape_player.dart';
import 'package:bujuan/pages/home/view/body_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bujuan/pages/user/personal_landscape.dart';
import 'package:bujuan/common/netease_api/src/api/play/bean.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:palette_generator/palette_generator.dart';
import 'playback_regression_test.dart' show FakePlayer;

class OfflineHome extends Home {
  @override
  void
      onReady() {} // The layout test does not start account or network services.
}

void main() {
  testWidgets('native cutout is applied to controls after a rotation',
      (tester) async {
    tester.view.devicePixelRatio = 3.25;
    tester.view.physicalSize = const Size(2670, 1200);
    var left = 140, top = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('bujuan/display'),
        (_) async => {'left': left, 'top': top, 'right': 0, 'bottom': 0});
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      DisplayMode.physicalCutout = EdgeInsets.zero;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('bujuan/display'), null);
    });
    await tester.pumpWidget(AdaptiveBujuanApp(
        builder: (_) => MaterialApp(
            builder: (context, child) => MediaQuery(
                data: DisplayMode.safeMedia(
                    MediaQuery.of(context), View.of(context).devicePixelRatio),
                child: child!),
            home: Scaffold(
                body: SafeArea(
                    child: Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                            key: const ValueKey('safe-control'),
                            width: 40,
                            height: 40)))))));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('safe-control'))).dx,
        closeTo(140 / 3.25, .01));
    left = 0;
    top = 140;
    tester.view.physicalSize = const Size(1200, 2670);
    await tester.pumpAndSettle();
    final position =
        tester.getTopLeft(find.byKey(const ValueKey('safe-control')));
    expect(position.dx, 0);
    expect(position.dy, closeTo(140 / 3.25, .01));
  });

  testWidgets('phone rotation retains route, scroll and open player',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final resources = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('bujuan-phone-ui');
      Hive.init(dir.path);
      final box = await Hive.openBox('rotation-test');
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
    final scroll = ScrollController();
    Home? home;
    var playlistTaps = 0;
    final liked = Play()
      ..id = 'liked'
      ..name = '喜欢的音乐'
      ..trackCount = 10;
    await tester.pumpWidget(AdaptiveBujuanApp(
        builder: (_) => ScreenUtilInit(
            designSize: DisplayMode.designSize(tester.view.physicalSize),
            builder: (_, __) {
              home ??= Get.put<Home>(OfflineHome());
              home!.pages = List.generate(
                  4, (i) => Center(child: Text('original page $i')));
              return GetMaterialApp(
                  theme: AppTheme.light,
                  home: HomeView(
                      body: BodyView(
                          child: Navigator(
                              key: navigator,
                              onGenerateRoute: (settings) => MaterialPageRoute(
                                  settings: settings,
                                  builder: (_) => settings.name == '/personal'
                                      ? PersonalLandscape(
                                          nickname: '',
                                          avatar: '',
                                          liked: liked,
                                          playlists: List.generate(
                                              2,
                                              (i) => Play()
                                                ..id = 'alignment:$i'
                                                ..name = '歌单 $i'),
                                          playlistFilter: Row(children: [
                                            const Expanded(child: Text('合并显示')),
                                            IconButton(
                                                key: const ValueKey(
                                                    'user-playlists-toggle'),
                                                onPressed: () {},
                                                icon: const Icon(
                                                    Icons.expand_less)),
                                          ]),
                                          actions: [
                                            PersonalAction(
                                                'FM', TablerIcons.vinyl, () {})
                                          ],
                                          onPlaylist: (_) => playlistTaps++,
                                          onManage: () {},
                                          onAvatar: () {},
                                          onSearch: () {})
                                      : ListView(
                                          controller:
                                              settings.name == '/details'
                                                  ? scroll
                                                  : null,
                                          children: List.generate(
                                              80,
                                              (i) => SizedBox(
                                                  height: 50,
                                                  child: Text(
                                                      '${settings.name} row $i')))))))));
            })));
    await tester.pump(const Duration(milliseconds: 300));
    tester.view.physicalSize = const Size(844, 390);
    await tester.pump(const Duration(milliseconds: 400));
    final drawer = tester.widget<ZoomDrawer>(find.byType(ZoomDrawer));
    expect(drawer.slideWidth, closeTo(390 * .256, .01));
    expect(drawer.menuScreenWidth, lessThan(drawer.slideWidth));
    tester.view.padding = const FakeViewPadding(right: 43);
    tester.view.viewPadding = const FakeViewPadding(right: 43);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    home!.myDrawerController.open!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(home!.myDrawerController.isOpen!(), isTrue);
    expect(tester.takeException(), isNull);
    final menuAvatar =
        tester.getRect(find.byKey(const ValueKey('menu-avatar')));
    final firstMenuAction =
        tester.getRect(find.byKey(const ValueKey('menu-action:0')));
    expect(menuAvatar.center.dx, closeTo(drawer.menuScreenWidth! / 2, .01));
    final firstShadow = find.byWidgetPredicate((widget) =>
        widget is Transform &&
        (widget.transform.storage[0] - .9).abs() < .0001);
    expect(firstShadow, findsOneWidget);
    final shadowContent =
        find.byWidget(tester.widget<Transform>(firstShadow).child!);
    expect(menuAvatar.center.dx,
        closeTo(tester.getTopLeft(shadowContent).dx / 2, .01));
    expect(firstMenuAction.center.dx, closeTo(menuAvatar.center.dx, .01));
    expect(firstMenuAction.top - menuAvatar.bottom, greaterThanOrEqualTo(24));
    tester.view.padding = const FakeViewPadding(left: 43);
    tester.view.viewPadding = const FakeViewPadding(left: 43);
    await tester.pump(const Duration(milliseconds: 400));
    final safeAction =
        tester.getRect(find.byKey(const ValueKey('menu-action:0')));
    expect(safeAction.left, greaterThanOrEqualTo(43));
    expect(safeAction.width, greaterThanOrEqualTo(48));
    // The cutout must move the shadow as well as the menu controls; otherwise
    // the controls are safe from the camera but painted beneath the shadow.
    final leftShadowEdge = tester
        .getTopLeft(find.byWidget(tester.widget<Transform>(firstShadow).child!))
        .dx;
    for (final control in [
      find.byKey(const ValueKey('menu-avatar')),
      for (var i = 0; i < 4; i++) find.byKey(ValueKey('menu-action:$i')),
    ]) {
      final bounds = tester.getRect(control);
      expect(bounds.left, greaterThanOrEqualTo(43));
      expect(bounds.right, lessThanOrEqualTo(leftShadowEdge + .01));
      expect(bounds.center.dx, closeTo(43 + menuAvatar.center.dx, .01));
    }
    final leftDrawer = tester.widget<ZoomDrawer>(find.byType(ZoomDrawer));
    expect(leftDrawer.slideWidth - drawer.slideWidth, closeTo(43, .01));
    expect(tester.takeException(), isNull);
    tester.view.padding = const FakeViewPadding(right: 43);
    tester.view.viewPadding = const FakeViewPadding(right: 43);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getRect(find.byKey(const ValueKey('menu-avatar'))).center.dx,
        closeTo(menuAvatar.center.dx, .01));
    expect(tester.widget<ZoomDrawer>(find.byType(ZoomDrawer)).slideWidth,
        closeTo(drawer.slideWidth, .01));
    tester.view.resetPadding();
    tester.view.resetViewPadding();
    await tester.pump(const Duration(milliseconds: 400));
    // A tablet has much more vertical space than the phone. The drawer must
    // distribute all four controls through that space instead of stacking them.
    for (final menuSize in [
      const Size(844, 390),
      const Size(1105.45, 692.36), // Connected 3040x1904 tablet at 440 dpi.
      const Size(1280, 800),
      const Size(1024, 600),
      const Size(640, 300),
    ]) {
      tester.view.physicalSize = menuSize;
      await tester.pump(const Duration(milliseconds: 800));
      final area =
          tester.getRect(find.byKey(const ValueKey('landscape-menu-actions')));
      final slot = area.height / 4;
      for (var i = 0; i < 4; i++) {
        final bounds = tester.getRect(find.byKey(ValueKey('menu-action:$i')));
        expect(bounds.center.dy, closeTo(area.top + slot * (i + .5), .01),
            reason: '$menuSize menu $i');
        expect(bounds.height, closeTo(slot, .01));
        expect(bounds.width, greaterThanOrEqualTo(48));
        expect(bounds.height, greaterThanOrEqualTo(48));
        expect(bounds.bottom, lessThanOrEqualTo(menuSize.height));
      }
      expect(tester.takeException(), isNull);
    }
    tester.view.physicalSize = const Size(640, 200);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.ensureVisible(find.byKey(const ValueKey('menu-action:3')));
    await tester.pumpAndSettle();
    final lastMenu =
        tester.getRect(find.byKey(const ValueKey('menu-action:3')));
    expect(lastMenu.height, greaterThanOrEqualTo(48));
    expect(lastMenu.bottom, lessThanOrEqualTo(200));
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(844, 390);
    await tester.pump(const Duration(milliseconds: 800));
    home!.myDrawerController.close!();
    await tester.pump(const Duration(milliseconds: 400));
    navigator.currentState!.pushNamed('/personal');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.byKey(const ValueKey('personal-list:liked')));
    await tester.pump();
    expect(playlistTaps, 1);
    home!.mediaItem.value = const MediaItem(id: 'aligned-song', title: '测试歌曲');
    home!.hasStartedPlayback.value = true;
    await tester.pump();
    for (final insets in [
      const FakeViewPadding(left: 43),
      const FakeViewPadding(right: 43),
    ]) {
      tester.view.padding = insets;
      tester.view.viewPadding = insets;
      await tester.pump(const Duration(milliseconds: 400));
      final card = tester
          .getRect(find.byKey(const ValueKey('personal-list:alignment:1')));
      final fold =
          tester.getRect(find.byKey(const ValueKey('user-playlists-toggle')));
      final playback =
          tester.getRect(find.byKey(const ValueKey('phone-mini-toggle')));
      expect(fold.right, closeTo(card.right, .01));
      expect(playback.right, closeTo(fold.right, .01));
      expect(playback.center.dx, closeTo(fold.center.dx, .01));
      expect(find.byKey(const ValueKey('phone-mini-toggle')).hitTestable(),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPadding();
    tester.view.resetViewPadding();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('personal-list:liked')));
    await tester.pump();
    expect(playlistTaps, 2);
    navigator.currentState!.pop();
    home!.hasStartedPlayback.value = false;
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    navigator.currentState!.pushNamed('/details');
    await tester.pump(const Duration(milliseconds: 800));
    scroll.jumpTo(350);
    await tester.pump();
    final originalNavigator = navigator.currentState;
    final position = scroll.position;
    tester.view.physicalSize = const Size(844, 390);
    await tester.pump(const Duration(milliseconds: 800));
    expect(navigator.currentState, same(originalNavigator));
    expect(find.text('/details row 8'), findsOneWidget);
    expect(scroll.position, same(position));
    expect(scroll.offset, 350);
    expect(home!.landscape, isFalse);
    expect(find.byKey(const ValueKey('phone-mini-player')), findsNothing);
    home!.mediaItem.value = const MediaItem(id: 'selected-song', title: '已选择歌曲');
    home!.hasStartedPlayback.value = true;
    home!.playing.value = true;
    await tester.pump();
    expect(find.byKey(const ValueKey('phone-mini-player')), findsOneWidget);
    home!.playing.value = false;
    await tester.pump();
    expect(find.byKey(const ValueKey('phone-mini-player')), findsOneWidget);
    expect(navigator.currentState, same(originalNavigator));
    expect(scroll.position, same(position));
    expect(tester.takeException(), isNull);
    // The collapsed panel header is positioned without horizontal constraints.
    // A full-width child inside SafeArea used to add the cutout twice and push
    // the playback button beyond the display on camera-left landscape phones.
    for (final size in [const Size(844, 390), const Size(916, 393)]) {
      tester.view.physicalSize = size;
      for (final insets in [
        const FakeViewPadding(top: 20, left: 43),
        const FakeViewPadding(top: 20, right: 43),
      ]) {
        tester.view.padding = insets;
        tester.view.viewPadding = insets;
        await tester.pump(const Duration(milliseconds: 400));
        final bar =
            tester.getRect(find.byKey(const ValueKey('phone-mini-player')));
        final toggle =
            tester.getRect(find.byKey(const ValueKey('phone-mini-toggle')));
        expect(bar.left, greaterThanOrEqualTo(insets.left));
        expect(bar.right, lessThanOrEqualTo(size.width - insets.right));
        expect(toggle.right, lessThanOrEqualTo(size.width - insets.right));
        expect(toggle.bottom, lessThanOrEqualTo(size.height));
        expect(find.byKey(const ValueKey('phone-mini-toggle')).hitTestable(),
            findsOneWidget);
        final surfaceFinder =
            find.byKey(const ValueKey('phone-mini-player-surface'));
        final surface = tester.getRect(surfaceFinder);
        expect(surface.left, 0);
        expect(surface.right, size.width);
        expect(surface.bottom, size.height);
        expect(tester.widget<Material>(surfaceFinder).color,
            AppTheme.light.scaffoldBackgroundColor);
        expect(tester.takeException(), isNull);
      }
    }
    tester.view.physicalSize = const Size(844, 390);
    tester.view.resetPadding();
    tester.view.resetViewPadding();
    await tester.pump(const Duration(milliseconds: 400));
    home!.panelControllerHome.open();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);
    expect(home!.panelControllerHome.isPanelOpen, isTrue);
    await tester.tap(find.byKey(const ValueKey('phone-player-tab:2')));
    await tester.pump();
    final lyrics =
        tester.getRect(find.byKey(const ValueKey('phone-player-lyrics')));
    final tabs = List.generate(
        4, (i) => tester.getRect(find.byKey(ValueKey('phone-player-tab:$i'))));
    expect(tabs.first.left, greaterThan(lyrics.right));
    for (var i = 1; i < tabs.length; i++) {
      expect(tabs[i].left, tabs.first.left);
      expect(tabs[i].top, greaterThan(tabs[i - 1].bottom));
    }
    for (final insets in [
      const FakeViewPadding(top: 20, right: 43),
      const FakeViewPadding(top: 20, left: 43),
    ]) {
      tester.view.padding = insets;
      tester.view.viewPadding = insets;
      await tester.pump(const Duration(milliseconds: 400));
      for (var i = 0; i < 4; i++) {
        final control =
            tester.getRect(find.byKey(ValueKey('phone-player-tab:$i')));
        expect(control.right, lessThanOrEqualTo(844 - insets.right));
        expect(control.left, greaterThanOrEqualTo(insets.left));
      }
      final close =
          tester.getRect(find.byKey(const ValueKey('phone-player-close')));
      expect(close.left, greaterThanOrEqualTo(insets.left));
      final lyricsBounds =
          tester.getRect(find.byKey(const ValueKey('phone-player-lyrics')));
      expect(lyricsBounds.top, lessThan(insets.top + 24));
      final overlays = tester.widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.ancestor(
              of: find.byKey(const ValueKey('phone-player-lyrics')),
              matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>)));
      expect(overlays.first.value.statusBarIconBrightness, Brightness.dark);
      home!.changeStatusIconColor(true);
      await tester.pump();
      expect(
          SystemChrome.latestStyle!.statusBarIconBrightness, Brightness.dark);
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPadding();
    tester.view.resetViewPadding();
    await tester.pump();
    home!.rx.value = PaletteGenerator.fromColors(
        [PaletteColor(const Color(0xff153060), 100)]);
    await tester.pump(const Duration(milliseconds: 400));
    final background = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('landscape-player-background')));
    final colors =
        ((background.decoration as BoxDecoration).gradient as LinearGradient)
            .colors;
    expect(colors.first, isNot(AppTheme.light.scaffoldBackgroundColor));
    expect(colors.first.blue, greaterThan(colors.first.red));
    home!.changeStatusIconColor(true);
    await tester.pump();
    expect(SystemChrome.latestStyle!.statusBarIconBrightness, Brightness.light);
    home!.rx.value = PaletteGenerator.fromColors(
        [PaletteColor(const Color(0xffa02060), 100)]);
    await tester.pump(const Duration(milliseconds: 400));
    final playerContext = tester.element(find.byType(PhoneLandscapePlayer));
    expect(Theme.of(playerContext).primaryColor, Colors.white);
    final title = tester.widget<Text>(find.descendant(
        of: find.byType(PhoneLandscapePlayer),
        matching: find.text(home!.mediaItem.value.title)));
    expect(title.style!.color, Colors.white);
    await tester.tap(find.byKey(const ValueKey('phone-player-tab:1')));
    await tester.pump();
    expect(home!.selectIndex.value, 1);
    expect(find.text('original page 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('phone-player-tab:2')));
    await tester.pump();
    expect(find.byKey(const ValueKey('phone-player-lyrics')), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump(const Duration(milliseconds: 800));
    expect(navigator.currentState, same(originalNavigator));
    expect(home!.panelControllerHome.isPanelOpen, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    Get.reset();
    await GetIt.instance.reset();
    await tester.runAsync(() async {
      await handler.dispose();
      await box.close();
      await dir.delete(recursive: true);
    });
    scroll.dispose();
  });
}
