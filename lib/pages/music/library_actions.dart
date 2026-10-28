// Community maintenance and new features: tiancaiProgramer.
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import '../../widget/adaptive_option_sheet.dart';
import '../../common/music/local_folders.dart';
import '../../common/music/music_source.dart';
import '../../common/music/qq_music.dart';
import '../../common/music/qq_library_api.dart';
import '../../common/music/unified_library.dart';

Future<String?> libraryNameDialog(BuildContext context, String title,
    {String initial = ''}) async {
  return showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(title: title, initial: initial));
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});
  final String title, initial;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final text = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.title),
          content: TextField(
              controller: text,
              autofocus: true,
              maxLength: 40,
              onSubmitted: (s) => Navigator.pop(context, s)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(context, text.text.trim()),
                child: const Text('保存'))
          ]);
}

Future<void> libraryAction(BuildContext context, Future<void> Function() action,
    {String success = '已完成'}) async {
  try {
    await action();
    if (context.mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
  } catch (e) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is MusicServiceError ? e.message : '操作未完成，请重试')));
  }
}

Future<void> chooseLocalFolder(BuildContext context, MediaItem song) async {
  final folders = LocalFolders.instance;
  await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => AnimatedBuilder(
          animation: folders,
          builder: (context, _) => AdaptiveOptionSheet(
              title: '加入本地文件夹',
              children: [
                for (final folder in folders.folders)
                  CheckboxListTile(
                      title: Text(folder.name),
                      value: folder.songs
                          .any((s) => sourceKey(s) == sourceKey(song)),
                      onChanged: (value) => libraryAction(sheet, () async {
                            if (value == true &&
                                !UnifiedLibrary.instance.contains(song)) {
                              await UnifiedLibrary.instance
                                  .setFavorite(song, true);
                            }
                            await folders.putSong(
                                folder.id, song, value == true);
                          }, success: '本地分类已更新')),
              ],
              footer: Column(mainAxisSize: MainAxisSize.min, children: [
                TextButton.icon(
                    icon: const Icon(TablerIcons.folder_plus),
                    label: const Text('新建本地文件夹'),
                    onPressed: () async {
                      final name = await libraryNameDialog(sheet, '新建本地文件夹');
                      if (name != null && sheet.mounted)
                        await libraryAction(sheet, () => folders.create(name));
                    }),
                if (folders.folders.isEmpty) const Text('新建文件夹后即可分类，不影响歌曲原音源。'),
              ]))));
}

Future<void> chooseQqPlaylist(BuildContext context, MediaItem song) async {
  final qq = QqMusic.instance;
  try {
    final lists =
        (await qq.userPlaylists()).where(qq.editablePlaylist).toList();
    if (!context.mounted) return;
    final selected = await showModalBottomSheet<SourcePlaylist>(
        context: context,
        isScrollControlled: true,
        builder: (sheet) => AdaptiveOptionSheet(title: '收藏到QQ音乐歌单', children: [
              for (final list in lists)
                ListTile(
                    leading: const Icon(TablerIcons.playlist),
                    title: Text(list.name),
                    subtitle: Text('${list.count} 首 · QQ音乐'),
                    onTap: () => Navigator.pop(sheet, list)),
              if (lists.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('暂无可编辑歌单，请在查看/管理中新建')),
            ]));
    if (selected != null && context.mounted)
      await libraryAction(
          context, () => qq.changePlaylistSong(selected, song, true),
          success: 'QQ云端已读回确认收藏');
  } catch (e) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is MusicServiceError ? e.message : 'QQ歌单读取失败')));
  }
}
