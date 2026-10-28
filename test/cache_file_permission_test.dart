// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'package:auto_route/auto_route.dart';
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/common/display_mode.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/pages/local/cache_directory.dart';
import 'package:bujuan/pages/local/local_controller.dart';
import 'package:bujuan/pages/local/local_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'download_preferences_test.dart' show MemoryBox;
import 'landscape_pages_test.dart' show OfflineLocal;
import 'phone_rotation_test.dart' show OfflineHome;
import 'playback_regression_test.dart' show FakePlayer;

class _Router extends Fake implements StackRouter {
  final routes = <String>[];
  @override
  Future<T?> push<T extends Object?>(PageRouteInfo route,
      {OnNavigationFailure? onFailure}) async {
    routes.add(route.routeName);
    return null;
  }
}

class _Permissions {
  int sdk = 36;
  bool granted = false;
  Completer<int>? sdkResult;
  final checks = <int>[];
  final requests = <int>[];
  Future<void> Function()? onRequest;
  final router = _Router();
}

Future<_Permissions> _open(WidgetTester tester, Size size,
    {bool granted = false, int sdk = 36}) async {
  final state = _Permissions()
    ..sdk = sdk
    ..granted = granted;
  const permissionChannel =
      MethodChannel('flutter.baseflow.com/permissions/methods');
  const sdkChannel = MethodChannel('bujuan/downloads');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      sdkChannel,
      (call) async => call.method == 'sdk'
          ? await (state.sdkResult?.future ?? Future.value(state.sdk))
          : null);
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(permissionChannel, (call) async {
    if (call.method == 'checkPermissionStatus') {
      state.checks.add(call.arguments as int);
      return state.granted ? 1 : 0;
    }
    if (call.method == 'requestPermissions') {
      final ids = List<int>.from(call.arguments as List);
      state.requests.addAll(ids);
      await state.onRequest?.call();
      // The flow must recheck settings, not trust a stale request result.
      return {for (final id in ids) id: 0};
    }
    return null;
  });
  final box = MemoryBox();
  final audio = (await tester.runAsync(() async => BujuanAudioHandler(
      player: FakePlayer(), box: box, restoreQueue: false)))!;
  GetIt.I.registerSingleton<Box>(box);
  GetIt.I.registerSingleton<BujuanAudioHandler>(audio);
  GetIt.I.registerSingleton<ZoomDrawerController>(ZoomDrawerController());
  GetIt.I.registerSingleton<OnAudioQuery>(OnAudioQuery());
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    Get.reset();
    await GetIt.I.reset();
    await tester.runAsync(audio.dispose);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    for (final channel in [permissionChannel, sdkChannel]) {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
  await tester.pumpWidget(ScreenUtilInit(
      designSize: DisplayMode.designSize(size),
      builder: (_, __) {
        if (!Get.isRegistered<Home>()) Get.put<Home>(OfflineHome());
        if (!Get.isRegistered<Local>()) {
          Get.put<Local>(OfflineLocal()..loading.value = false);
        }
        return GetMaterialApp(
            theme: AppTheme.light,
            home: StackRouterScope(
                controller: state.router,
                stateHash: 0,
                child: const LocalView()));
      }));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('网易云缓存歌曲'));
  return state;
}

void main() {
  test('stable and coexist cache paths resolve the same shared root', () {
    for (final package in [
      'com.sixbugs.bujuan',
      'com.sixbugs.bujuan.preview'
    ]) {
      expect(
          cacheStorageRoot('/storage/emulated/0/Android/data/$package/files'),
          '/storage/emulated/0');
      expect(
          cacheStorageRoot('/storage/ABCD-1234/Android/data/$package/files/'),
          '/storage/ABCD-1234');
    }
    expect(cacheStorageRoot('/data/user/0/com.sixbugs.bujuan/files'), isNull);
  });

  for (final size in [const Size(390, 844), const Size(640, 300)]) {
    testWidgets('cancel cache explanation never requests permission $size',
        (tester) async {
      final state = await _open(tester, size);
      await tester.tap(find.text('网易云缓存歌曲'));
      await tester.pumpAndSettle();
      expect(find.text('读取网易云缓存'), findsOneWidget);
      expect(find.textContaining('所有文件访问权限'), findsOneWidget);
      await tester.tap(find.text('暂不开启'));
      await tester.pumpAndSettle();
      expect(state.requests, isEmpty);
      expect(state.router.routes, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('denial offers retry and settings grant opens cache once $size',
        (tester) async {
      final state = await _open(tester, size);
      final sdkReady = state.sdkResult = Completer<int>();
      await tester.tap(find.text('网易云缓存歌曲'));
      await tester.tap(find.text('网易云缓存歌曲'));
      sdkReady.complete(state.sdk);
      state.sdkResult = null;
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('前往授权'));
      await tester.pumpAndSettle();
      expect(state.requests, [22]);
      expect(state.router.routes, isEmpty);
      expect(find.text('尚未开启文件访问权限，暂时无法读取网易云缓存'), findsOneWidget);
      await tester.tap(find.text('重新授权'));
      await tester.pumpAndSettle();
      final returned = Completer<void>();
      state.onRequest = () => returned.future;
      await tester.tap(find.text('前往授权'));
      await tester.pumpAndSettle();
      expect(state.router.routes, isEmpty);
      // Returning from Android settings after enabling access.
      state.granted = true;
      returned.complete();
      await tester.pumpAndSettle();
      expect(state.requests, [22, 22]);
      expect(state.router.routes, ['NeteaseCacheView']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('existing grant opens cache without a new request $size',
        (tester) async {
      final state = await _open(tester, size, granted: true);
      await tester.tap(find.text('网易云缓存歌曲'));
      await tester.pumpAndSettle();
      expect(state.router.routes, ['NeteaseCacheView']);
      expect(state.requests, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
    });
  }

  testWidgets('older Android requests storage instead of all-files access',
      (tester) async {
    final state = await _open(tester, const Size(390, 844), sdk: 29);
    state.onRequest = () async => state.granted = true;
    await tester.tap(find.text('网易云缓存歌曲'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('允许读取'));
    await tester.pumpAndSettle();
    expect(state.requests, [15]);
    expect(state.router.routes, ['NeteaseCacheView']);
  });

  testWidgets('permission settings failure shows a retry message',
      (tester) async {
    final state = await _open(tester, const Size(390, 844));
    state.onRequest = () async => throw PlatformException(code: 'SETTINGS');
    await tester.tap(find.text('网易云缓存歌曲'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('前往授权'));
    await tester.pumpAndSettle();
    expect(find.text('无法完成文件访问授权，请检查系统设置后重试'), findsOneWidget);
    expect(state.router.routes, isEmpty);
    await tester.tap(find.text('重新授权'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('settings grant survives rotation and opens only once',
      (tester) async {
    final state = await _open(tester, const Size(390, 844));
    final returned = Completer<void>();
    state.onRequest = () => returned.future;
    await tester.tap(find.text('网易云缓存歌曲'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('前往授权'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    state.granted = true;
    returned.complete();
    await tester.pumpAndSettle();
    expect(state.requests, [22]);
    expect(state.router.routes, ['NeteaseCacheView']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving while settings are open never navigates a disposed page',
      (tester) async {
    final state = await _open(tester, const Size(390, 844));
    final returned = Completer<void>();
    state.onRequest = () => returned.future;
    await tester.tap(find.text('网易云缓存歌曲'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('前往授权'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    state.granted = true;
    returned.complete();
    await tester.pumpAndSettle();
    expect(state.router.routes, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
