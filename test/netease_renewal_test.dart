// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:bujuan/common/netease_api/src/netease_api.dart';
import 'package:bujuan/common/netease_api/src/netease_handler.dart';
import 'package:bujuan/common/netease_api/src/api/login/bean.dart';
import 'package:bujuan/common/netease_api/src/dio_ext.dart';
import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';

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

ResponseBody _json(int code, {List<String>? cookies}) =>
    ResponseBody.fromString(jsonEncode({'code': code, 'fixture': true}), 200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
          if (cookies != null) HttpHeaders.setCookieHeader: cookies,
        });

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(
          RequestOptions o, Stream<Uint8List>? stream, Future<void>? cancel) =>
      respond(o);
  @override
  void close({bool force = false}) {}
}

NeteaseAccountInfoWrap _account(int id) => NeteaseAccountInfoWrap.fromJson({
      'code': 200,
      'profile': {'userId': id, 'nickname': 'fixture'},
    });

class _Fixture {
  late Directory directory;
  late HttpClientAdapter originalAdapter;
  var requests = 0, refreshes = 0;
  Future<ResponseBody> Function(RequestOptions) main = (_) async => _json(301);
  Future<ResponseBody> Function(RequestOptions) renewal =
      (_) async => _json(200);
  NeteaseMusicApi get api => NeteaseMusicApi();
  Future<void> init() async {
    directory = await Directory.systemTemp.createTemp('buyu-nt-renewal');
    originalAdapter = Https.dio.httpClientAdapter;
    await NeteaseMusicApi.init(
        provider: _Paths(directory),
        refreshClientFactory: () {
          return Dio()
            ..httpClientAdapter = _Adapter((o) async {
              refreshes++;
              expect(o.uri.host, 'music.163.com');
              expect(o.uri.path, '/weapi/login/token/refresh');
              return renewal(o);
            });
        });
    api.usc = UserLoginStateController();
    await api.usc.init();
    await api.usc.onLogined(_account(123));
    await NeteaseMusicApi.cookieManager.cookieJar
        .saveFromResponse(Uri.parse(HOST), [
      Cookie('MUSIC_U', 'fixture-old')..path = '/',
      Cookie('__csrf', 'csrf-old')..path = '/',
    ]);
    Https.dio.httpClientAdapter = _Adapter((o) async {
      requests++;
      return main(o);
    });
  }

  Future<Response> get({CancelToken? cancel}) =>
      Https.dio.get('$HOST/weapi/session/test', cancelToken: cancel);
  Future<void> close() async {
    Https.dio.interceptors.clear();
    Https.dio.httpClientAdapter = originalAdapter;
    api.usc.destroy();
    await directory.delete(recursive: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() async {
    f = _Fixture();
    await f.init();
  });
  tearDown(() => f.close());

  for (final error in [
    'network',
    'timeout',
    'malformed',
    'service',
    'risk',
    'unsupported'
  ]) {
    test(
        'refresh $error failure preserves persisted credentials and avoids false logout',
        () async {
      f.renewal = (o) async {
        if (error == 'network' || error == 'timeout')
          throw DioException(
              requestOptions: o,
              type: error == 'network'
                  ? DioExceptionType.connectionError
                  : DioExceptionType.receiveTimeout);
        if (error == 'malformed')
          return ResponseBody.fromString('not-json', 200);
        return _json(error == 'risk'
            ? 250
            : error == 'unsupported'
                ? 400
                : 500);
      };
      await expectLater(
          f.get(),
          throwsA(isA<DioException>().having((e) => e.response,
              'transient error has no auth response', isNull)));
      expect(f.refreshes, 1);
      expect(f.requests, 1);
      expect(f.api.usc.isLogined, true);
      expect((await loadCookies()).any((c) => c.name == 'MUSIC_U'), true);
      final restored = UserLoginStateController();
      await restored.init();
      expect(restored.isLogined, true);
      restored.destroy();
      await expectLater(f.get(), throwsA(isA<DioException>()));
      expect(f.refreshes, 1, reason: 'failed refreshes have a cooldown');
    });
  }

  test(
      'successful unchanged-cookie refresh retries once with a matching generation signature',
      () async {
    f.main = (o) async {
      if (o.extra['neteaseRecoveryAttempted'] == true) {
        expect(o.extra['cookiesHash'], await loadCookiesHash(host: o.uri));
        return _json(200);
      }
      return _json(301);
    };
    final version = f.api.loginRefreshVersion;
    final response = await Https.dio.post('$HOST/weapi/session/test',
        data: {'song': 123}, options: joinOptions());
    expect(response.data['code'], 200);
    expect(f.requests, 2);
    expect(f.refreshes, 1);
    expect(f.api.loginRefreshVersion, version + 1);
    expect(f.api.usc.isLogined, true);
  });

  test('parallel expired requests share one real refresh transport', () async {
    final allSent = Completer<void>();
    var sent = 0;
    f.main = (o) async {
      if (o.extra['neteaseRecoveryAttempted'] == true) return _json(200);
      if (++sent == 3) allSent.complete();
      await allSent.future;
      return _json(301);
    };
    f.renewal = (_) async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return _json(200);
    };
    final responses = await Future.wait([f.get(), f.get(), f.get()]);
    expect(responses.every((r) => r.data['code'] == 200), true);
    expect(f.refreshes, 1);
    expect(f.requests, 6);
  });

  test('a repeated 301 cannot cause an unlimited recursive retry', () async {
    final result = await f.get().timeout(const Duration(seconds: 2));
    expect(result.data['code'], 301);
    expect(f.requests, 2);
    expect(f.refreshes, 1);
    expect(f.api.usc.isLogined, true,
        reason:
            'one endpoint failing after renewal does not erase credentials');
  });

  test(
      'confirmed renewal rejection invalidates once and all waiters receive authentication status',
      () async {
    final allSent = Completer<void>();
    var sent = 0;
    f.main = (_) async {
      if (++sent == 3) allSent.complete();
      await allSent.future;
      return _json(301);
    };
    f.renewal = (_) async => _json(301);
    final responses = await Future.wait([f.get(), f.get(), f.get()]);
    expect(responses.every((r) => r.data['code'] == 301), true);
    expect(f.refreshes, 1);
    expect(f.api.usc.isLogined, false);
    expect(await loadCookies(), isEmpty);
  });

  test('ordinary request network error never starts renewal', () async {
    f.main = (o) async => throw DioException(
        requestOptions: o, type: DioExceptionType.connectionError);
    await expectLater(f.get(), throwsA(isA<DioException>()));
    expect(f.refreshes, 0);
    expect(f.api.usc.isLogined, true);
  });

  test(
      'third-party 301 and login endpoint 301 cannot renew or clear a music session',
      () async {
    f.main = (o) async {
      if (o.uri.host == 'example.test')
        expect(o.headers['cookie'], isNot(contains('fixture-old')));
      return _json(301);
    };
    expect(
        (await Https.dio.get('https://example.test/test')).data['code'], 301);
    expect((await Https.dio.get('$HOST/weapi/login/qrcode/test')).data['code'],
        301);
    expect(f.refreshes, 0);
    expect(f.api.usc.isLogined, true);
  });

  test(
      'logout during renewal prevents late Set-Cookie from restoring authentication',
      () async {
    final started = Completer<void>(), release = Completer<void>();
    f.renewal = (_) async {
      started.complete();
      await release.future;
      return _json(200,
          cookies: ['MUSIC_U=late-fixture; Domain=.music.163.com; Path=/']);
    };
    final pending = f.get();
    final checked = expectLater(pending, throwsA(isA<DioException>()));
    await started.future;
    await f.api.usc.onLogout();
    release.complete();
    await checked;
    expect(f.api.usc.isLogined, false);
    expect(await loadCookies(), isEmpty);
    final restored = UserLoginStateController();
    await restored.init();
    expect(restored.isLogined, false);
    restored.destroy();
  });

  test(
      'switching accounts while renewal is pending protects the new account and cookies',
      () async {
    final started = Completer<void>(), release = Completer<void>();
    f.renewal = (_) async {
      started.complete();
      await release.future;
      return _json(301,
          cookies: ['MUSIC_U=late-fixture; Domain=.music.163.com; Path=/']);
    };
    final pending = f.get();
    final checked = expectLater(pending, throwsA(isA<DioException>()));
    await started.future;
    await f.api.usc.onLogined(_account(456));
    await NeteaseMusicApi.cookieManager.cookieJar.saveFromResponse(
        Uri.parse(HOST), [Cookie('MUSIC_U', 'fixture-new')..path = '/']);
    release.complete();
    await checked;
    expect(f.api.usc.accountInfo?.profile?.userId, '456');
    expect(f.api.usc.isLogined, true);
    expect((await loadCookies()).singleWhere((c) => c.name == 'MUSIC_U').value,
        'fixture-new');
  });

  test(
      'retry re-encrypts the original payload with rotated EAPI authentication headers',
      () async {
    Map decode(RequestOptions o) {
      final encoded = Uri.splitQueryString(o.data as String)['params']!;
      final text = crypto.Encrypter(crypto.AES(
              crypto.Key.fromUtf8('e82ckenh8dichen8'),
              mode: crypto.AESMode.ecb))
          .decrypt(crypto.Encrypted.fromBase16(encoded),
              iv: crypto.IV.fromLength(0));
      return jsonDecode(text.split('-36cd479b6b5-')[1]) as Map;
    }

    f.main = (o) async {
      final retried = o.extra['neteaseRecoveryAttempted'] == true;
      final payload = decode(o);
      expect(payload['song'], 123);
      expect(payload['header']['MUSIC_U'],
          retried ? 'fixture-new' : 'fixture-old');
      expect(payload['header']['__csrf'], retried ? 'csrf-new' : 'csrf-old');
      return _json(retried ? 200 : 301);
    };
    f.renewal = (_) async => _json(200,
        cookies: ['MUSIC_U=fixture-new; Path=/', '__csrf=csrf-new; Path=/']);
    final response = await Https.dio.post('$HOST/eapi/session/test',
        data: {'song': 123},
        options: joinOptions(
            encryptType: EncryptType.EApi, eApiUrl: '/api/session/test'));
    expect(response.data['code'], 200);
    expect(f.requests, 2);
  });

  test('cancelling one waiter does not cancel another caller shared renewal',
      () async {
    final started = Completer<void>(), release = Completer<void>();
    f.renewal = (_) async {
      if (!started.isCompleted) started.complete();
      await release.future;
      return _json(200);
    };
    f.main = (o) async =>
        _json(o.extra['neteaseRecoveryAttempted'] == true ? 200 : 301);
    final token = CancelToken();
    final cancelled = f.get(cancel: token);
    final checked = expectLater(
        cancelled,
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.cancel)));
    final active = f.get();
    await started.future;
    token.cancel('fixture');
    release.complete();
    await checked;
    expect((await active).data['code'], 200);
    expect(f.refreshes, 1);
    expect(f.api.usc.isLogined, true);
  });

  test(
      'irrelevant tracking cookies do not masquerade as a new authenticated session',
      () async {
    final before = await loadCookiesHash();
    await NeteaseMusicApi.cookieManager.cookieJar.saveFromResponse(
        Uri.parse(HOST), [Cookie('NMTID', 'tracking-fixture')]);
    expect(await loadCookiesHash(), before);
  });
}
