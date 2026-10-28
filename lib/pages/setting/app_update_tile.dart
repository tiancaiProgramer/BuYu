// Community maintenance and new features: tiancaiProgramer.
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../common/display_mode.dart';
import '../../common/github_updates.dart';

/// Shows update results where the installed version is normally displayed.
class AppUpdateTile extends StatefulWidget {
  const AppUpdateTile({super.key, this.updates, this.titleStyle});
  final GitHubUpdates? updates;
  final TextStyle? titleStyle;

  @override
  State<AppUpdateTile> createState() => _AppUpdateTileState();
}

class _AppUpdateTileState extends State<AppUpdateTile> {
  PackageInfo? _package;
  bool _checking = false;
  String? _status;
  GitHubRelease? _available;

  @override
  void initState() {
    super.initState();
    _readPackage().then<void>((_) {}, onError: (Object _) {});
  }

  Future<PackageInfo> _readPackage() async {
    final info =
        await PackageInfo.fromPlatform().timeout(const Duration(seconds: 5));
    if (mounted) setState(() => _package = info);
    return info;
  }

  Future<void> _open(Uri page) async {
    try {
      if (await launchUrl(page, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (mounted) setState(() => _status = '无法打开发布页，重试');
  }

  Future<void> _check() async {
    if (_checking) return;
    if (const bool.fromEnvironment('BUYU_COEXIST')) {
      setState(() => _status = '请使用共存测试包更新');
      return;
    }
    setState(() {
      _checking = true;
      _status = '检查中…';
      _available = null;
    });
    try {
      final installed = _package ?? await _readPackage();
      final latest = await (widget.updates ?? GitHubUpdates())
          .latest(tv: DisplayMode.isTv)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (latest == null) {
        setState(() => _status = '暂无可用更新');
        return;
      }
      final current = AppReleaseVersion(
          installed.version, int.tryParse(installed.buildNumber) ?? 0);
      setState(() {
        if (latest.version.compareTo(current) > 0) {
          _available = latest;
          _status = '发现新版本，前往更新';
        } else {
          _status = '已是最新版本';
        }
      });
    } catch (_) {
      if (mounted) setState(() => _status = '检查失败，点击重试');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final version = _package == null
        ? '…'
        : '${_package!.version} (${_package!.buildNumber})';
    final result = Text(_status ?? version,
        key: const ValueKey('github-update-status'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: const TextStyle(fontSize: 13));
    return ListTile(
      title: Text('检测更新', style: widget.titleStyle),
      subtitle: const Text('tiancaiProgramer / BuYu'),
      trailing: Tooltip(
        message: _available == null
            ? '当前版本：$version'
            : '最新版本：${_available!.version.label}',
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: _checking
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Flexible(child: result),
                ])
              : _available == null
                  ? result
                  : TextButton(
                      onPressed: () => _open(_available!.page), child: result),
        ),
      ),
      onTap: _checking ? null : _check,
    );
  }
}
