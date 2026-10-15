import 'dart:io';
import 'package:bujuan/pages/splash_page.dart';
import 'package:bujuan/widget/simple_extended_image.dart';
import 'package:bujuan/widget/splash_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(640, 300),
  ]) {
    testWidgets('startup artwork remains fully inside the screen at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (size.width > size.height) {
        tester.view.padding = const FakeViewPadding(left: 43);
        tester.view.viewPadding = const FakeViewPadding(left: 43);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
      }
      await tester
          .pumpWidget(const MaterialApp(home: Scaffold(body: SplashArtwork())));
      await tester.pumpAndSettle();
      final art = tester.getRect(find.byType(SvgPicture));
      expect(art.top, greaterThanOrEqualTo(0));
      expect(art.bottom, lessThanOrEqualTo(size.height));
      expect(art.right, lessThanOrEqualTo(size.width));
      if (size.width > size.height) {
        expect(art.left, greaterThanOrEqualTo(43));
        expect(art.center.dx, closeTo(43 + (size.width - 43) / 2, .01));
        expect(tester.widget<SvgPicture>(find.byType(SvgPicture)).fit,
            BoxFit.contain);
      } else {
        expect(art.width, closeTo(size.width / 1.8, .01));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('custom portrait wallpaper fits rather than crops in landscape',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [const Size(390, 844), const Size(844, 390)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: SplashArtwork(background: 'test-wallpaper'))));
      if (size.width > size.height) {
        final images = tester.widgetList<Image>(find.byType(Image));
        expect(images.any((image) => image.fit == BoxFit.contain), isTrue);
        expect(images.any((image) => image.fit == BoxFit.cover), isTrue);
        expect(find.byType(ImageFiltered), findsOneWidget);
      } else {
        final image = tester.widget<SimpleExtendedImage>(find.byType(SimpleExtendedImage));
        expect(image.fit, BoxFit.cover);
        expect(image.width, size.width);
        expect(image.height, size.height);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('leaving the startup page cancels its pending navigation',
      (tester) async {
    final resources = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('bujuan-splash');
      Hive.init(dir.path);
      return (dir, await Hive.openBox('startup'));
    });
    final (dir, box) = resources!;
    GetIt.instance.registerSingleton<Box>(box);
    await tester.pumpWidget(const MaterialApp(home: SplashPage()));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: Text('home')));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('home'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await GetIt.instance.reset();
    await tester.runAsync(() async {
      await box.close();
      await dir.delete(recursive: true);
    });
  });
}
