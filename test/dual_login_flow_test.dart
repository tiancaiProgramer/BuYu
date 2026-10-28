// Community maintenance and new features: tiancaiProgramer.
import 'dart:typed_data';
import 'package:bujuan/common/music/music_source.dart';
import 'package:bujuan/common/music/qq_music.dart';
import 'package:bujuan/common/music/qq_qr_login.dart';
import 'package:bujuan/pages/login/login.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:qr_flutter/qr_flutter.dart';

class ExchangeMusic extends QqMusic {
  int exchanges = 0;
  @override
  Future<String> exchangeQrCode(String code) async {
    exchanges++;
    expect(code, 'fake-code');
    return 'uin=123; qqmusic_key=fake-key';
  }
}

class NoScanQr extends QqQrLogin {
  @override
  Future<Uint8List> create() async =>
      throw const MusicServiceError('test QR ready');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() async {
    await GetIt.I.reset();
  });
  test(
      'QQ successful scan completes full check_sig and OAuth, retries saved ticket without a rescan',
      () async {
    final dio = Dio();
    final steps = <String>[];
    final music = ExchangeMusic();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      steps.add(o.uri.path);
      if (o.uri.path == '/ptqrshow') {
        h.resolve(Response(
            requestOptions: o,
            data: [137, 80, 78, 71, 13, 10, 26, 10],
            headers: Headers.fromMap({
              'set-cookie': ['qrsig=fake-qr; Secure; HttpOnly']
            })));
      } else if (o.uri.path == '/ptqrlogin') {
        h.resolve(Response(
            requestOptions: o,
            data:
                "ptuiCB('0','0','https://ssl.ptlogin2.graph.qq.com/check_sig?uin=123&ptsigx=fake-signature&s_url=x','0','success','name');"));
      } else if (o.uri.path == '/check_sig') {
        expect(o.uri.host, 'ssl.ptlogin2.graph.qq.com');
        expect(o.queryParameters['nodirect'], '0');
        expect(o.queryParameters['ptredirect'], '100');
        expect(o.queryParameters['pt_3rd_aid'], '100497308');
        expect(o.queryParameters['pt_login_type'], '3');
        expect(o.headers['Cookie'], isNull);
        h.resolve(Response(
            requestOptions: o,
            statusCode: 302,
            headers: Headers.fromMap({
              'set-cookie': [
                'p_skey=fake-pskey; Domain=graph.qq.com; Secure; HttpOnly',
                'p_skey=; Domain=qq.com; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/',
                'p_uin=o00123; Secure'
              ]
            })));
      } else if (o.uri.path == '/oauth2.0/authorize') {
        expect(o.headers['Cookie'], contains('p_skey=fake-pskey'));
        expect(o.data['client_id'], '100497308');
        h.resolve(Response(
            requestOptions: o,
            statusCode: 302,
            headers: Headers.fromMap({
              'location': [
                'https://y.qq.com/portal/wx_redirect.html?login_type=1&code=fake-code&state=state'
              ]
            })));
      } else {
        fail('unexpected host');
      }
    }));
    final qr = QqQrLogin(dio: dio);
    await qr.create();
    expect(await qr.check(music), 'uin=123; qqmusic_key=fake-key');
    expect(await qr.check(music), 'uin=123; qqmusic_key=fake-key');
    expect(steps,
        ['/ptqrshow', '/ptqrlogin', '/check_sig', '/oauth2.0/authorize']);
    expect(music.exchanges, 1);
    qr.close();
    music.dispose();
  });
  test('parent-domain deletions never overwrite a valid scoped QQ OAuth cookie', () {
    final qr=QqQrLogin();
    final response=Response(requestOptions:RequestOptions(path:'https://ssl.ptlogin2.graph.qq.com/check_sig'),headers:Headers.fromMap({'set-cookie':[
      'p_skey=valid-fixture; Domain=graph.qq.com; Path=/; Secure',
      'p_uin=account-fixture; Domain=graph.qq.com; Path=/; Secure',
      'p_skey=; Domain=qq.com; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT',
      'p_uin=; Domain=qq.com; Path=/; Max-Age=0',
      'unrelated=never; Domain=example.org; Path=/',
    ]}));
    expect(qr.cookies(response,forUri:Uri.parse('https://graph.qq.com/oauth2.0/authorize')),{'p_skey':'valid-fixture','p_uin':'account-fixture'});
    expect(qr.cookies(response,forUri:Uri.parse('https://y.qq.com/')),isEmpty);
    qr.close();
  });
  test('QQ auth cookie may arrive on the bounded official login-jump redirect', () async {
    final dio=Dio();final music=ExchangeMusic();final paths=<String>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h){
      paths.add(o.uri.path);
      if(o.uri.path=='/ptqrshow')h.resolve(Response(requestOptions:o,data:[137,80,78,71,13,10,26,10],headers:Headers.fromMap({'set-cookie':['qrsig=fake']})));
      else if(o.uri.path=='/ptqrlogin')h.resolve(Response(requestOptions:o,data:"ptuiCB('0','0','https://ssl.ptlogin2.graph.qq.com/check_sig?uin=123&ptsigx=fake','0','','');"));
      else if(o.uri.path=='/check_sig')h.resolve(Response(requestOptions:o,statusCode:302,headers:Headers.fromMap({'location':['https://graph.qq.com/oauth2.0/login_jump'],'set-cookie':['p_uin=o00123; Secure']})));
      else if(o.uri.path=='/oauth2.0/login_jump')h.resolve(Response(requestOptions:o,statusCode:200,headers:Headers.fromMap({'set-cookie':['p_skey=fake-key; Domain=graph.qq.com; Secure']})));
      else h.resolve(Response(requestOptions:o,statusCode:302,headers:Headers.fromMap({'location':['https://y.qq.com/portal/wx_redirect.html?code=fake-code&state=state']})));
    }));
    final qr=QqQrLogin(dio:dio);await qr.create();expect(await qr.check(music),isNotNull);
    expect(paths,contains('/oauth2.0/login_jump'));qr.close();music.dispose();
  });
  test('QQ scan rejects a callback to a nonofficial host before requesting it',
      () async {
    final dio = Dio();
    final qq = ExchangeMusic();
    var calls = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      calls++;
      if (o.uri.path == '/ptqrshow')
        h.resolve(Response(
            requestOptions: o,
            data: [137, 80, 78, 71, 13, 10, 26, 10],
            headers: Headers.fromMap({
              'set-cookie': ['qrsig=fake']
            })));
      else
        h.resolve(Response(
            requestOptions: o,
            data:
                "ptuiCB('0','0','https://example.org/check_sig?uin=123&ptsigx=secret','0','','');"));
    }));
    final qr = QqQrLogin(dio: dio);
    await qr.create();
    await expectLater(qr.check(qq), throwsA(isA<MusicServiceError>()));
    expect(calls, 2);
    qr.close();
    qq.dispose();
  });
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets(
        'one account shows three actions, two accounts show two, and logout is isolated at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final statuses = {MusicSource.netease: true, MusicSource.qq: false};
      final signedOut = <MusicSource>[];
      await tester.pumpWidget(MaterialApp(
          home: LoginViewPage(
              autoQr: true,
              statusReader: (s) => statuses[s]!,
              qqQrFactory: NoScanQr.new,
              signOut: (s) async {
                signedOut.add(s);
                statuses[s] = false;
              })));
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('跳转主页'), findsOneWidget);
      expect(find.text('继续登录QQ音乐'), findsOneWidget);
      expect(find.text('退出网易云登录'), findsOneWidget);
      final logout = tester.widget<OutlinedButton>(find.byKey(const ValueKey('login-logout')));
      expect(logout.onPressed, isNotNull);
      final ink = logout.style!.foregroundColor!.resolve({})!;
      expect(ink.computeLuminance(), lessThan(.4));
      await tester.ensureVisible(find.text('继续登录QQ音乐'));
      await tester.tap(find.text('继续登录QQ音乐'));
      await tester.pumpAndSettle();
      expect(find.text('登录QQ音乐'), findsOneWidget);
      expect(find.text('官方网页登录'), findsOneWidget);
      statuses[MusicSource.qq] = true;
      await tester.tap(find.widgetWithText(ChoiceChip, '网易云'));
      await tester.pumpAndSettle();
      expect(find.text('继续登录QQ音乐'), findsNothing);
      expect(find.text('跳转主页'), findsOneWidget);
      expect(find.text('退出网易云登录'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'QQ音乐'));
      await tester.pumpAndSettle();
      expect(find.text('退出QQ音乐登录'), findsOneWidget);
      expect(find.text('继续登录网易云'), findsNothing);
      await tester.ensureVisible(find.text('退出QQ音乐登录'));
      await tester.tap(find.text('退出QQ音乐登录'));
      await tester.pumpAndSettle();
      expect(signedOut, [MusicSource.qq]);
      expect(statuses[MusicSource.netease], true);
      await tester.tap(find.widgetWithText(ChoiceChip, '网易云'));
      await tester.pumpAndSettle();
      expect(find.text('继续登录QQ音乐'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
