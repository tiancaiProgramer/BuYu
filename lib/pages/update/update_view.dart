import 'package:auto_route/auto_route.dart';
import 'package:bujuan/common/constants/icon.dart';
import 'package:bujuan/common/github_updates.dart';
import 'package:bujuan/widget/app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateView extends StatelessWidget {
  const UpdateView({super.key});

  @override
  Widget build(BuildContext context) {
    final params = context.routeData.queryParams;
    final target = Uri.tryParse(
        params.getString('downloadUrl', GitHubUpdates.latestReleasePage));
    final page = target != null &&
            (target.toString() == GitHubUpdates.releasesPage ||
                target.toString() == GitHubUpdates.latestReleasePage ||
                target
                    .toString()
                    .startsWith('${GitHubUpdates.releasesPage}/tag/'))
        ? target
        : Uri.parse(GitHubUpdates.latestReleasePage);
    return Scaffold(
      appBar: MyAppBar(title: const Text('发现新版本')),
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              SvgPicture.asset(AppIcons.update,
                  height: MediaQuery.sizeOf(context).width >
                          MediaQuery.sizeOf(context).height
                      ? 100
                      : 180,
                  fit: BoxFit.contain),
              const SizedBox(height: 16),
              Text('当前版本：${params.getString('oldVersion', '')}',
                  style: const TextStyle(fontSize: 15)),
              const SizedBox(height: 6),
              Text('最新版本：${params.getString('version', '')}',
                  style: TextStyle(
                      fontSize: 18, color: Theme.of(context).primaryColor)),
              const SizedBox(height: 16),
              Text(params.getString('versionInfo', ''),
                  style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 16),
              const Text('更新来源：tiancaiProgramer / BuYu',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              ElevatedButton(
                  onPressed: () async {
                    try {
                      if (await launchUrl(page,
                          mode: LaunchMode.externalApplication)) {
                        return;
                      }
                    } catch (_) {}
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('无法打开 GitHub，请稍后重试')));
                    }
                  },
                  child: const Text('前往 GitHub 更新')),
            ])),
      ))),
    );
  }
}
