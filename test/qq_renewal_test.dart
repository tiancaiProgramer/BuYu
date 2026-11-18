// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'dart:convert';
import 'package:bujuan/common/music/qq_music.dart';
import 'package:bujuan/common/music/qq_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('qq-renewal-regression');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final epoch = DateTime.fromMillisecondsSinceEpoch(1800000000000);
  Map<String, dynamic> issued({String key = 'new-fixture', int id = 123}) => {
        'musicid': id,
        'musickey': key,
        'openid': 'open-fixture',
        'refresh_key': 'renew-fixture',
        'refresh_token': 'refresh-fixture',
        'access_token': 'access-fixture',
        'expired_in': 123456,
        'musickeyCreateTime': epoch.millisecondsSinceEpoch ~/ 1000,
        'keyExpiresIn': 3600,
        'needRefreshKeyIn': 1800,
      };
  String session(Map refresh, {String key = 'old-fixture'}) => jsonEncode({
        'cookies': 'uin=123; qqmusic_key=$key; qm_keyst=$key; tmeLoginType=2',
        'refresh': refresh,
      });
  final profiles = {
    'code': 0,
    'data': {
      'creator': {'uin': '123', 'nick': 'fixture'}
    }
  };
  Map response(Map data) => {
        'code': 0,
        'req_0': {'code': 0, 'data': data}
      };
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final type in [1, 2]) {
    test(
        'official web authorization exchanges complete ${type == 2 ? 'QQ' : 'WeChat'} response and restores metadata',
        () async {
      String? saved;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'login')
          return jsonEncode({
            'authorization': {'code': 'code-fixture', 'loginType': type}
          });
        if (call.method == 'saveSession') saved = call.arguments as String;
        if (call.method == 'readSession') return saved;
        return null;
      });
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
          if (o.method == 'GET') {
            h.resolve(Response(requestOptions: o, data: profiles));
            return;
          }
          expect(o.headers['Cookie'], isNull);
          expect(o.data['comm']['tmeLoginType'], type);
          expect(
              o.data['req_0']['module'],
              type == 2
                  ? 'QQConnectLogin.LoginServer'
                  : 'music.login.LoginServer');
          expect(o.data['req_0']['param']['code'], 'code-fixture');
          if (type == 1)
            expect(o.data['req_0']['param']['strAppid'], 'wx48db31d50e334801');
          h.resolve(Response(
              requestOptions: o,
              data: response(
                  {...issued(), 'unknown_private_field': 'discard-fixture'})));
        }));
      final q = QqMusic(channel: channel, dio: dio, now: () => epoch);
      expect(await q.login(fresh: true), true);
      final stored = jsonDecode(saved!);
      expect(stored['refresh']['refresh_token'], 'refresh-fixture');
      expect(stored['refresh']['keyExpiresIn'], 3600);
      expect(stored['refresh']['needRefreshKeyIn'], 1800);
      expect(saved, isNot(contains('discard-fixture')));
      q.dispose();
      final restored = QqMusic(channel: channel, now: () => epoch);
      await restored.restore();
      expect(restored.loggedIn, true);
      expect(restored.key, 'new-fixture');
      restored.dispose();
    });
  }

  test('music lifetime drives renewal independently of OAuth expiry', () {
    final metadata =
        QqSessionMetadata.issued({...issued(), 'expired_in': 1}, epoch);
    expect(QqSessionMetadata.renewalAt(metadata, epoch),
        epoch.add(const Duration(minutes: 30)));
    metadata.remove('needRefreshKeyIn');
    expect(QqSessionMetadata.renewalAt(metadata, epoch),
        epoch.add(const Duration(minutes: 55)));
    final threeDayKey = QqSessionMetadata.issued(
        {...issued(), 'keyExpiresIn': 259200, 'needRefreshKeyIn': 0}, epoch);
    expect(QqSessionMetadata.renewalAt(threeDayKey, epoch),
        epoch.add(const Duration(days: 2)));
    final next = QqSessionMetadata.issued(
        {'refresh_key': 'next'}, epoch.add(const Duration(hours: 1)),
        previous: metadata);
    expect(next.containsKey('musickeyCreateTime'), false);
    expect(QqSessionMetadata.renewalAt(next, epoch),
        epoch.add(const Duration(minutes: 90)));
  });

  test(
      'overdue restored session renews once before concurrent authenticated calls and survives restart',
      () async {
    var clock = epoch.add(const Duration(minutes: 31));
    String? saved = session(QqSessionMetadata.issued(issued(), epoch));
    var renewals = 0, reads = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'readSession') return saved;
      if (call.method == 'saveSession') saved = call.arguments as String;
      return null;
    });
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
        if (o.method == 'GET') {
          h.resolve(Response(requestOptions: o, data: profiles));
          return;
        }
        final req = o.data['req_0'];
        if (req['module'] == 'music.login.LoginServer') {
          renewals++;
          expect(req['param']['loginMode'], 2);
          expect(req['param']['expired_in'], 123456);
          expect(req['param'].containsKey('receivedAt'), false);
          expect(req['param'].containsKey('keyExpiresIn'), false);
          expect(o.headers['Cookie'], isNot(contains('refresh-fixture')));
          await Future<void>.delayed(const Duration(milliseconds: 5));
          h.resolve(Response(
              requestOptions: o,
              data: response({
                ...issued(),
                'musickeyCreateTime': clock.millisecondsSinceEpoch ~/ 1000
              })));
        } else {
          reads++;
          expect(o.data['comm']['authst'], 'new-fixture');
          expect(o.headers['Cookie'], contains('qm_keyst=new-fixture'));
          h.resolve(Response(requestOptions: o, data: response({'ok': true})));
        }
      }));
    final q = QqMusic(channel: channel, dio: dio, now: () => clock);
    await Future.wait([
      q.rpc('test', 'read', {}, auth: true),
      q.rpc('test', 'read', {}, auth: true)
    ]);
    expect(renewals, 1);
    expect(reads, 2);
    expect(q.sessionNeedsLogin, false);
    q.dispose();
    final restored = QqMusic(channel: channel, now: () => clock);
    await restored.restore();
    expect(await restored.refreshSessionIfNeeded(), true);
    expect(restored.key, 'new-fixture');
    restored.dispose();
  });

  testWidgets('active app timer renews before music key expiry',
      (tester) async {
    var clock = epoch;
    var renewals = 0;
    messenger.setMockMethodCallHandler(
        channel,
        (c) async => c.method == 'readSession'
            ? session(QqSessionMetadata.issued(
                {...issued(), 'needRefreshKeyIn': 120}, epoch))
            : null);
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.method == 'GET') {
          h.resolve(Response(requestOptions: o, data: profiles));
          return;
        }
        renewals++;
        h.resolve(Response(
            requestOptions: o,
            data: response({
              ...issued(),
              'musickeyCreateTime': clock.millisecondsSinceEpoch ~/ 1000
            })));
      }));
    final q = QqMusic(channel: channel, dio: dio, now: () => clock);
    await q.restore();
    expect(renewals, 0);
    clock = epoch.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2));
    await tester.pump();
    expect(renewals, 1);
    expect(q.key, 'new-fixture');
    q.dispose();
  });

  test('foreground performs overdue renewal after suspension', () async {
    var clock = epoch, renewals = 0;
    messenger.setMockMethodCallHandler(
        channel,
        (c) async => c.method == 'readSession'
            ? session(QqSessionMetadata.issued(issued(), epoch))
            : null);
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.method == 'GET') {
          h.resolve(Response(requestOptions: o, data: profiles));
          return;
        }
        renewals++;
        h.resolve(Response(requestOptions: o, data: response(issued())));
      }));
    final q = QqMusic(channel: channel, dio: dio, now: () => clock);
    await q.restore();
    clock = epoch.add(const Duration(hours: 2));
    q.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(renewals, 1);
    q.dispose();
  });

  testWidgets('long lifetime keeps scheduling after a bounded timer wakeup',
      (tester) async {
    var clock = epoch;
    var renewals = 0;
    messenger.setMockMethodCallHandler(
        channel,
        (c) async => c.method == 'readSession'
            ? session(QqSessionMetadata.issued({
                ...issued(),
                'needRefreshKeyIn': 172800,
                'keyExpiresIn': 604800
              }, epoch))
            : null);
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.method == 'GET') {
          h.resolve(Response(requestOptions: o, data: profiles));
          return;
        }
        renewals++;
        h.resolve(Response(
            requestOptions: o,
            data: response({
              ...issued(),
              'musickeyCreateTime': clock.millisecondsSinceEpoch ~/ 1000
            })));
      }));
    final q = QqMusic(channel: channel, dio: dio, now: () => clock);
    await q.restore();
    clock = epoch.add(const Duration(days: 1));
    await tester.pump(const Duration(days: 1));
    await tester.pump();
    expect(renewals, 0);
    clock = epoch.add(const Duration(days: 2));
    await tester.pump(const Duration(days: 1));
    await tester.pump();
    expect(renewals, 1);
    q.dispose();
  });

  test(
      'reauthentication state still retries renewable credentials after network recovers',
      () async {
    var clock = epoch;
    var online = false, renewals = 0;
    messenger.setMockMethodCallHandler(
        channel,
        (c) async => c.method == 'readSession'
            ? session({'refresh_key': 'fixture'})
            : null);
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.method == 'GET') {
          h.resolve(Response(requestOptions: o, data: profiles));
          return;
        }
        renewals++;
        if (!online) {
          h.reject(DioException(
              requestOptions: o, type: DioExceptionType.connectionError));
          return;
        }
        h.resolve(Response(
            requestOptions: o,
            data: response({
              ...issued(),
              'musickeyCreateTime': clock.millisecondsSinceEpoch ~/ 1000
            })));
      }));
    final q = QqMusic(channel: channel, dio: dio, now: () => clock);
    await q.restore();
    expect(await q.recoverSession(), false);
    expect(q.sessionNeedsLogin, true);
    expect(await q.refreshSessionIfNeeded(), false);
    expect(renewals, 1);
    online = true;
    clock = epoch.add(const Duration(minutes: 6));
    q.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(renewals, 2);
    expect(q.sessionNeedsLogin, false);
    expect(q.key, 'new-fixture');
    q.dispose();
  });

  test(
      'proactive renewal network failure preserves valid session and backs off',
      () async {
    var clock = epoch.add(const Duration(minutes: 31));
    var renewals = 0, saves = 0;
    messenger.setMockMethodCallHandler(channel, (c) async {
      if (c.method == 'readSession')
        return session(QqSessionMetadata.issued(issued(), epoch));
      if (c.method == 'saveSession' || c.method == 'clearSession') saves++;
      return null;
    });
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.data['req_0']['module'] == 'music.login.LoginServer') {
          renewals++;
          h.reject(DioException(
              requestOptions: o, type: DioExceptionType.connectionError));
        } else
          h.resolve(Response(requestOptions: o, data: response({'ok': true})));
      }));
    final q = QqMusic(channel: channel, dio: dio, now: () => clock);
    expect((await q.rpc('test', 'read', {}))['ok'], true);
    expect((await q.rpc('test', 'read', {}))['ok'], true);
    expect(renewals, 1);
    expect(q.sessionNeedsLogin, false);
    expect(q.key, 'old-fixture');
    expect(saves, 0);
    clock = clock.add(const Duration(minutes: 6));
    await q.refreshSessionIfNeeded();
    expect(renewals, 2);
    q.dispose();
  });

  test(
      'explicit expiry joining failed background renewal still requests reauthentication',
      () async {
    final gate = Completer<void>();
    messenger.setMockMethodCallHandler(
        channel,
        (c) async => c.method == 'readSession'
            ? session({'refresh_key': 'fixture'})
            : null);
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
        await gate.future;
        h.resolve(Response(requestOptions: o, data: {'code': 1000}));
      }));
    final q = QqMusic(channel: channel, dio: dio, now: () => epoch);
    await q.restore();
    final proactive = q.refreshSessionIfNeeded(force: true);
    await Future<void>.delayed(Duration.zero);
    final reactive = q.recoverSession();
    gate.complete();
    expect(await proactive, false);
    expect(await reactive, false);
    expect(q.sessionNeedsLogin, true);
    expect(q.loggedIn, true);
    q.dispose();
  });

  for (final mismatch in [false, true]) {
    test(
        'renewal ${mismatch ? 'wrong account' : 'logout race'} cannot replace current encrypted credentials',
        () async {
      var saves = 0;
      final gate = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (c) async {
        if (c.method == 'readSession')
          return session({'refresh_key': 'fixture'});
        if (c.method == 'saveSession') saves++;
        return null;
      });
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
          await gate.future;
          h.resolve(Response(
              requestOptions: o,
              data: response(issued(id: mismatch ? 456 : 123))));
        }));
      final q = QqMusic(channel: channel, dio: dio, now: () => epoch);
      await q.restore();
      final pending = q.refreshSessionIfNeeded(force: true);
      await Future<void>.delayed(Duration.zero);
      if (!mismatch) await q.logout();
      gate.complete();
      expect(await pending, false);
      expect(saves, 0);
      expect(q.loggedIn, mismatch);
      q.dispose();
    });
  }

  test(
      'legacy key-only compatibility refresh is validated without inventing renewal tokens',
      () async {
    String? saved;
    messenger.setMockMethodCallHandler(channel, (c) async {
      if (c.method == 'readSession') return 'uin=123; qqmusic_key=old-fixture';
      if (c.method == 'saveSession') saved = c.arguments as String;
      return null;
    });
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.method == 'GET') {
          h.resolve(Response(requestOptions: o, data: profiles));
          return;
        }
        expect(o.data['req_0']['module'], 'QQConnectLogin.LoginServer');
        expect(o.data['req_0']['param']['musicid'], 123);
        h.resolve(Response(
            requestOptions: o,
            data: response({'musicid': 123, 'musickey': 'new-fixture'})));
      }));
    final q = QqMusic(channel: channel, dio: dio, now: () => epoch);
    expect(await q.refreshSessionIfNeeded(force: true), true);
    expect(q.key, 'new-fixture');
    expect(q.automaticRenewalAvailable, true);
    expect(q.hasVerifiedRenewal, true);
    expect(jsonDecode(saved!)['refresh'].containsKey('refresh_token'), false);
    expect(jsonDecode(saved!)['refresh']['renewalMethod'], 'musicKey');
    expect(jsonDecode(saved!)['refresh']['lastRenewalKeyChanged'], 1);
    q.dispose();
  });

  test('WeChat cookie aliases normalize to canonical renewable metadata', () {
    final parsed = QqSessionMetadata.read({
      'wxopenid': 'open-fixture',
      'wxunionid': 'union-fixture',
      'wxrefresh_token': 'refresh-fixture'
    });
    expect(parsed['openid'], 'open-fixture');
    expect(parsed['refresh_token'], 'refresh-fixture');
    expect(QqSessionMetadata.renewable(parsed), true);
    expect(QqSessionMetadata.renewable({'refresh_key': 0}), false);
  });

  test(
      'server-rejected renewal requires explicit authentication rather than automatic polling',
      () async {
    var clock = epoch, calls = 0;
    messenger.setMockMethodCallHandler(
        channel,
        (c) async => c.method == 'readSession'
            ? session({'refresh_key': 'fixture'})
            : null);
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        calls++;
        h.resolve(Response(requestOptions: o, data: {'code': 1000}));
      }));
    final q = QqMusic(channel: channel, dio: dio, now: () => clock);
    await q.restore();
    expect(await q.recoverSession(), false);
    clock = epoch.add(const Duration(hours: 1));
    expect(await q.refreshSessionIfNeeded(), false);
    expect(calls, 1);
    expect(q.sessionNeedsLogin, true);
    q.dispose();
  });

  test('background work waits until the key is due, then persists renewal',
      () async {
    var clock = epoch;
    var exchanges = 0, saves = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'readSession') {
        return session(QqSessionMetadata.issued(issued(), epoch));
      }
      if (call.method == 'saveSession') saves++;
      return null;
    });
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        if (options.method == 'GET') {
          handler.resolve(Response(requestOptions: options, data: profiles));
          return;
        }
        exchanges++;
        handler.resolve(Response(
            requestOptions: options,
            data: response({
              ...issued(),
              'musickeyCreateTime': clock.millisecondsSinceEpoch ~/ 1000,
            })));
      }));
    final qq = QqMusic(
        channel: channel, dio: dio, manageLifecycle: false, now: () => clock);
    addTearDown(qq.dispose);
    expect(await qq.shouldRetryBackgroundRenewal(), false);
    expect(exchanges, 0);
    clock = epoch.add(const Duration(minutes: 31));
    expect(await qq.shouldRetryBackgroundRenewal(), false);
    expect(exchanges, 1);
    expect(saves, 1);
    expect(qq.hasVerifiedRenewal, true);
  });

  for (final networkFailure in [true, false]) {
    test(
        'background retry after ${networkFailure ? 'offline' : 'QQ rejection'}',
        () async {
      messenger.setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'readSession'
              ? session(QqSessionMetadata.issued(issued(), epoch))
              : null);
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
          if (networkFailure) {
            handler.reject(DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError));
            return;
          }
          handler
              .resolve(Response(requestOptions: options, data: {'code': 1000}));
        }));
      final qq = QqMusic(
          channel: channel,
          dio: dio,
          manageLifecycle: false,
          now: () => epoch.add(const Duration(minutes: 31)));
      addTearDown(qq.dispose);
      expect(await qq.shouldRetryBackgroundRenewal(), networkFailure);
      expect(qq.key, 'old-fixture');
    });
  }
}
