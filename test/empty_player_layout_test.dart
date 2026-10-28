// Community maintenance and new features: tiancaiProgramer.
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/common/display_mode.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/pages/home/view/body_view.dart';
import 'package:bujuan/pages/home/view/home_view.dart';
import 'package:bujuan/widget/weslide/panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'download_preferences_test.dart' show MemoryBox;
import 'phone_rotation_test.dart' show OfflineHome;
import 'playback_regression_test.dart' show FakePlayer;

void main() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets(
        'empty player leaves no reserved space or draggable blank panel at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      tester.view.padding = const FakeViewPadding(bottom: 20);
      tester.view.viewPadding = const FakeViewPadding(bottom: 20);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      final box = MemoryBox();
      final handler = BujuanAudioHandler(
          player: FakePlayer(), box: box, restoreQueue: false);
      GetIt.I.registerSingleton<Box>(box);
      GetIt.I.registerSingleton<BujuanAudioHandler>(handler);
      GetIt.I.registerSingleton<ZoomDrawerController>(ZoomDrawerController());
      Home? home;
      final navigator = GlobalKey<NavigatorState>();
      const viewport = ValueKey('available-content');
      await tester.pumpWidget(ScreenUtilInit(
          designSize: DisplayMode.designSize(size),
          builder: (_, __) {
            home ??= Get.put<Home>(OfflineHome());
            home!.pages = List.generate(4, (i) => Text('player tab $i'));
            return GetMaterialApp(
                theme: AppTheme.light,
                home: HomeView(
                    body: BodyView(
                        child: Navigator(
                            key: navigator,
                            onGenerateRoute: (_) => MaterialPageRoute(
                                builder: (_) =>
                                    const SizedBox.expand(key: viewport))))));
          }));
      await tester.pumpAndSettle();
      final state = navigator.currentState;
      double contentBottom() => tester.getBottomRight(find.byKey(viewport)).dy;
      expect(contentBottom(), closeTo(size.height - 20, .01));
      home!.hasStartedPlayback.value = true;
      home!.playing.value = true;
      await tester.pumpAndSettle();
      final emptyPanel =
          tester.widget<SlidingUpPanel>(find.byType(SlidingUpPanel));
      expect(emptyPanel.minHeight, 0);
      expect(emptyPanel.maxHeight, 0);
      expect(emptyPanel.isDraggable, false);
      expect(contentBottom(), closeTo(size.height - 20, .01));
      home!.mediaItem.value = const MediaItem(id: 'qq:test', title: '已选择歌曲');
      await tester.pumpAndSettle();
      expect(contentBottom(), lessThan(size.height - 40));
      home!.playing.value = false;
      await tester.pumpAndSettle();
      expect(contentBottom(), lessThan(size.height - 40),
          reason: '暂停时仍保留已选择歌曲');
      home!.panelControllerHome.open();
      await tester.pumpAndSettle();
      home!.mediaItem.value = const MediaItem(id: '', title: '暂无');
      await tester.pumpAndSettle();
      expect(contentBottom(), closeTo(size.height - 20, .01));
      expect(
          tester.widget<SlidingUpPanel>(find.byType(SlidingUpPanel)).maxHeight,
          0);
      expect(navigator.currentState, same(state));
      expect(await home!.onWillPop(), isTrue,
          reason: '无歌曲时，返回操作不能被隐藏的播放器拦截');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      Get.reset();
      await GetIt.I.reset();
      await tester.runAsync(handler.dispose);
    });
  }
}
