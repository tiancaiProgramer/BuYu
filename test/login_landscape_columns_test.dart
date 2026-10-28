// Community maintenance and new features: tiancaiProgramer.
import 'package:bujuan/common/music/music_source.dart';
import 'package:bujuan/common/music/qq_music.dart';
import 'package:bujuan/common/music/qq_qr_login.dart';
import 'package:bujuan/common/netease_api/src/api/login/api.dart';
import 'package:bujuan/common/netease_api/src/api/login/bean.dart';
import 'package:bujuan/pages/login/login.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:qr_flutter/qr_flutter.dart';

class _Api with ApiLogin {
  @override
  Future<QrCodeLoginKey> loginQrCodeKey() async => QrCodeLoginKey()
    ..code = 200
    ..unikey = 'layout-test';
}

class _Qr extends QqQrLogin {
  @override
  Future<Uint8List> create() async =>
      (await rootBundle.load('assets/images/logo.png')).buffer.asUint8List();
  @override
  Future<String?> check(QqMusic music) async => null;
}

void main() {
  for (final size in [
    const Size(640, 300),
    const Size(844, 390),
    const Size(1280, 800)
  ]) {
    for (final source in MusicSource.values) {
      testWidgets(
          '$source QR is fully visible between selector and actions at $size',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        tester.view.padding =
            const FakeViewPadding(right: 36, top: 20, bottom: 16);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        await tester.pumpWidget(MaterialApp(
            home: LoginViewPage(
                api: _Api(),
                initialSource: source,
                statusReader: (_) => false,
                qqQrFactory: _Qr.new)));
        await tester.pumpAndSettle();
        final platforms = tester
            .getRect(find.byKey(const ValueKey('login-landscape-platforms')));
        final qr =
            tester.getRect(find.byKey(const ValueKey('login-landscape-qr')));
        final actions = tester
            .getRect(find.byKey(const ValueKey('login-landscape-actions')));
        expect(platforms.right, lessThan(qr.left));
        expect(qr.right, lessThan(actions.left));
        expect(qr.top, greaterThanOrEqualTo(20));
        expect(qr.bottom, lessThanOrEqualTo(size.height - 16));
        expect(qr.width, closeTo(qr.height, .01));
        expect(qr.width, greaterThan(160));
        if (source == MusicSource.netease) {
          expect(find.byType(QrImageView), findsOneWidget);
        } else {
          expect(find.byType(Image), findsOneWidget);
        }
        for (final text in ['刷新二维码', '关闭二维码', '官方网页登录']) {
          final rect = tester.getRect(find.text(text));
          expect(rect.left, greaterThanOrEqualTo(actions.left));
          expect(rect.bottom, lessThanOrEqualTo(size.height - 16),
              reason: '$text must be visible without scrolling');
        }
        await tester.tap(find.text('关闭二维码'));
        await tester.pumpAndSettle();
        expect(find.text('二维码登录'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await GetIt.I.reset();
      });
    }
  }
}
