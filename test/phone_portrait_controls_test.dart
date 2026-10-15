import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/common/constants/key.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/pages/home/view/home_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'phone_rotation_test.dart' show OfflineHome;
import 'playback_regression_test.dart' show FakePlayer;

void main() {
  testWidgets('portrait previous and repeat respond to real taps with stale FM state', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final resources = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('bujuan-controls');
      Hive.init(dir.path);
      final box = await Hive.openBox('controls');
      final player = FakePlayer();
      final handler = BujuanAudioHandler(player: player, box: box, restoreQueue: false,
          urlResolver: (_) async => '/tmp/test-audio.wav');
      return (dir, box, player, handler);
    });
    final (dir, box, player, handler) = resources!;
    GetIt.instance.registerSingleton<Box>(box);
    GetIt.instance.registerSingleton<BujuanAudioHandler>(handler);
    GetIt.instance.registerSingleton<ZoomDrawerController>(ZoomDrawerController());
    Home? home;
    await tester.pumpWidget(ScreenUtilInit(designSize: const Size(750, 1624), builder: (_, __) {
      home ??= Get.put<Home>(OfflineHome());
      return GetMaterialApp(theme: AppTheme.light, home: const HomeView(body: SizedBox.expand()));
    }));
    await tester.pump();
    await tester.runAsync(() async {
      await handler.changeQueueLists(const [MediaItem(id: 'a', title: 'A'), MediaItem(id: 'b', title: 'B')], index: 1);
    });
    home!.fm.value = true;
    home!.mediaItem.value = handler.mediaItem.value!;
    home!.panelControllerHome.open();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.runAsync(() async { await tester.tap(find.byKey(const ValueKey('portrait-previous'))); });
    await tester.pump();
    expect(handler.mediaItem.value!.id, 'a');
    await tester.runAsync(() async { await tester.tap(find.byKey(const ValueKey('portrait-repeat'))); await box.flush(); });
    await tester.pump();
    expect(home!.audioServiceRepeatMode.value, AudioServiceRepeatMode.one);
    expect(box.get(repeatModeSp), 'one');
    expect(home!.fm.value, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    Get.reset();
    await GetIt.instance.reset();
    await tester.runAsync(() async { await handler.dispose(); await box.close(); await dir.delete(recursive: true); });
  });
}
