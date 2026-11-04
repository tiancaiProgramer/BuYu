// Community maintenance and new features: tiancaiProgramer.
import 'package:flutter/material.dart';
import '../../common/music/music_source.dart';
import '../../common/music/unified_library.dart';
import '../../widget/adaptive_option_sheet.dart';
import '../../widget/buyu_components.dart';

class FavoriteTargetsView extends StatefulWidget {
  const FavoriteTargetsView({super.key, this.library});
  final UnifiedLibrary? library;
  @override
  State<FavoriteTargetsView> createState() => _FavoriteTargetsViewState();
}

class _FavoriteTargetsViewState extends State<FavoriteTargetsView> {
  late final library = widget.library ?? UnifiedLibrary.instance;
  bool busy = false, working = false;
  String? error;
  Future<void> choose(MusicSource source) async {
    setState(() {
      busy = true;
      working = true;
      error = null;
    });
    try {
      final bound = library.remotes[source]!.account;
      final options = await library.targetOptions(source);
      if (!mounted) return;
      setState(() => working = false);
      final current = library.targets.get(source, bound);
      final index = await showModalBottomSheet<int>(
          context: context,
          isScrollControlled: true,
          builder: (sheet) =>
              AdaptiveOptionSheet(title: '${source.label}收藏歌单', children: [
                ListTile(
                    title: const Text('自动使用 BuYu收藏'),
                    subtitle: const Text('未指定时沿用原逻辑；需要同步时创建'),
                    trailing: current == null ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(sheet, -1)),
                for (var i = 0; i < options.length; i++)
                  ListTile(
                      title: Text(options[i].name),
                      trailing: current?.id == options[i].id
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.pop(sheet, i)),
              ]));
      if (index == null || !mounted) return;
      if (library.remotes[source]!.account != bound)
        throw const MusicServiceError('账号已切换，请重新选择');
      final selected = index < 0 ? null : options[index];
      if (selected?.id == current?.id) return;
      final merge = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
                  title: const Text('合并当前收藏？'),
                  content: Text(
                      '是否把当前${source.label}聚合收藏及原连接歌单中的歌曲合并到“${selected?.name ?? 'BuYu收藏'}”？\n\n合并只添加歌曲，不清空新旧歌单。仅连接会保留本地已有收藏，不主动写入新歌单；后续新增收藏同步到新连接。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text('取消')),
                    TextButton(
                        onPressed: () => Navigator.pop(dialog, false),
                        child: const Text('仅连接')),
                    TextButton(
                        onPressed: () => Navigator.pop(dialog, true),
                        child: const Text('合并并连接')),
                  ]));
      if (merge == null || !mounted) return;
      if (library.remotes[source]!.account != bound)
        throw const MusicServiceError('账号已切换，请重新选择');
      setState(() => working = true);
      await library.changeTarget(source, selected, mergeCurrent: merge);
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('连接已保存，同步结果可在聚合收藏查看')));
    } catch (e) {
      if (mounted)
        setState(
            () => error = e is MusicServiceError ? e.message : '收藏歌单连接失败，请重试');
    } finally {
      if (mounted)
        setState(() {
          busy = false;
          working = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('聚合收藏连接')),
      body: AnimatedBuilder(
          animation: library,
          builder: (context, _) => BuYuSettingsList(children: [
                if (working) const LinearProgressIndicator(),
                for (final source in MusicSource.values)
                  ListTile(
                      key: ValueKey('favorite-target:${source.name}'),
                      title: Text(source.label),
                      subtitle: Text(library.remotes[source]!.account.isEmpty
                          ? '请先登录该平台'
                          : library.targets
                                  .get(source, library.remotes[source]!.account)
                                  ?.name ??
                              '自动：BuYu收藏'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: busy || library.remotes[source]!.account.isEmpty
                          ? null
                          : () => choose(source)),
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.all(16), child: Text(error!)),
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                        '两个平台可分别指定本人创建的普通歌单。未指定时使用 BuYu收藏；连接按账号保存，切换账号不会沿用他人的歌单。指定歌单删除或无法编辑时会提示重新选择，不会改写其他歌单。')),
              ])));
}
