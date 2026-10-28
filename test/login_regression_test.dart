// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bujuan/common/netease_api/src/api/bean.dart';
import 'package:bujuan/common/netease_api/src/api/login/api.dart';
import 'package:bujuan/common/netease_api/src/api/login/bean.dart';
import 'package:bujuan/common/netease_api/src/dio_ext.dart';
import 'package:bujuan/common/netease_api/src/netease_api.dart';
import 'package:bujuan/common/netease_api/src/netease_handler.dart';
import 'package:bujuan/pages/login/login.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/pages/user/user_controller.dart';
import 'package:bujuan/routes/router.gr.dart';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bujuan/pages/login/web_login.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:qr_flutter/qr_flutter.dart';

class _Paths extends PathProvider {
  _Paths(this.directory);
  final Directory directory;
  @override
  Future<void> init() async {}
  @override
  String getDataSavedPath() => '${directory.path}/data/';
  @override
  String getCookieSavedPath() => '${directory.path}/cookies/';
}

NeteaseAccountInfoWrap _account([int code = 200]) =>
    NeteaseAccountInfoWrap.fromJson({
      'code': code,
      if (code == 200) 'profile': {'userId': 123, 'nickname': '测试用户'},
    });

class _LoginApi with ApiLogin {
  Future<NeteaseAccountInfoWrap> Function()? passwordResponse;
  Future<QrCodeLoginKey> Function()? keyResponse;
  Future<ServerStatusBean> Function()? checkResponse;
  Future<NeteaseAccountInfoWrap> Function()? smsResponse;
  Future<ServerStatusBean> Function()? sendResponse;
  int passwords = 0;
  int emails = 0;
  int keys = 0;
  int checks = 0;
  int smsLogins = 0;
  int sends = 0;
  String? account;
  String? code;

  @override
  Future<NeteaseAccountInfoWrap> loginCellPhoneCaptcha(
      String phone, String captcha,
      {String countryCode = '86'}) async {
    smsLogins++;
    account = phone;
    code = captcha;
    return smsResponse?.call() ?? Future.value(_account());
  }

  @override
  Future<ServerStatusBean> captchaSend(String phone,
      {String ctcode = '86'}) async {
    sends++;
    account = phone;
    return sendResponse?.call() ?? Future.value(ServerStatusBean()..code = 200);
  }

  @override
  Future<NeteaseAccountInfoWrap> loginCellPhone(String phone, String password,
      {String countryCode = ''}) async {
    passwords++;
    account = phone;
    return passwordResponse?.call() ?? Future.value(_account());
  }

  @override
  Future<NeteaseAccountInfoWrap> loginEmail(
      String email, String password) async {
    emails++;
    account = email;
    return passwordResponse?.call() ?? Future.value(_account());
  }

  @override
  Future<QrCodeLoginKey> loginQrCodeKey() async {
    keys++;
    return keyResponse?.call() ??
        Future.value(QrCodeLoginKey()
          ..code = 200
          ..unikey = 'key-$keys');
  }

  @override
  Future<ServerStatusBean> loginQrCodeCheck(String key) async {
    checks++;
    return checkResponse?.call() ??
        Future.value(ServerStatusBean()..code = 801);
  }
}

class _User extends UserController {
  int refreshes = 0;
  Future<bool> Function()? response;
  @override
  void onReady() {}
  @override
  Future<bool> getUserState() async {
    refreshes++;
    return response?.call() ?? Future.value(true);
  }
}

class _ResponseAdapter implements HttpClientAdapter {
  Map<String, dynamic> response = {'code': 502, 'msg': '账号或密码错误'};
  String? requestCookies;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requestCookies = options.headers[HttpHeaders.cookieHeader] as String?;
    return ResponseBody.fromString(jsonEncode(response), 200, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _open(WidgetTester tester, _LoginApi api,
    {Size size = const Size(390, 844),
    Future<bool> Function()? webLogin,
    ThemeData? theme}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(750, 1334),
    builder: (_, __) => GetMaterialApp(
      theme: theme,
      home: Builder(
          builder: (context) => Scaffold(
                  body: TextButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) =>
                            LoginViewPage(api: api, webLogin: webLogin, autoQr: false))),
                child: const Text('打开登录'),
              ))),
    ),
  ));
  await tester.tap(find.text('打开登录'));
  await tester.pumpAndSettle();
}

Future<void> _qr(WidgetTester tester) async {
  await tester.ensureVisible(find.text('二维码登录'));
  await tester.tap(find.text('二维码登录'));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('phone and email auth use current endpoints and distinct credentials',
      () {
    final api = _LoginApi();
    final password = api.loginCellPhoneDioMetaData('13800138000', 'password');
    expect(password.uri.path, '/weapi/w/login/cellphone');
    expect(password.data['password'], '5f4dcc3b5aa765d61d8327deb882cf99');
    expect(password.data['countrycode'], '86');
    expect(password.data['type'], '1');
    expect(password.data.containsKey('captcha'), isFalse);
    final sms = api.loginCellPhoneCaptchaDioMetaData('13800138000', '0123');
    expect(sms.uri.path, '/weapi/w/login/cellphone');
    expect(sms.data['captcha'], '0123');
    expect(sms.data.containsKey('password'), isFalse);
    expect(sms.data['remember'], 'true');
    final email = api.loginEmailDioMetaData('test@163.com', 'password');
    expect(email.uri.path, '/weapi/w/login');
    expect(email.data['type'], '0');
    final sending = api.captchaSendDioMetaData('13800138000');
    expect(sending.data['secrete'], 'music_middleuser_pclogin');
    expect(sending.data['ctcode'], '86');
  });

  test('the avatar and sidebar login path resolves to a login page', () {
    final router = RootRouter();
    final matches = router.matcher.match('/login');
    expect(matches, isNotNull);
    expect(matches!.last.name, LoginViewRoute.name);
    router.dispose();
  });

  group('account persistence', () {
    late Directory directory;
    late UserLoginStateController state;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('bujuan-login');
      await NeteaseMusicApi.init(provider: _Paths(directory));
      await NeteaseMusicApi().usc.init();
      state = UserLoginStateController();
      await state.init();
    });
    tearDown(() async {
      state.destroy();
      Https.dio.interceptors.clear();
      await directory.delete(recursive: true);
    });

    test('failed credentials and anonymous responses never become a login',
        () async {
      await state.onLogined(_account(502));
      await state.onLogined(NeteaseAccountInfoWrap()..code = 200);
      expect(state.isLogined, isFalse);
      expect(state.accountInfo, isNull);
      expect(
          jsonDecode(await File('${directory.path}/data/_accountInfo.json')
              .readAsString()),
          isNull);
    });

    test('invalid accounts cached by older versions are discarded', () async {
      await File('${directory.path}/data/_accountInfo.json')
          .writeAsString(jsonEncode({'code': 502, 'msg': '登录失败'}));
      final restored = UserLoginStateController();
      await restored.init();
      expect(restored.isLogined, isFalse);
      expect(restored.accountInfo, isNull);
      restored.destroy();
    });

    test('a failed response cannot replace an authenticated account', () async {
      await state.onLogined(_account());
      await state.onLogined(_account(502));
      expect(state.isLogined, isTrue);
      expect(state.accountInfo!.profile!.userId, '123');
      expect(
          jsonDecode(await File('${directory.path}/data/_accountInfo.json')
              .readAsString())['code'],
          200);
    });

    test('login waits for initialization and survives a restart with cookies',
        () async {
      final fresh = UserLoginStateController();
      await fresh.onLogined(_account());
      await NeteaseMusicApi.cookieManager.cookieJar
          .saveFromResponse(Uri.parse(HOST), [
        Cookie('MUSIC_U', 'test-session')
          ..expires = DateTime.now().add(const Duration(days: 1)),
      ]);
      final restored = UserLoginStateController();
      await restored.init();
      expect(restored.isLogined, isTrue);
      expect(restored.accountInfo!.profile!.nickname, '测试用户');
      await restored.onLogout();
      expect(await loadCookies(), isEmpty);
      fresh.destroy();
      restored.destroy();
    });

    const webChannel = MethodChannel('bujuan/auth');
    Future<void> webResult(String? header) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(webChannel, (_) async => header);
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(webChannel, null));
    }

    test('cancelled and malformed web sessions leave saved cookies intact',
        () async {
      final jar = NeteaseMusicApi.cookieManager.cookieJar;
      await jar.saveFromResponse(
          Uri.parse(HOST), [Cookie('MUSIC_U', 'old-test-session')]);
      await webResult(null);
      expect(await WebLogin().login(), isFalse);
      for (final header in ['__csrf=only-csrf', 'MUSIC_U=fake\r\nInjected=1']) {
        await webResult(header);
        await expectLater(
            WebLogin().login(), throwsA(isA<WebLoginException>()));
        expect((await loadCookies()).single.value, 'old-test-session');
      }
    });

    test('rejected or anonymous web auth never replaces the current session',
        () async {
      await NeteaseMusicApi().usc.onLogined(_account());
      await NeteaseMusicApi.cookieManager.cookieJar.saveFromResponse(
          Uri.parse(HOST), [Cookie('MUSIC_U', 'old-test-session')]);
      for (final response in [
        {'code': 301},
        {'code': 200}
      ]) {
        final adapter = _ResponseAdapter()..response = response;
        final verifier = Dio()..httpClientAdapter = adapter;
        await webResult('MUSIC_U=new-test-session; __csrf=new-test-csrf');
        await expectLater(WebLogin(verifier: verifier).login(),
            throwsA(isA<WebLoginException>()));
        expect(adapter.requestCookies, contains('MUSIC_U=new-test-session'));
        expect(adapter.requestCookies, isNot(contains('old-test-session')));
        expect((await loadCookies()).single.value, 'old-test-session');
        expect(NeteaseMusicApi().usc.accountInfo!.profile!.userId, '123');
      }
    });

    test(
        'validated web cookies replace duplicates and persist with the account',
        () async {
      await NeteaseMusicApi.cookieManager.cookieJar.saveFromResponse(
          Uri.parse(HOST), [
        Cookie('MUSIC_U', 'old-host-cookie'),
        Cookie('__csrf', 'old-test-csrf')
      ]);
      final adapter = _ResponseAdapter()..response = _account().toJson();
      await webResult(
          'MUSIC_U=new-test-session; __csrf=new-test-csrf; ignored=unused');
      expect(
          await WebLogin(verifier: Dio()..httpClientAdapter = adapter).login(),
          isTrue);
      final cookies = await loadCookies();
      expect(cookies.where((c) => c.name == 'MUSIC_U').single.value,
          'new-test-session');
      expect(cookies.where((c) => c.name == '__csrf').single.value,
          'new-test-csrf');
      expect(cookies.any((c) => c.name == 'ignored'), isFalse);
      final restoredJar = PersistCookieJar(
          storage:
              FileStorage(NeteaseMusicApi.pathProvider.getCookieSavedPath()));
      final persistedCookies =
          await restoredJar.loadForRequest(Uri.parse(HOST));
      expect(persistedCookies.where((c) => c.name == 'MUSIC_U').single.value,
          'new-test-session');
      final restored = UserLoginStateController();
      await restored.init();
      expect(restored.isLogined, isTrue);
      expect(restored.accountInfo!.profile!.userId, '123');
      restored.destroy();
    });

    test('password and email API failures do not publish login state',
        () async {
      final previous = Https.dio.httpClientAdapter;
      Https.dio.httpClientAdapter = _ResponseAdapter();
      try {
        await NeteaseMusicApi().usc.onLogout();
        expect(
            (await NeteaseMusicApi().loginCellPhone('13800138000', 'bad')).code,
            502);
        expect(NeteaseMusicApi().usc.isLogined, isFalse);
        expect(
            (await NeteaseMusicApi().loginEmail('test@example.com', 'bad'))
                .code,
            502);
        expect(NeteaseMusicApi().usc.isLogined, isFalse);
        expect(
            (await NeteaseMusicApi()
                    .loginCellPhoneCaptcha('13800138000', '0000'))
                .code,
            502);
        expect(NeteaseMusicApi().usc.isLogined, isFalse);
      } finally {
        Https.dio.httpClientAdapter = previous;
      }
    });
  });

  group('login page', () {
    late _User user;
    setUp(() {
      user = Get.put<UserController>(_User()) as _User;
    });
    tearDown(() {
      Get.reset();
    });

    testWidgets('only web and QR are offered, without direct credential fields',
        (tester) async {
      final api = _LoginApi();
      await _open(tester, api);
      expect(find.text('官方网页登录'), findsOneWidget);
      expect(find.text('二维码登录'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('短信验证码'), findsNothing);
      expect(find.text('账号密码'), findsNothing);
      expect(api.sends + api.smsLogins + api.passwords + api.emails, 0);
    });

    for (final theme in [AppTheme.light, AppTheme.dark]) {
      testWidgets(
          'login buttons match and remain readable in ${theme.brightness}',
          (tester) async {
        await _open(tester, _LoginApi(), theme: theme);
        final buttons =
            find.byWidgetPredicate((widget) => widget is FilledButton);
        expect(buttons, findsNWidgets(2));
        final web = tester.widget<FilledButton>(buttons.first);
        final qr = tester.widget<FilledButton>(buttons.last);
        final background = web.style!.backgroundColor!.resolve({})!;
        final foreground = web.style!.foregroundColor!.resolve({})!;
        expect(qr.style!.backgroundColor!.resolve({}), background);
        expect(qr.style!.foregroundColor!.resolve({}), foreground);
        expect(tester.getSize(buttons.first), tester.getSize(buttons.last));
        double contrast(Color a, Color b) {
          final x = a.computeLuminance(), y = b.computeLuminance();
          return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
        }

        expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
        expect(
            DefaultTextStyle.of(tester.element(find.text('二维码登录'))).style.color,
            foreground);
        await _qr(tester);
        for (final label in ['刷新二维码', '关闭二维码']) {
          final color = DefaultTextStyle.of(tester.element(find.text(label)))
              .style
              .color!;
          expect(contrast(color, theme.scaffoldBackgroundColor),
              greaterThanOrEqualTo(4.5));
        }
        await tester.tap(find.text('关闭二维码'));
        await tester.pump();
      });
    }

    testWidgets(
        'web cancellation preserves the page and does not refresh the account',
        (tester) async {
      await _open(tester, _LoginApi(), webLogin: () async => false);
      await tester.tap(find.text('官方网页登录'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginViewPage), findsOneWidget);
      expect(user.refreshes, 0);
      expect(find.text('官方网页登录'), findsOneWidget);
    });

    testWidgets(
        'web authorization waits for account synchronization and prevents repeat launches',
        (tester) async {
      final authorized = Completer<bool>();
      final refreshed = Completer<bool>();
      var launches = 0;
      user.response = () => refreshed.future;
      await _open(tester, _LoginApi(), webLogin: () {
        launches++;
        return authorized.future;
      });
      await tester.tap(find.text('官方网页登录'));
      await tester.pump();
      await tester.tap(find.text('正在认证…'));
      expect(launches, 1);
      authorized.complete(true);
      await tester.pump();
      expect(user.refreshes, 1);
      expect(find.byType(LoginViewPage), findsOneWidget);
      refreshed.complete(true);
      await tester.pumpAndSettle();
      expect(find.byType(LoginViewPage), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('跳转主页'), findsOneWidget);
      expect(find.text('继续登录QQ音乐'), findsOneWidget);
      await tester.tap(find.text('跳转主页'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginViewPage), findsNothing);
    });

    testWidgets(
        'failed web verification offers retry without pretending to log in',
        (tester) async {
      var attempts = 0;
      await _open(tester, _LoginApi(), webLogin: () async {
        attempts++;
        if (attempts == 1) throw const WebLoginException('尚未完成官方登录');
        return false;
      });
      await tester.tap(find.text('官方网页登录'));
      await tester.pumpAndSettle();
      expect(find.text('尚未完成官方登录'), findsOneWidget);
      expect(user.refreshes, 0);
      await tester.tap(find.text('官方网页登录'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('leaving during web authentication ignores late navigation',
        (tester) async {
      final pending = Completer<bool>();
      await _open(tester, _LoginApi(), webLogin: () => pending.future);
      await tester.tap(find.text('官方网页登录'));
      await tester.pump();
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      pending.complete(true);
      await tester.pumpAndSettle();
      expect(user.refreshes, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('QR renders and handles scanned, expired, refresh and close',
        (tester) async {
      final api = _LoginApi();
      await _open(tester, api);
      await _qr(tester);
      expect(find.byType(QrImageView), findsOneWidget);
      api.checkResponse = () async => ServerStatusBean()..code = 802;
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('已扫码，请在手机上确认登录'), findsOneWidget);
      api.checkResponse = () async => ServerStatusBean()..code = 800;
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('二维码已过期，请刷新二维码'), findsOneWidget);
      final checks = api.checks;
      await tester.pump(const Duration(seconds: 6));
      expect(api.checks, checks);
      await tester.tap(find.text('刷新二维码'));
      await tester.pump();
      expect(api.keys, 2);
      await tester.tap(find.text('关闭二维码'));
      await tester.pump(const Duration(seconds: 6));
      expect(find.byType(QrImageView), findsNothing);
      expect(api.checks, checks);
    });

    testWidgets('QR polling cannot overlap or navigate after it is closed',
        (tester) async {
      final pending = Completer<ServerStatusBean>();
      final api = _LoginApi()..checkResponse = () => pending.future;
      await _open(tester, api);
      await _qr(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 6));
      expect(api.checks, 1);
      await tester.tap(find.text('关闭二维码'));
      pending.complete(ServerStatusBean()..code = 803);
      await tester.pump();
      expect(user.refreshes, 0);
      expect(find.byType(LoginViewPage), findsOneWidget);
    });

    testWidgets('QR authorization waits for profile then shows platform actions',
        (tester) async {
      final refreshed = Completer<bool>();
      user.response = () => refreshed.future;
      final api = _LoginApi()
        ..checkResponse = () async => ServerStatusBean()..code = 803;
      await _open(tester, api);
      await _qr(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('授权成功，正在获取用户资料…'), findsOneWidget);
      expect(user.refreshes, 1);
      refreshed.complete(true);
      await tester.pumpAndSettle();
      expect(find.byType(LoginViewPage), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('退出网易云登录'), findsOneWidget);
    });

    testWidgets('closing while a QR key is loading ignores the late result',
        (tester) async {
      final pending = Completer<QrCodeLoginKey>();
      final api = _LoginApi()..keyResponse = () => pending.future;
      await _open(tester, api);
      await _qr(tester);
      await tester.tap(find.text('关闭二维码'));
      pending.complete(QrCodeLoginKey()
        ..code = 200
        ..unikey = 'old-key');
      await tester.pump(const Duration(seconds: 6));
      expect(find.byType(QrImageView), findsNothing);
      expect(api.checks, 0);
    });

    for (final size in [
      const Size(844, 390),
      const Size(640, 300),
      const Size(800, 1280),
      const Size(1280, 800)
    ]) {
      testWidgets('login QR and controls fit a landscape window $size',
          (tester) async {
        await _open(tester, _LoginApi(), size: size);
        await _qr(tester);
        expect(find.byType(QrImageView), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('关闭二维码'));
        await tester.pump();
      });
    }
  });
}
