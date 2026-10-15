import 'dart:io';
import 'package:bujuan/widget/adaptive_wallpaper.dart';
import 'package:bujuan/widget/simple_extended_image.dart';
import 'package:bujuan/widget/splash_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final splash in [false, true]) {
    testWidgets(
        '${splash ? 'startup' : 'wallpaper'} switches independent images and falls back after clearing',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final files = await tester.runAsync(() async {
        final directory =
            await Directory.systemTemp.createTemp('bujuan-rotation-image');
        final bytes = await rootBundle.load('assets/images/logo.png');
        final portrait = await File('${directory.path}/portrait.png')
            .writeAsBytes(bytes.buffer.asUint8List());
        final landscape = await File('${directory.path}/landscape.png')
            .writeAsBytes(bytes.buffer.asUint8List());
        return (directory, portrait, landscape);
      });
      final (directory, portrait, landscape) = files!;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() => directory.delete(recursive: true));
      });
      Future<void> mount(Size size, {bool separate = true}) async {
        tester.view.physicalSize = size;
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: splash
                    ? SplashArtwork(
                        background: portrait.path,
                        landscapeBackground: separate ? landscape.path : '')
                    : AdaptiveWallpaper(
                        portrait: portrait.path,
                        landscape: separate ? landscape.path : '',
                        portraitBlur: 3))));
        await tester.pump();
        final wide = size.width > size.height;
        final expected = wide && separate ? landscape.path : portrait.path;
        if (splash && !wide) {
          final image = tester.widget<SimpleExtendedImage>(find.byType(SimpleExtendedImage));
          expect(image.url, expected);
          expect(image.fit, BoxFit.cover);
        } else {
          final images = tester.widgetList<Image>(find.byType(Image)).toList();
          for (final image in images) {
            final provider = image.image is ResizeImage ? (image.image as ResizeImage).imageProvider : image.image;
            expect((provider as FileImage).file.path, expected);
          }
          expect(images.any((image) => image.fit == BoxFit.cover), isTrue);
          expect(images.any((image) => image.fit == BoxFit.contain), wide && !separate);
          expect(tester.getSize(find.byType(AdaptiveWallpaper)).width, size.width);
          if (!splash) expect(find.byType(ImageFiltered), findsNWidgets(wide ? (separate ? 0 : 2) : 1));
        }
        expect(tester.takeException(), isNull);
      }

      await mount(const Size(390, 844));
      await mount(const Size(844, 390));
      await mount(const Size(390, 844));
      await mount(const Size(844, 390), separate: false);
    });
  }
}
