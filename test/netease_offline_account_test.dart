// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'dart:convert';
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/constants/key.dart';
import 'package:bujuan/common/netease_api/src/api/login/api.dart';
import 'package:bujuan/common/netease_api/src/api/login/bean.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/pages/user/user_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'download_preferences_test.dart' show MemoryBox;
import 'phone_rotation_test.dart' show OfflineHome;
import 'playback_regression_test.dart' show FakePlayer;

class _AccountApi with ApiLogin {
  late Future<NeteaseAccountInfoWrap> Function() respond;
  @override
  Future<NeteaseAccountInfoWrap> loginAccountInfo() => respond();
}

void main() {
  for (final failure in ['network', 'timeout', '503', '429', '301', '200']) {
    testWidgets(
        'account refresh preserves cached login for transient $failure and expires only confirmed sessions',
        (tester) async {
      const toast = MethodChannel('PonnamKarthik/fluttertoast');
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(toast, (_) async => true);
      final box = MemoryBox();
      final account = NeteaseAccountInfoWrap.fromJson({
        'code': 200,
        'profile': {'userId': 123, 'nickname': 'cached'}
      });
      await box.put(loginData, jsonEncode(account.toJson()));
      final audio = (await tester.runAsync(() async => BujuanAudioHandler(
          player: FakePlayer(), box: box, restoreQueue: false)))!;
      GetIt.I.registerSingleton<Box>(box);
      GetIt.I.registerSingleton<BujuanAudioHandler>(audio);
      GetIt.I.registerSingleton<ZoomDrawerController>(ZoomDrawerController());
      late Home home;
      await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(750, 1334),
          builder: (_, __) {
            if (!Get.isRegistered<Home>()) {
              home = Get.put<Home>(OfflineHome());
              home.userData.value = account;
              home.loginStatus.value = LoginStatus.login;
              home.likeIds.add(123);
            }
            return const GetMaterialApp(home: Scaffold(body: SizedBox()));
          }));
      await tester.pumpAndSettle();
      final api = _AccountApi()
        ..respond = () async {
          if (failure == 'network') throw StateError('offline');
          if (failure == 'timeout') throw TimeoutException('offline');
          return NeteaseAccountInfoWrap()..code = int.parse(failure);
        };
      expect(await UserController.refreshNeteaseAccount(api: api), false);
      final expired = failure == '301' || failure == '200';
      expect(home.loginStatus.value,
          expired ? LoginStatus.noLogin : LoginStatus.login);
      expect(home.userData.value.profile?.userId, '123');
      expect(home.likeIds, [123]);
      expect(box.get(loginData), jsonEncode(account.toJson()));
      // A later successful check can recover without requesting credentials again.
      api.respond = () async => account;
      expect(await UserController.refreshNeteaseAccount(api: api), true);
      expect(home.loginStatus.value, LoginStatus.login);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      Get.reset();
      await GetIt.I.reset();
      await tester.runAsync(audio.dispose);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(toast, null);
    });
  }
}
