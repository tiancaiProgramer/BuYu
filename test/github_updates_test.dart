import 'package:bujuan/common/github_updates.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> release(String tag, List<String> names,
        {bool draft = false, bool preview = false}) =>
    {
      'tag_name': tag,
      'draft': draft,
      'prerelease': preview,
      'html_url': '${GitHubUpdates.releasesPage}/tag/$tag',
      'body': '测试发布说明',
      'assets': [
        for (final name in names) {'name': name}
      ],
    };

void main() {
  test('versions compare numeric components and same-version build numbers',
      () {
    expect(
        AppReleaseVersion('2.0.10', 1)
            .compareTo(AppReleaseVersion('2.0.9', 999)),
        greaterThan(0));
    expect(
        AppReleaseVersion('2.1.0', 1)
            .compareTo(AppReleaseVersion('2.0.99', 999)),
        greaterThan(0));
    expect(
        AppReleaseVersion('2.0.6', 2053)
            .compareTo(AppReleaseVersion('2.0.6', 2052)),
        greaterThan(0));
    expect(
        AppReleaseVersion('2.0.5', 9999)
            .compareTo(AppReleaseVersion('2.0.6', 2052)),
        lessThan(0));
    expect(
        AppReleaseVersion.fromTag('v2.0.5-wide-tv-preview.2040')!.build, 2040);
    expect(
        AppReleaseVersion.fromTag('v2.0.6-fixed.2052')!.label, '2.0.6 (2052)');
    expect(AppReleaseVersion.fromTag('v2.0.7')!.version, '2.0.7');
    expect(AppReleaseVersion.fromTag('v2.0.7')!.build, 0);
    expect(AppReleaseVersion.fromTag('invalid'), isNull);
  });

  test(
      'GitHub updates use the user repository and select the newest usable release',
      () async {
    final client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.uri.host, 'api.github.com');
      expect(options.uri.path, '/repos/tiancaiProgramer/BuYu/releases');
      handler.resolve(Response(requestOptions: options, data: [
        release('v2.0.5-fixed.2039', ['bujuan-2.0.5-fixed.apk']),
        release('v2.0.6-preview.2053', ['bujuan-mobile-arm64.apk'],
            preview: true),
        release('v2.0.6-tv.2090', ['bujuan-tv-arm64.apk']),
        release('v2.0.8-fixed.3000', ['bujuan-arm64.apk'], draft: true),
        release('v2.0.9-fixed.4000', ['source.zip']),
      ]));
    }));
    final updates = GitHubUpdates(client: client);
    expect((await updates.latest())!.version.build, 2053);
    expect((await updates.latest(tv: true))!.version.build, 2090);
    client.close();
  });

  test('renamed BuYu repository release links are accepted', () async {
    final client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(requestOptions: options, data: [
        {
          ...release('v2.0.7.2071', ['BuYu-2.0.7-2071-arm64.apk']),
          'html_url':
              'https://github.com/tiancaiProgramer/BuYu/releases/tag/v2.0.7.2071'
        },
      ]));
    }));
    final result = await GitHubUpdates(client: client).latest();
    expect(result?.version.label, '2.0.7 (2071)');
    expect(
        result?.page.path, '/tiancaiProgramer/BuYu/releases/tag/v2.0.7.2071');
    client.close();
  });

  test('untrusted release links and releases without APKs are ignored',
      () async {
    final client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(requestOptions: options, data: [
        {
          ...release('v2.0.6-fixed.2053', ['mobile.apk']),
          'html_url': 'https://example.test/download'
        },
        release('v2.0.7', ['source.zip']),
      ]));
    }));
    expect(await GitHubUpdates(client: client).latest(), isNull);
    client.close();
  });

  test('invalid API responses are errors instead of claiming no updates',
      () async {
    final client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(
          requestOptions: options, data: {'message': 'API rate limit'}));
    }));
    await expectLater(
        GitHubUpdates(client: client).latest(), throwsFormatException);
    client.close();
  });
}
