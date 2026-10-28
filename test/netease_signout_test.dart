// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/common/constants/key.dart';
import 'package:bujuan/common/netease_api/src/api/login/bean.dart';
import 'package:bujuan/common/netease_api/src/api/login/api.dart';
import 'package:bujuan/common/netease_api/src/api/play/bean.dart';
import 'package:bujuan/common/netease_api/src/netease_api.dart';
import 'package:bujuan/common/netease_api/src/netease_handler.dart';
import 'package:bujuan/common/music/qq_music.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/pages/music/music_accounts_view.dart';
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

class _Paths extends PathProvider {
  _Paths(this.root);
  final Directory root;
  @override
  Future<void> init() async {}
  @override
  String getDataSavedPath() => '${root.path}/data/';
  @override
  String getCookieSavedPath() => '${root.path}/cookies/';
}

class _Api with ApiLogin {
  late final pending = Completer<NeteaseAccountInfoWrap>();
  @override
  Future<NeteaseAccountInfoWrap> loginAccountInfo() => pending.future;
}

class _User extends UserController {
  _User({super.accountApi});
  @override
  void onReady() {}
}

void main() {
  for (final personalRoutePresent in [false, true]) {
    testWidgets(
        'NetEase signout clears persisted session and keeps QQ when personal route exists=$personalRoutePresent',
        (tester) async {
      late Directory directory;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('buyu-signout-test');
        await Directory('${directory.path}/data').create(recursive: true);
        await NeteaseMusicApi.init(provider: _Paths(directory));
        NeteaseMusicApi().usc = UserLoginStateController();
        await NeteaseMusicApi().usc.init();
      });
      final box = MemoryBox();
      final account = NeteaseAccountInfoWrap.fromJson({
        'code': 200,
        'profile': {'userId': 123, 'nickname': '测试账号'}
      });
      await tester.runAsync(() async {
        await NeteaseMusicApi().usc.onLogined(account);
        await NeteaseMusicApi.cookieManager.cookieJar.saveFromResponse(
            Uri.parse(HOST), [Cookie('MUSIC_U', 'test-session')]);
      });
      await box.put(loginData, jsonEncode(account.toJson()));
      final handler = BujuanAudioHandler(
          player: FakePlayer(), box: box, restoreQueue: false);
      GetIt.I.registerSingleton<Box>(box);
      GetIt.I.registerSingleton<BujuanAudioHandler>(handler);
      GetIt.I.registerSingleton<ZoomDrawerController>(ZoomDrawerController());
      final nativeCalls = <String>[];
      const channel = MethodChannel('buyu/qqmusic');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        nativeCalls.add(call.method);
        if (call.method == 'readSession')
          return 'uin=456; qqmusic_key=fixture-only';
        throw StateError('NetEase signout must not change QQ authorization');
      });
      Home? home;
      UserController? user;
      final accountApi = _Api();
      await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(750, 1334),
          builder: (_, __) {
            if (home == null) {
              home = Get.put<Home>(OfflineHome());
              home!.userData.value = account;
              home!.loginStatus.value = LoginStatus.login;
              home!.likeIds.add(123);
              if (personalRoutePresent) {
                user = Get.put<UserController>(_User(accountApi: accountApi));
                user!.playlist.add(Play()
                  ..id = 'owned'
                  ..name = '测试歌单');
              }
            }
            return GetMaterialApp(
                theme: AppTheme.light, home: const MusicAccountsView());
          }));
      await tester.pumpAndSettle();
      expect(Get.isRegistered<UserController>(), personalRoutePresent);
      expect(QqMusic.instance.loggedIn, true);
      await tester.runAsync(() async {
        final oldRequest = personalRoutePresent ? user!.getUserState() : null;
        await tester.tap(find.text('退出网易云登录'));
        for (var i = 0;
            i < 50 && home!.loginStatus.value == LoginStatus.login;
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        if (oldRequest != null) {
          accountApi.pending.complete(account);
          expect(await oldRequest, false,
              reason: 'an old response cannot log the user back in');
        }
      });
      await tester.pumpAndSettle();
      expect(home!.loginStatus.value, LoginStatus.noLogin);
      expect(home!.userData.value.profile, isNull);
      expect(home!.likeIds, isEmpty);
      expect(box.get(loginData), '');
      expect(find.text('已退出网易云登录'), findsOneWidget);
      expect(find.text('退出网易云登录'), findsNothing);
      expect(QqMusic.instance.loggedIn, true);
      expect(nativeCalls, ['readSession']);
      if (user != null) expect(user!.playlist, isEmpty);
      await tester.runAsync(() async {
        expect(await loadCookies(), isEmpty);
        final restored = UserLoginStateController();
        await restored.init();
        expect(restored.isLogined, false);
        expect(restored.accountInfo, isNull);
        restored.destroy();
      });
      if (!personalRoutePresent) {
        // Account management can also log back in without recreating the
        // removed personal-page controller.
        await tester.runAsync(() async {
          final api = _Api();
          api.pending.complete(account);
          expect(await UserController.refreshNeteaseAccount(api: api), true);
          expect(Get.isRegistered<UserController>(), false);
          expect(home!.loginStatus.value, LoginStatus.login);
          await UserController.signOutNetease();
        });
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      Get.reset();
      await GetIt.I.reset();
      await tester.runAsync(() async {
        await handler.dispose();
        await directory.delete(recursive: true);
      });
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  }
}
