// Community maintenance and new features: tiancaiProgramer.
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/netease_api/src/dio_ext.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/widget/cloud_account_gate.dart';
import 'package:bujuan/widget/data_widget.dart';
import 'package:bujuan/widget/request_widget/request_loadmore_view.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:get/get.dart' hide Response;
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'download_preferences_test.dart' show MemoryBox;
import 'playback_regression_test.dart' show FakePlayer;

class _Home extends Home {
  // Avoid starting real account/audio services in request-state tests.
  @override
  // ignore: must_call_super
  void onInit() {}
  // The request UI does not initialize real account services.
  @override
  // ignore: must_call_super
  void onReady() {}
}

void main() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets(
        'cloud requires NetEase, opens login and reloads on return $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var loggedIn = false;
      var loads = 0;
      late StateSetter update;
      await tester.pumpWidget(
          MaterialApp(home: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return Scaffold(
            body: CloudAccountGate(
                loggedIn: loggedIn,
                accountId: 'test-account',
                onLogin: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (context) => Scaffold(
                          body: TextButton(
                              onPressed: () {
                                update(() => loggedIn = true);
                                Navigator.pop(context);
                              },
                              child: const Text('模拟网易云登录成功')))));
                },
                contentBuilder: (_, prompt) {
                  loads++;
                  return const Text('云盘歌曲');
                }));
      })));
      // A QQ session does not build the NetEase request: only the NetEase flag is passed.
      expect(loads, 0);
      expect(find.text('请登录账号'), findsOneWidget);
      expect(find.text('网络错误'), findsNothing);
      await tester.tap(find.text('请登录账号'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('模拟网易云登录成功'));
      await tester.pumpAndSettle();
      expect(find.text('云盘歌曲'), findsOneWidget);
      expect(loads, greaterThan(0));
      update(() => loggedIn = false);
      await tester.pumpAndSettle();
      expect(find.text('云盘歌曲'), findsNothing);
      expect(find.text('请登录账号'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final code in [301, 401, 500, 1401, 0]) {
    testWidgets(
        'cloud server code $code is classified without masking network failures',
        (tester) async {
      final box = MemoryBox();
      final handler = BujuanAudioHandler(
          player: FakePlayer(), box: box, restoreQueue: false);
      GetIt.I.registerSingleton<Box>(box);
      GetIt.I.registerSingleton<BujuanAudioHandler>(handler);
      GetIt.I.registerSingleton<ZoomDrawerController>(ZoomDrawerController());
      final interceptor = InterceptorsWrapper(onRequest: (request, next) {
        if (code == 1401) {
          next.reject(DioException(
              requestOptions: request,
              type: DioExceptionType.badResponse,
              response: Response(
                  requestOptions: request,
                  statusCode: 401,
                  data: {'code': 401})));
        } else if (code == 0) {
          next.reject(DioException(
              requestOptions: request,
              type: DioExceptionType.connectionTimeout));
        } else {
          next.resolve(Response(
              requestOptions: request, statusCode: 200, data: {'code': code}));
        }
      });
      Https.dio.interceptors.add(interceptor);
      await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(750, 1334),
          builder: (_, __) {
            if (!Get.isRegistered<Home>()) Get.put<Home>(_Home());
            return GetMaterialApp(
                home: Scaffold(
                    body: RequestLoadMoreWidget<dynamic, dynamic>(
                        dioMetaData: DioMetaData(
                            Uri.parse('https://example.invalid/cloud'),
                            data: {}),
                        listKey: const ['data'],
                        authenticationRequiredBuilder: (_) =>
                            const Text('请登录账号'),
                        childBuilder: (_) => const Text('歌曲'))));
          }));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final expired = [301, 401, 1401].contains(code);
      expect(find.text('请登录账号'), expired ? findsOneWidget : findsNothing);
      expect(find.byType(ErrorView), expired ? findsNothing : findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      Https.dio.interceptors.remove(interceptor);
      Get.reset();
      await tester.runAsync(handler.dispose);
      await GetIt.I.reset();
      expect(tester.takeException(), isNull);
    });
  }
}
