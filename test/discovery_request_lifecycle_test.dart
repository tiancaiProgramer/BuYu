// Community maintenance and new features: tiancaiProgramer.
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/netease_api/src/dio_ext.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/widget/request_widget/request_view.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:get/get.dart' hide Response;
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'download_preferences_test.dart' show MemoryBox;
import 'phone_rotation_test.dart' show OfflineHome;
import 'playback_regression_test.dart' show FakePlayer;

void main() {
  testWidgets(
      'switching platform cancels a request and ignores the late old response',
      (tester) async {
    final box = MemoryBox();
    final audio =
        BujuanAudioHandler(player: FakePlayer(), box: box, restoreQueue: false);
    GetIt.I.registerSingleton<Box>(box);
    GetIt.I.registerSingleton<BujuanAudioHandler>(audio);
    GetIt.I.registerSingleton<ZoomDrawerController>(ZoomDrawerController());
    RequestInterceptorHandler? held;
    RequestOptions? request;
    var dataCallbacks = 0;
    final interceptor = InterceptorsWrapper(onRequest: (options, next) {
      request = options;
      held = next;
    });
    Https.dio.interceptors.add(interceptor);
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(750, 1334),
        builder: (_, __) {
          if (!Get.isRegistered<Home>()) Get.put<Home>(OfflineHome());
          return GetMaterialApp(
              home: Scaffold(
                  body: RequestWidget<dynamic>(
                      dioMetaData: DioMetaData(
                          Uri.parse('https://example.invalid/old-source'),
                          data: {}),
                      onData: (_) => dataCallbacks++,
                      childBuilder: (_) => const Text('旧平台内容'))));
        }));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(held, isNotNull);
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: Text('新平台内容'))));
    expect(request!.cancelToken!.isCancelled, true);
    held!.resolve(Response(
        requestOptions: request!, statusCode: 200, data: {'code': 200}));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('新平台内容'), findsOneWidget);
    expect(dataCallbacks, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    Https.dio.interceptors.remove(interceptor);
    Get.reset();
    await GetIt.I.reset();
    await tester.runAsync(audio.dispose);
  });
}
