// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/common/display_mode.dart';
import 'package:bujuan/common/music/music_source.dart';
import 'package:bujuan/common/music/qq_music.dart';
import 'package:bujuan/common/netease_api/src/api/login/bean.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/pages/music/music_accounts_view.dart';
import 'package:bujuan/pages/user/user_controller.dart';
import 'package:bujuan/widget/simple_extended_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:get/get.dart' hide Response;
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'download_preferences_test.dart' show MemoryBox;
import 'phone_rotation_test.dart' show OfflineHome;
import 'playback_regression_test.dart' show FakePlayer;

class _Qq extends QqMusic {
  bool signed = true;
  @override
  bool get loggedIn => signed;
  void update(bool value) { signed = value; notifyListeners(); }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('buyu/profile-test');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await GetIt.I.reset();
  });

  test('QQ official public profile is cached by account and refreshed safely', () async {
    final box = MemoryBox();
    GetIt.I.registerSingleton<Box>(box);
    messenger.setMockMethodCallHandler(channel, (call) async =>
        call.method == 'readSession' ? 'uin=123; qqmusic_key=fixture' : null);
    final dio = Dio();
    var requests = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      requests++;
      h.resolve(Response(requestOptions: o, data: {'code': 0, 'data': {
        'creator': {'musicid': 123, 'nick': 'QQ昵称', 'headpic': '//y.gtimg.cn/avatar.jpg'}
      }}));
    }));
    final qq = QqMusic(dio: dio, channel: channel);
    await qq.refreshProfile();
    expect(qq.avatarUrl, 'https://y.gtimg.cn/avatar.jpg');
    expect(qq.nickname, 'QQ昵称');
    final restored = QqMusic(dio: dio, channel: channel);
    await restored.restore();
    expect(restored.avatarUrl, qq.avatarUrl);
    expect(restored.nickname, qq.nickname);
    expect(requests, 1);
    messenger.setMockMethodCallHandler(channel, (call) async =>
        call.method == 'readSession' ? 'uin=456; qqmusic_key=other-fixture' : null);
    final other = QqMusic(dio: dio, channel: channel);
    await other.restore();
    expect(other.avatarUrl, isEmpty);
    expect(other.nickname, isEmpty);
    qq.dispose(); restored.dispose(); other.dispose();
  });

  test('a late public-profile response after logout cannot restore the old avatar', () async {
    final box = MemoryBox();
    GetIt.I.registerSingleton<Box>(box);
    messenger.setMockMethodCallHandler(channel, (call) async =>
        call.method == 'readSession' ? 'uin=123; qqmusic_key=fixture' : null);
    final pending = Completer<void>();
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
      await pending.future;
      h.resolve(Response(requestOptions: o, data: {'code': 0, 'data': {
        'creator': {'musicid': 123, 'nick': '旧账号', 'headpic': 'https://y.gtimg.cn/old.jpg'}
      }}));
    }));
    final qq = QqMusic(dio: dio, channel: channel);
    final loading = qq.refreshProfile();
    await Future<void>.delayed(Duration.zero);
    await qq.logout();
    pending.complete();
    await loading;
    expect(qq.avatarUrl, isEmpty);
    expect(qq.nickname, isEmpty);
    expect(box.get(QqMusic.profileCacheKey), isNull);
    qq.dispose();
  });

  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('dual account avatar source persists, updates and falls back at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      final box = MemoryBox(), qq = _Qq();
      qq.nickname = 'QQ昵称'; qq.avatarUrl = 'https://images.example/qq.jpg';
      final audio = (await tester.runAsync(() async => BujuanAudioHandler(
          player: FakePlayer(), box: box, restoreQueue: false)))!;
      GetIt.I.registerSingleton<Box>(box);
      GetIt.I.registerSingleton<QqMusic>(qq);
      GetIt.I.registerSingleton<BujuanAudioHandler>(audio);
      GetIt.I.registerSingleton<ZoomDrawerController>(ZoomDrawerController());
      Home? home;
      await tester.pumpWidget(ScreenUtilInit(designSize: DisplayMode.designSize(size),
          builder: (_, __) {
            home ??= Get.put<Home>(OfflineHome());
            return GetMaterialApp(theme: AppTheme.light,
                home: const MusicAccountsView());
          }));
      await tester.pump(const Duration(milliseconds: 300));
      expect(home!.displayProfileSource, MusicSource.qq);
      expect(home!.displayAvatarUrl, qq.avatarUrl);
      expect(home!.displayNickname, qq.nickname);
      home!.userData.value = NeteaseAccountInfoWrap.fromJson({'code': 200,
        'profile': {'userId': 456, 'nickname': '网易昵称', 'avatarUrl': 'https://images.example/ne.jpg'}});
      home!.loginStatus.value = LoginStatus.login;
      await tester.tap(find.byKey(const ValueKey('profile-source-setting')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-source:qq')));
      await tester.pumpAndSettle();
      expect(home!.displayProfileSource, MusicSource.qq);
      expect(box.get(Home.profileSourceKey), 'qq');
      final selectedImage = tester.widget<SimpleExtendedImage>(find.descendant(
          of: find.byKey(const ValueKey('profile-source-setting')),
          matching: find.byType(SimpleExtendedImage)));
      expect(selectedImage.url, qq.avatarUrl);
      await tester.tap(find.byKey(const ValueKey('profile-source-setting')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-source:qq')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('profile-source:qq')), findsNothing);
      expect(home!.displayProfileSource, MusicSource.qq);
      qq.update(false);
      await tester.pump();
      expect(home!.displayProfileSource, MusicSource.netease);
      expect(home!.displayNickname, '网易昵称');
      expect(box.get(Home.profileSourceKey), 'qq');
      qq.update(true);
      await tester.pump();
      expect(home!.displayProfileSource, MusicSource.qq);
      home!.loginStatus.value = LoginStatus.noLogin;
      qq.update(false);
      await tester.pump();
      expect(home!.displayProfileSource, isNull);
      expect(home!.displayAvatarUrl, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      Get.reset();
      qq.dispose();
      await tester.runAsync(audio.dispose);
      tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
    });
  }
}
