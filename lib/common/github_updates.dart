// Community maintenance and new features: tiancaiProgramer.
import 'dart:convert';
import 'package:dio/dio.dart';

class AppReleaseVersion implements Comparable<AppReleaseVersion> {
  AppReleaseVersion(this.version, this.build);
  final String version;
  final int build;

  static AppReleaseVersion? fromTag(String tag) {
    final match = RegExp(r'^v?(\d+\.\d+\.\d+)(.*)$').firstMatch(tag);
    if (match == null) return null;
    final suffix = RegExp(r'[.+](\d+)$').firstMatch(match.group(2)!);
    return AppReleaseVersion(
        match.group(1)!, int.tryParse(suffix?.group(1) ?? '') ?? 0);
  }

  String get label => build > 0 ? '$version ($build)' : version;

  @override
  int compareTo(AppReleaseVersion other) {
    final own = version.split('.').map(int.parse).toList();
    final theirs = other.version.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      final comparison = own[i].compareTo(theirs[i]);
      if (comparison != 0) return comparison;
    }
    return build.compareTo(other.build);
  }
}

class GitHubRelease {
  GitHubRelease(this.version, this.page, this.notes);
  final AppReleaseVersion version;
  final Uri page;
  final String notes;
}

class GitHubUpdates {
  GitHubUpdates({Dio? client})
      : client = client ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 12),
                headers: {
                  'Accept': 'application/vnd.github+json',
                  'User-Agent': 'BuYu-Community-Update'
                }));
  final Dio client;
  static const repository = 'https://github.com/tiancaiProgramer/BuYu';
  static const releasesPage = '$repository/releases';
  static const latestReleasePage = '$releasesPage/latest';
  static const endpoint =
      'https://api.github.com/repos/tiancaiProgramer/BuYu/releases';

  Future<GitHubRelease?> latest({bool tv = false}) async {
    final response =
        await client.get<dynamic>(endpoint, queryParameters: {'per_page': 30});
    final data = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    if (data is! List) throw const FormatException('Invalid release list');
    final available = <GitHubRelease>[];
    for (final item in data) {
      if (item is! Map || item['draft'] == true) continue;
      final version =
          AppReleaseVersion.fromTag(item['tag_name']?.toString() ?? '');
      final page = Uri.tryParse(item['html_url']?.toString() ?? '');
      if (version == null ||
          page == null ||
          !page.toString().startsWith('$releasesPage/tag/')) continue;
      final assets = item['assets'];
      if (assets is! List) continue;
      final hasInstaller = assets.any((asset) {
        if (asset is! Map) return false;
        final name = asset['name']?.toString().toLowerCase() ?? '';
        final isTv = RegExp(r'(^|[-_.])tv([-_.]|$)').hasMatch(name);
        return name.endsWith('.apk') && isTv == tv;
      });
      if (hasInstaller) {
        available.add(GitHubRelease(
            version, page, item['body']?.toString() ?? '请在 GitHub 发布页查看更新说明。'));
      }
    }
    available.sort((a, b) => b.version.compareTo(a.version));
    return available.isEmpty ? null : available.first;
  }
}
