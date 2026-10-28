// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'package:bujuan/common/github_updates.dart';
import 'package:bujuan/pages/setting/app_update_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

class Updates extends GitHubUpdates {
  Updates(this.read);
  final Future<GitHubRelease?> Function() read;
  int calls = 0;
  @override
  Future<GitHubRelease?> latest({bool tv = false}) {
    calls++;
    return read();
  }
}

GitHubRelease published(int build) => GitHubRelease(
    AppReleaseVersion('2.0.8', build),
    Uri.parse('${GitHubUpdates.releasesPage}/tag/v2.0.8.$build'),
    '更新说明');

Future<void> openSettings(WidgetTester tester, Updates updates) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Scaffold(body: AppUpdateTile(updates: updates)),
          bottomNavigationBar: const SizedBox(
              height: 80, child: Center(child: Text('迷你播放器'))))));
  await tester.pumpAndSettle();
  expect(find.text('2.0.8 (2120)'), findsOneWidget);
  await tester.tap(find.text('检测更新'));
  await tester.pump();
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
        appName: 'BuYu',
        packageName: 'com.sixbugs.bujuan',
        version: '2.0.8',
        buildNumber: '2120',
        buildSignature: '');
  });

  testWidgets('latest status replaces the version without opening a dialog',
      (tester) async {
    await openSettings(tester, Updates(() async => published(2120)));
    await tester.pumpAndSettle();
    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(
        find.descendant(
            of: find.byWidget(tile.trailing!), matching: find.text('已是最新版本')),
        findsOneWidget);
    expect(find.text('2.0.8 (2120)'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('newer build opens the exact current-repository release URL',
      (tester) async {
    String? launched;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'), (call) async {
      if (call.method == 'launch') launched = call.arguments['url'] as String;
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/url_launcher'), null));
    await openSettings(tester, Updates(() async => published(2121)));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('发现新版本，前往更新'));
    await tester.pumpAndSettle();
    expect(launched, '${GitHubUpdates.releasesPage}/tag/v2.0.8.2121');
  });

  testWidgets('network failure is inline and tapping the row retries',
      (tester) async {
    var offline = true;
    final updates = Updates(() async {
      if (offline) throw StateError('offline');
      return published(2120);
    });
    await openSettings(tester, updates);
    await tester.pumpAndSettle();
    expect(find.text('检查失败，点击重试'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    offline = false;
    await tester.tap(find.text('检测更新'));
    await tester.pumpAndSettle();
    expect(find.text('已是最新版本'), findsOneWidget);
    expect(updates.calls, 2);
  });

  testWidgets('no compatible APK produces an inline result', (tester) async {
    await openSettings(tester, Updates(() async => null));
    await tester.pumpAndSettle();
    expect(find.text('暂无可用更新'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('stalled checks show progress then timeout without a dialog',
      (tester) async {
    final pending = Completer<GitHubRelease?>();
    await openSettings(tester, Updates(() => pending.future));
    expect(find.text('检查中…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();
    expect(find.text('检查失败，点击重试'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    pending.complete(null);
  });

  testWidgets('repeated taps do not duplicate requests and leaving is safe',
      (tester) async {
    final pending = Completer<GitHubRelease?>();
    final updates = Updates(() => pending.future);
    await openSettings(tester, updates);
    await tester.tap(find.text('检测更新'));
    await tester.pump();
    expect(updates.calls, 1);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete(published(2120));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed browser launch reports inline and can be retried',
      (tester) async {
    var allowBrowser = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        (_) async => allowBrowser);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/url_launcher'), null));
    await openSettings(tester, Updates(() async => published(2121)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发现新版本，前往更新'));
    await tester.pumpAndSettle();
    expect(find.text('无法打开发布页，重试'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    allowBrowser = true;
    await tester.tap(find.text('无法打开发布页，重试'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
