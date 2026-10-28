import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/common/constants/key.dart';
import 'package:bujuan/common/downloads.dart';
import 'package:bujuan/common/display_mode.dart';
import 'package:bujuan/common/netease_api/src/api/play/bean.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/pages/index/index_controller.dart';
import 'package:bujuan/pages/user/user_controller.dart';
import 'package:bujuan/pages/index/main_view.dart';
import 'package:bujuan/pages/local/local_controller.dart';
import 'package:bujuan/pages/local/local_view.dart';
import 'package:bujuan/pages/local/local_song.dart';
import 'package:bujuan/pages/setting/settring_view.dart';
import 'package:bujuan/pages/setting/image_blur.dart';
import 'package:bujuan/pages/playlist_manager/playlist_manager_controller.dart';
import 'package:bujuan/pages/playlist_manager/playlist_manager_view.dart';
import 'package:bujuan/widget/adaptive_wallpaper.dart';
import 'package:bujuan/widget/landscape_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'phone_rotation_test.dart' show OfflineHome;
import 'playback_regression_test.dart' show FakePlayer;

class OfflineDiscovery extends IndexController {
  @override
  void onReady() {}
}

class OfflineLocal extends Local {
  int requests = 0;
  @override
  Future<void> getLocalSong() async {
    requests++;
    songs.assignAll(List.generate(
        8,
        (i) => MediaItem(
            id: 'local:$i',
            title: '本地歌曲 $i',
            artist: '本地歌手',
            extras: {'type': 'local'})));
    loadingSong.value = false;
  }

  @override
  void onReady() {}
}

class OfflineUser extends UserController {
  @override void onReady() {}
}

class OfflineManager extends PlaylistManager {
  @override
  void onReady() {}
}

void main() {
  for (final size in [const Size(844, 390), const Size(640, 300)]) {
    testWidgets('discovery, local and settings fit landscape at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (_) async => {
                'appName': 'BuJuan',
                'packageName': 'test',
                'version': '2.0.5',
                'buildNumber': '2043'
              });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('dev.fluttercommunity.plus/package_info'),
              null));
      final resources = await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('bujuan-pages');
        Hive.init(dir.path);
        final box = await Hive.openBox('landscape-pages');
        final handler = BujuanAudioHandler(
            player: FakePlayer(), box: box, restoreQueue: false);
        return (dir, box, handler);
      });
      final (dir, box, handler) = resources!;
      GetIt.instance.registerSingleton<Box>(box);
      GetIt.instance.registerSingleton<BujuanAudioHandler>(handler);
      GetIt.instance
          .registerSingleton<ZoomDrawerController>(ZoomDrawerController());
      GetIt.instance.registerSingleton<OnAudioQuery>(OnAudioQuery());
      final discovery = Get.put<IndexController>(OfflineDiscovery());
      discovery.loading.value = false;
      discovery.playlist.assignAll(List.generate(
          6,
          (i) => Play()
            ..id = '$i'
            ..name = '每日发现推荐歌单 $i'
            ..trackCount = 20));
      discovery.newSong.assignAll(List.generate(
          6,
          (i) => MediaItem(
              id: '$i',
              title: '很长的歌曲名称需要正确换行而不是溢出 $i',
              artist: '演唱者',
              extras: {'image': ''})));
      final local = Get.put<Local>(OfflineLocal())..loading.value = false;
      const capturePath = String.fromEnvironment('PAGES_CAPTURE');
      final boundary = GlobalKey();
      if (capturePath.isNotEmpty) {
        await tester.runAsync(() async {
          final font =
              await File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf')
                  .readAsBytes();
          await (FontLoader('Roboto')
                ..addFont(Future.value(ByteData.sublistView(font))))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          await (FontLoader('packages/flutter_tabler_icons/tabler-icons')
                ..addFont(rootBundle.load(
                    'packages/flutter_tabler_icons/assets/fonts/tabler-icons.ttf')))
              .load();
        });
      }
      Future<void> capture(String name) async {
        if (capturePath.isEmpty) return;
        await tester.runAsync(() async {
          final render = boundary.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
          final pixels = await render.toImage(pixelRatio: 2);
          final data = await pixels.toByteData(format: ui.ImageByteFormat.png);
          await Directory(capturePath).create(recursive: true);
          await File('$capturePath/$name-${size.width.toInt()}.png')
              .writeAsBytes(data!.buffer.asUint8List());
          pixels.dispose();
        });
      }

      Home? home;
      Future<void> mount(Widget page) async {
        await tester.pumpWidget(ScreenUtilInit(
            designSize: DisplayMode.designSize(tester.view.physicalSize),
            builder: (_, __) {
              home ??= Get.put<Home>(OfflineHome());
              if (!Get.isRegistered<UserController>()) Get.put<UserController>(OfflineUser());
              return GetMaterialApp(
                  theme: capturePath.isEmpty
                      ? AppTheme.light
                      : AppTheme.light.copyWith(
                          textTheme: AppTheme.light.textTheme
                              .apply(fontFamily: 'Roboto'),
                          primaryTextTheme: AppTheme.light.primaryTextTheme
                              .apply(fontFamily: 'Roboto')),
                  home: RepaintBoundary(
                      key: boundary,
                      child: ColoredBox(
                          color: AppTheme.light.scaffoldBackgroundColor,
                          child: page)));
            }));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await mount(const MainView());
      await capture('discovery');
      final cards = find.byType(LandscapeCard);
      expect(cards, findsNWidgets(6));
      expect(tester.getRect(cards.at(0)).top, tester.getRect(cards.at(2)).top);
      expect(tester.getRect(cards.at(3)).top,
          greaterThan(tester.getRect(cards.at(0)).bottom));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final manager = Get.put<PlaylistManager>(OfflineManager());
      manager.playlist.addAll(List.generate(9, (i) => Play()..id = '$i'..name = '我的歌单 $i'..trackCount = 10));
      UserController.to.playlist.addAll(manager.playlist);
      await mount(const PlaylistManagerView());
      final managerCards = find.byType(LandscapeCardSurface);
      expect(tester.getRect(managerCards.at(0)).top, tester.getRect(managerCards.at(2)).top);
      expect(tester.getRect(managerCards.at(3)).top, greaterThan(tester.getRect(managerCards.at(0)).bottom));
      await capture('manager');
      final previewFile = await tester.runAsync(() async {
        final bytes = await rootBundle.load('assets/images/logo.png');
        return File('${dir.path}/preview.png').writeAsBytes(bytes.buffer.asUint8List());
      });
      await tester.runAsync(() async {
        await mount(ImageBlur(path: previewFile!.path));
        for (final element in find.byType(Image).evaluate()) {
          final image = element.widget as Image;
          await precacheImage(image.image, element).timeout(const Duration(seconds: 10));
        }
      });
      await tester.pump();
      expect(tester.getRect(find.text('保存')).center.dx,
          greaterThan(tester.getRect(find.byType(AdaptiveWallpaper)).right));
      expect(tester.getRect(find.byType(AdaptiveWallpaper)).height, greaterThan(100));
      await tester.drag(find.byType(Slider), const Offset(40, 0));
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider)).value, greaterThan(0));
      expect(tester.takeException(), isNull);
      await capture('background-editor');
      await mount(const LocalView());
      await capture('local');
      expect(local.loading.value, isFalse);
      expect(find.text('本地SDCard歌曲'), findsOneWidget);
      expect(find.text('网易云缓存歌曲'), findsOneWidget);
      expect(tester.getRect(find.text('本地SDCard歌曲')).center.dy,
          tester.getRect(find.text('网易云缓存歌曲')).center.dy);
      await mount(const SettingViewL());
      await capture('settings');
      final first = tester.getRect(find.text('适配横屏'));
      final second = tester.getRect(find.text('渐变播放背景'));
      expect((first.center.dy - second.center.dy).abs(), lessThan(2));
      expect(second.left, greaterThan(first.right));
      final firstCard = tester
          .element(find.text('适配横屏'))
          .findAncestorWidgetOfExactType<Material>()!;
      final secondCard = tester
          .element(find.text('渐变播放背景'))
          .findAncestorWidgetOfExactType<Material>()!;
      expect(identical(firstCard, secondCard), isFalse);
      expect(firstCard.borderRadius, BorderRadius.circular(12));
      expect(
          tester.getRect(find.byWidget(secondCard)).left -
              tester.getRect(find.byWidget(firstCard)).right,
          12);

      final before = home!.gradientBackground.value;
      await tester.runAsync(() async {
        await tester.tap(find.text('渐变播放背景'));
        await box.flush();
      });
      await tester.pump();
      expect(home!.gradientBackground.value, !before);
      expect(box.get(gradientBackgroundSp), !before);
      for (final removed in [
        '顶部歌词',
        '圆形专辑',
        '开启缓存',
        '开启高音质(与会员有关)',
        'Unblock获取灰色音乐',
        'Unblock获取Vip音乐（会员勿开）'
      ]) {
        expect(find.text(removed), findsNothing);
      }
      expect(
          find.byKey(const ValueKey('github-update-setting')), findsOneWidget);
      await tester.runAsync(
          () => tester.tap(find.byKey(const ValueKey('background-setting'))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('artwork-portrait')), findsOneWidget);
      expect(find.byKey(const ValueKey('artwork-landscape')), findsOneWidget);
      expect(tester.getRect(find.byKey(const ValueKey('artwork-portrait'))).top,
          tester.getRect(find.byKey(const ValueKey('artwork-landscape'))).top);
      await tester.ensureVisible(find.byKey(const ValueKey('artwork-reset')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('artwork-reset')));
        await box.flush();
      });
      await tester.pumpAndSettle();
      final qualitySetting =
          find.byKey(const ValueKey('audio-quality-setting'));
      await tester.ensureVisible(qualitySetting);
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(qualitySetting));
      await tester.pumpAndSettle();
      final lossless = find.byKey(const ValueKey('audio-quality:lossless'));
      await tester.ensureVisible(lossless);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(lossless);
        await box.flush();
      });
      await tester.pumpAndSettle();
      expect(box.get(audioQualitySp), 'lossless');
      expect(find.text('无损（优先）'), findsOneWidget);
      await tester
          .ensureVisible(find.byKey(const ValueKey('landscape-setting')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('landscape-setting')));
        await box.flush();
      });
      await tester.pump();
      expect(home!.landscapeAdaptation.value, false);
      expect(box.get(landscapeAdaptationSp), false);
      await tester.runAsync(() => home!.setLandscapeAdaptation(true));
      expect(box.get(landscapeAdaptationSp), true);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      final portraitFirst = tester.getRect(find.text('适配横屏'));
      final portraitSecond = tester.getRect(find.text('渐变播放背景'));
      expect(portraitSecond.top, greaterThan(portraitFirst.bottom));
      expect(tester.takeException(), isNull);
      await mount(const LocalSongView());
      expect((local as OfflineLocal).requests, 1);
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(local.requests, 1);
      expect(find.byType(GridView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
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
