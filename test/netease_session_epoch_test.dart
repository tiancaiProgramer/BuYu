// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:bujuan/common/netease_api/src/netease_api.dart';
import 'package:bujuan/common/netease_api/src/api/login/bean.dart';
import 'package:bujuan/common/netease_api/src/dio_ext.dart';
import 'package:bujuan/common/netease_api/src/netease_handler.dart';
import 'package:dio/dio.dart';
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

class _HeldResponse implements HttpClientAdapter {
  final requested = Completer<void>();
  final response = Completer<ResponseBody>();
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    requested.complete();
    return response.future;
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
      'a real account API response arriving after logout cannot restore saved login',
      () async {
    final root = await Directory.systemTemp.createTemp('buyu-session-epoch');
    await NeteaseMusicApi.init(provider: _Paths(root));
    final api = NeteaseMusicApi(), adapter = _HeldResponse();
    final previous = Https.dio.httpClientAdapter;
    Https.dio.httpClientAdapter = adapter;
    try {
      final account = NeteaseAccountInfoWrap.fromJson({
        'code': 200,
        'profile': {'userId': 123, 'nickname': '测试账号'}
      });
      await api.usc.onLogined(account);
      await NeteaseMusicApi.cookieManager.cookieJar.saveFromResponse(
          Uri.parse(HOST), [Cookie('MUSIC_U', 'fixture-only')]);
      final pending = api.loginAccountInfo();
      await adapter.requested.future;
      await api.usc.onLogout();
      adapter.response.complete(
          ResponseBody.fromString(jsonEncode(account.toJson()), 200, headers: {
        Headers.contentTypeHeader: ['application/json']
      }));
      expect((await pending).code, 200);
      expect(api.usc.isLogined, false);
      expect(api.usc.accountInfo, isNull);
      expect(await loadCookies(), isEmpty);
      expect(
          jsonDecode(
              await File('${root.path}/data/_accountInfo.json').readAsString()),
          isNull);
    } finally {
      Https.dio.httpClientAdapter = previous;
      await root.delete(recursive: true);
    }
  });
}
