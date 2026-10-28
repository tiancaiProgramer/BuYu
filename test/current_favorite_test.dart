// Community maintenance and new features: tiancaiProgramer.
import 'dart:io';
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/common/music/music_source.dart';
import 'package:bujuan/common/music/unified_library.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/pages/home/view/home_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'phone_rotation_test.dart' show OfflineHome;
import 'playback_regression_test.dart' show FakePlayer;
import 'multi_source_test.dart' show Remote, qqSong;

void main() {
  testWidgets(
      'same song favorite changes repaint the heart and follow menu changes',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('PonnamKarthik/fluttertoast'), (_) async => true);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('PonnamKarthik/fluttertoast'), null));
    final resources = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('buyu-favorite-heart');
      Hive.init(dir.path);
      final box = await Hive.openBox('favorite-heart');
      final handler = BujuanAudioHandler(
          player: FakePlayer(),
          box: box,
          restoreQueue: false,
          urlResolver: (_) async => '/tmp/test-audio.wav');
      return (dir, box, handler);
    });
    final (dir, box, handler) = resources!;
    GetIt.I.registerSingleton<Box>(box);
    GetIt.I.registerSingleton<BujuanAudioHandler>(handler);
    GetIt.I.registerSingleton<ZoomDrawerController>(ZoomDrawerController());
    final library = UnifiedLibrary(box, remotes: {
      MusicSource.netease: Remote()..account = '',
      MusicSource.qq: Remote()..account = ''
    });
    GetIt.I.registerSingleton<UnifiedLibrary>(library);
    Home? home;
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(750, 1624),
        builder: (_, __) {
          home ??= Get.put<Home>(OfflineHome());
          home!.pages = List.generate(4, (i) => Text('播放页 $i'));
          return GetMaterialApp(
              theme: AppTheme.light,
              home: const HomeView(body: SizedBox.expand()));
        }));
    await tester.pump();
    await tester.runAsync(() => handler.changeQueueLists([qqSong]));
    home!.mediaItem.value = handler.mediaItem.value!;
    home!.hasStartedPlayback.value = true;
    home!.panelControllerHome.open();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    final button = find.byKey(const ValueKey('portrait-favorite'));
    IconData icon() => tester
        .widget<Icon>(find.descendant(of: button, matching: find.byType(Icon)))
        .icon!;
    expect(icon(), Icons.favorite_border);
    await tester.runAsync(() async {
      await tester.tap(button);
      await library.sync();
    });
    await tester.pump();
    expect(library.contains(qqSong), isTrue);
    expect(handler.mediaItem.value?.id, qqSong.id);
    expect(icon(), Icons.favorite);
    // An action from the song menu must also update an already open player.
    await tester.runAsync(() => library.setFavorite(qqSong, false));
    await tester.pump();
    expect(icon(), Icons.favorite_border);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    Get.reset();
    await GetIt.I.reset();
    library.dispose();
    await tester.runAsync(() async {
      await handler.dispose();
      await box.close();
      await dir.delete(recursive: true);
    });
  });
}
