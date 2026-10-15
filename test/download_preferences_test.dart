import 'package:bujuan/common/audio_quality.dart';
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/common/constants/key.dart';
import 'package:bujuan/common/downloads.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/pages/setting/settring_view.dart';
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

class MemoryBox extends Fake implements Box {
  final data = <dynamic, dynamic>{};
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    data[key] = value;
  }

  @override
  Future<void> putAll(Map<dynamic, dynamic> entries) async {
    data.addAll(entries);
  }

  @override
  Future<int> deleteAll(Iterable<dynamic> keys) async {
    for (final key in keys) {
      data.remove(key);
    }
    return keys.length;
  }
}

void main() {
  testWidgets(
      'download quality is independent and chosen directory is remembered',
      (tester) async {
    final box = MemoryBox();
    await box.put(audioQualitySp, 'lossless');
    GetIt.instance.registerSingleton<Box>(box);
    final handler =
        BujuanAudioHandler(player: FakePlayer(), box: box, restoreQueue: false);
    GetIt.instance.registerSingleton<BujuanAudioHandler>(handler);
    GetIt.instance
        .registerSingleton<ZoomDrawerController>(ZoomDrawerController());
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/package_info'),
        (_) async => {
              'appName': 'BuJuan',
              'packageName': 'test',
              'version': '2.0.6',
              'buildNumber': '2060'
            });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        Downloads.channel,
        (_) async => {'uri': 'content://tree/music', 'name': '自选音乐目录'});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(750, 346),
        builder: (_, __) {
          if (!Get.isRegistered<Home>()) Get.put<Home>(OfflineHome());
          return GetMaterialApp(
              theme: AppTheme.light, home: const SettingViewL());
        }));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('download-quality-setting')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('download-quality-setting')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hi-Res'));
    await tester.pumpAndSettle();
    expect(box.get(Downloads.qualityKey), 'hires');
    expect(box.get(audioQualitySp), 'lossless');
    await tester.tap(find.byKey(const ValueKey('download-folder-setting')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择文件夹'));
    await tester.pumpAndSettle();
    expect(box.get(Downloads.folderKey), 'content://tree/music');
    expect(find.text('自选音乐目录'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    Get.reset();
    await GetIt.instance.reset();
    await tester.runAsync(() => handler.dispose());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(Downloads.channel, null);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/package_info'), null);
  });
}
