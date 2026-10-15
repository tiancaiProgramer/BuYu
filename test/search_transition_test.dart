import 'dart:io';
import 'dart:ui' as ui;
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/common/display_mode.dart';
import 'package:bujuan/common/netease_api/src/dio_ext.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/pages/search/search_view.dart';
import 'package:bujuan/widget/request_widget/request_view.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:get/get.dart' hide Response;
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'phone_rotation_test.dart' show OfflineHome;
import 'playback_regression_test.dart' show FakePlayer;

void main() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    for (final dark in [false, true]) {
      testWidgets('search covers the previous route at $size, dark=$dark',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final resources = await tester.runAsync(() async {
          final dir = await Directory.systemTemp.createTemp('bujuan-search');
          Hive.init(dir.path);
          final box = await Hive.openBox('search-transition');
          final handler = BujuanAudioHandler(
              player: FakePlayer(), box: box, restoreQueue: false);
          return (dir, box, handler);
        });
        final (dir, box, handler) = resources!;
        GetIt.instance.registerSingleton<Box>(box);
        GetIt.instance.registerSingleton<BujuanAudioHandler>(handler);
        GetIt.instance
            .registerSingleton<ZoomDrawerController>(ZoomDrawerController());
        final offline = InterceptorsWrapper(onRequest: (options, handler) {
          handler.resolve(Response(requestOptions: options, data: {
            'code': 200,
            'result': {'hots': []}
          }));
        });
        Https.dio.interceptors.add(offline);
        final navigator = GlobalKey<NavigatorState>();
        final surface = GlobalKey();
        final theme = dark ? AppTheme.dark : AppTheme.light;
        Home? home;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          Https.dio.interceptors.remove(offline);
          Get.reset();
          await GetIt.instance.reset();
          await tester.runAsync(() async {
            await handler.dispose();
            await box.close();
            await dir.delete(recursive: true);
          });
        });
        await tester.pumpWidget(ScreenUtilInit(
            designSize: DisplayMode.designSize(size),
            builder: (_, __) {
              home ??= Get.put<Home>(OfflineHome());
              // Force a contrasting old page to expose transparent areas even
              // when the app normally uses the same colour for both routes.
              home!.background.value = 'custom-wallpaper';
              return GetMaterialApp(
                  theme: theme,
                  home: RepaintBoundary(
                      key: surface,
                      child: Navigator(
                          key: navigator,
                          onGenerateRoute: (_) => MaterialPageRoute(
                              builder: (_) => const ColoredBox(
                                  color: Color(0xffff00ff))))));
            }));
        await tester.pump();
        navigator.currentState!
            .push(MaterialPageRoute(builder: (_) => const SearchView()));
        await tester.pump();
        // Measure while both routes are still being painted.
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(find.byWidgetPredicate((widget) => widget is RequestWidget),
            findsOneWidget);
        final point = Offset(size.width - 10, size.height * .75);
        Future<Color> pixel() async {
          return (await tester.runAsync(() async {
            final image = await (surface.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final data =
                await image.toByteData(format: ui.ImageByteFormat.rawRgba);
            final offset =
                (point.dy.floor() * image.width + point.dx.floor()) * 4;
            final bytes = data!.buffer.asUint8List();
            final colour = Color.fromARGB(bytes[offset + 3], bytes[offset],
                bytes[offset + 1], bytes[offset + 2]);
            image.dispose();
            return colour;
          }))!;
        }

        // Dark mode deliberately fades the whole incoming route. Account for
        // that animation while ensuring SearchView itself paints a solid page.
        final fades = find.ancestor(
            of: find.byType(SearchView), matching: find.byType(FadeTransition));
        final opacity = tester
            .widgetList<FadeTransition>(fades)
            .fold(1.0, (value, fade) => value * fade.opacity.value);
        final expected = Color.alphaBlend(
            theme.scaffoldBackgroundColor.withOpacity(opacity),
            const Color(0xffff00ff));
        final actual = await pixel();
        expect(actual.red, closeTo(expected.red, 1));
        expect(actual.green, closeTo(expected.green, 1));
        expect(actual.blue, closeTo(expected.blue, 1));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.byType(TextField));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.testTextInput.isVisible, isTrue);
        expect(await pixel(), theme.scaffoldBackgroundColor);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
