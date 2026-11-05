// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'dart:convert';
import 'package:bujuan/common/music/qq_music.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('qq-session-regression');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test('foreground retries a temporary protected-store failure without login', () async {
    var reads = 0;
    messenger.setMockMethodCallHandler(channel, (c) async {
      if (c.method == 'readSession') { if (++reads == 1) throw PlatformException(code:'locked'); return 'uin=123; qqmusic_key=fixture'; }
      throw StateError('No login or clear should occur');
    });
    final q=QqMusic(channel:channel);
    await expectLater(q.restore(), throwsA(isA<Exception>()));
    q.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds:10));
    expect(q.loggedIn,true);expect(reads,2);q.dispose();
  });
  test(
      'temporary protected-storage read failure retries without deleting credentials',
      () async {
    var reads = 0, clears = 0;
    messenger.setMockMethodCallHandler(channel, (c) async {
      if (c.method == 'readSession') {
        if (++reads == 1) throw PlatformException(code: 'locked');
        return 'uin=123; qqmusic_key=fixture';
      }
      if (c.method == 'clearSession') clears++;
      return null;
    });
    final q = QqMusic(channel: channel);
    await expectLater(q.restore(), throwsA(isA<Exception>()));
    await q.restore();
    expect(q.loggedIn, true);
    expect(reads, 2);
    expect(clears, 0);
    q.dispose();
  });
  test(
      'expired session renews once for simultaneous reads, validates and stores refresh privately',
      () async {
    final old = jsonEncode({
      'cookies': 'uin=123; qqmusic_key=old-fixture; tmeLoginType=2',
      'refresh': {
        'refresh_key': 'renew-fixture',
        'refresh_token': 'refresh-fixture'
      }
    });
    String? saved;
    var refreshes = 0;
    messenger.setMockMethodCallHandler(channel, (c) async {
      if (c.method == 'readSession') return old;
      if (c.method == 'saveSession') saved = c.arguments as String;
      return null;
    });
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
        expect(
            o.headers['Cookie'].toString(), isNot(contains('renew-fixture')));
        if (o.method == 'GET') {
          h.resolve(Response(requestOptions: o, data: {
            'code': 0,
            'data': {
              'creator': {'uin': '123', 'nick': 'test'}
            }
          }));
          return;
        }
        final req = o.data['req_0'];
        if (req['module'] == 'music.login.LoginServer') {
          refreshes++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          h.resolve(Response(requestOptions: o, data: {
            'code': 0,
            'req_0': {
              'code': 0,
              'data': {
                'musicid': 123,
                'musickey': 'new-fixture',
                'refresh_key': 'next-fixture'
              }
            }
          }));
        } else {
          h.resolve(Response(
              requestOptions: o,
              data: o.data['comm']['authst'] == 'old-fixture'
                  ? {'code': 1000}
                  : {
                      'code': 0,
                      'req_0': {
                        'code': 0,
                        'data': {'ok': true}
                      }
                    }));
        }
      }));
    final q = QqMusic(channel: channel, dio: dio);
    final results = await Future.wait(
        [q.rpc('test', 'read', {}), q.rpc('test', 'read', {})]);
    expect(results.every((x) => x['ok'] == true), true);
    expect(refreshes, 1);
    expect(q.key, 'new-fixture');
    expect(jsonDecode(saved!)['refresh']['refresh_key'], 'next-fixture');
    expect(q.sessionNeedsLogin, false);
    q.dispose();
  });
  test('ordinary network failure never renews or logs out', () async {
    var webReads = 0;
    messenger.setMockMethodCallHandler(channel, (c) async {
      if (c.method == 'readSession') return 'uin=123; qqmusic_key=old';
      if (c.method == 'readWebSession') webReads++;
      return null;
    });
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(
          onRequest: (o, h) => h.reject(DioException(
              requestOptions: o, type: DioExceptionType.connectionError))));
    final q = QqMusic(channel: channel, dio: dio);
    await expectLater(q.rpc('test', 'read', {}), throwsA(isA<Exception>()));
    expect(q.loggedIn, true);
    expect(webReads, 0);
    expect(q.sessionNeedsLogin, false);
    q.dispose();
  });
  test('failed renewal keeps old saved session and shows explicit expiry',
      () async {
    var saved = 0, clears = 0;
    messenger.setMockMethodCallHandler(channel, (c) async {
      if (c.method == 'readSession') return 'uin=123; qqmusic_key=old';
      if (c.method == 'saveSession') saved++;
      if (c.method == 'clearSession') clears++;
      return null;
    });
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(
          onRequest: (o, h) =>
              h.resolve(Response(requestOptions: o, data: {'code': 1000}))));
    final q = QqMusic(channel: channel, dio: dio);
    await expectLater(q.rpc('test', 'read', {}), throwsA(isA<QqAuthExpired>()));
    expect(q.loggedIn, true);
    expect(q.sessionNeedsLogin, true);
    expect(saved, 0);
    expect(clears, 0);
    q.dispose();
  });
  test('logout during pending authentication cannot resurrect old credentials',
      () async {
    final gate = Completer<void>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (c) async {
      calls.add(c.method);
      if (c.method == 'readSession') return 'uin=123; qqmusic_key=old';
      return null;
    });
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
        await gate.future;
        h.resolve(Response(requestOptions: o, data: {
          'code': 0,
          'data': {
            'creator': {'uin': '123'}
          }
        }));
      }));
    final q = QqMusic(channel: channel, dio: dio);
    await q.restore();
    final attempt = q.acceptSession('uin=123; qqmusic_key=new');
    await Future<void>.delayed(Duration.zero);
    await q.logout();
    gate.complete();
    expect(await attempt, false);
    expect(q.loggedIn, false);
    expect(calls.where((c) => c == 'saveSession'), isEmpty);
    q.dispose();
  });
}
