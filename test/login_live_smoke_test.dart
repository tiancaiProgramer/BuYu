// Community maintenance and new features: tiancaiProgramer.
import 'dart:io';

import 'package:bujuan/common/netease_api/src/netease_api.dart';
import 'package:bujuan/common/netease_api/src/dio_ext.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

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

class _Network extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('official QR endpoints issue a key and report waiting for a scan',
      () async {
    final directory = await Directory.systemTemp.createTemp('bujuan-live-qr');
    try {
      await HttpOverrides.runWithHttpOverrides(() async {
        await NeteaseMusicApi.init(provider: _Paths(directory));
        final api = NeteaseMusicApi();
        await api.usc.init();
        final key =
            await api.loginQrCodeKey().timeout(const Duration(seconds: 15));
        expect(key.code, 200);
        expect(key.unikey, isNotEmpty);
        expect(Uri.parse(api.loginQrCodeUrl(key.unikey)).host, 'music.163.com');
        final status = await api
            .loginQrCodeCheck(key.unikey)
            .timeout(const Duration(seconds: 15));
        expect(status.code, 801);
      }, _Network());
    } finally {
      Https.dio.interceptors.clear();
      await directory.delete(recursive: true);
    }
  }, skip: !const bool.fromEnvironment('BUJUAN_LIVE_LOGIN'));

  test(
      'current phone and email endpoints return validation errors for empty input',
      () async {
    final directory = await Directory.systemTemp.createTemp('buyu-live-auth');
    try {
      await HttpOverrides.runWithHttpOverrides(() async {
        await NeteaseMusicApi.init(provider: _Paths(directory));
        final api = NeteaseMusicApi();
        for (final request in [
          api.loginCellPhoneCaptchaDioMetaData('', ''),
          api.loginEmailDioMetaData('', ''),
        ]) {
          Response? response;
          try {
            response = await Https.dioProxy
                .postUri(request)
                .timeout(const Duration(seconds: 15));
          } on DioException catch (error) {
            response = error.response;
          }
          expect(response?.data, isA<Map>());
          final code = response!.data['code'];
          expect(code, isA<num>());
          expect(code, isNot(404));
          expect(code, isNot(200));
        }
      }, _Network());
    } finally {
      Https.dio.interceptors.clear();
      await directory.delete(recursive: true);
    }
  }, skip: !const bool.fromEnvironment('BUJUAN_LIVE_LOGIN'));
}
