// Community maintenance and new features: tiancaiProgramer.
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import '../../widget/adaptive_option_sheet.dart';
import 'package:get/get.dart';
import '../../common/music/local_folders.dart';
import '../../common/music/netease_library.dart';
import '../../common/netease_api/src/api/play/bean.dart';
import '../../common/music/music_source.dart';
import '../../common/music/qq_library_api.dart';
import '../../common/music/qq_music.dart';
import '../../routes/router.gr.dart' as routes;
import '../../widget/landscape_cards.dart';
import '../home/home_controller.dart';
import '../music/library_actions.dart';
import '../music/mixed_library_view.dart';
import '../music/playlist_source_filter.dart';
import '../user/user_controller.dart';

class PlaylistManagerView extends StatefulWidget {
  const PlaylistManagerView({super.key});
  @override
  State<PlaylistManagerView> createState() => _ManagerState();
}

class _ManagerState extends State<PlaylistManagerView> {
  final qq = QqMusic.instance;
  final folders = LocalFolders.instance;
  bool loading = false;
  String error = '';
  Future<void> refresh() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = '';
    });
    try {
      if (qq.loggedIn) await qq.userPlaylists();
      if (Home.to.loginStatus.value == LoginStatus.login)
        await UserController.to.getUserPlayList();
    } catch (e) {
      error = e is MusicServiceError ? e.message : '歌单刷新失败';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> create() async {
    final source = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (sheet) => AdaptiveOptionSheet(title: '新建文件夹或歌单', children: [
              ListTile(
                  leading: const Icon(TablerIcons.folder_plus),
                  title: const Text('新建本地文件夹'),
                  onTap: () => Navigator.pop(sheet, 'local')),
              ListTile(
                  leading: const Icon(TablerIcons.playlist),
                  title: const Text('新建网易云歌单'),
                  onTap: () => Navigator.pop(sheet, 'netease')),
              ListTile(
                  leading: const Icon(TablerIcons.playlist),
                  title: const Text('新建QQ音乐歌单'),
                  onTap: () => Navigator.pop(sheet, 'qq')),
            ]));
    if (source == null || !mounted) return;
    final name = await libraryNameDialog(
        context,
        source == 'local'
            ? '新建本地文件夹'
            : source == 'netease'
                ? '新建网易云歌单'
                : '新建QQ音乐歌单');
    if (name == null || !mounted) return;
    await libraryAction(context, () async {
      if (source == 'local') {
        await folders.create(name);
      } else if (source == 'netease') {
        await NeteaseLibrary(Home.to.box).create(name);
        await UserController.to.getUserPlayList();
      } else {
        await qq.createPlaylist(name);
      }
    });
  }

  Future<void> editQq(SourcePlaylist list, String action) async {
    if (action == 'rename') {
      final name =
          await libraryNameDialog(context, '修改QQ歌单名称', initial: list.name);
      if (name != null && mounted)
        await libraryAction(context, () => qq.renamePlaylist(list, name));
    } else {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
                  title: const Text('删除QQ云端歌单？'),
                  content: Text('“${list.name}”将从QQ音乐账号删除，不会删除音频文件。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(d, false),
                        child: const Text('取消')),
                    TextButton(
                        onPressed: () => Navigator.pop(d, true),
                        child: const Text('删除'))
                  ]));
      if (confirmed == true && mounted)
        await libraryAction(context, () => qq.deletePlaylist(list));
    }
  }

  Future<void> editNetease(Play list, String action) async {
    final api = NeteaseLibrary(Home.to.box);
    if (action == 'rename') {
      final name = await libraryNameDialog(context, '修改网易云歌单名称',
          initial: list.name ?? '');
      if (name != null && mounted)
        await libraryAction(context, () async {
          await api.rename(list, name);
          await UserController.to.getUserPlayList();
        });
    } else {
      final yes = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
                  title: const Text('删除网易云歌单？'),
                  content: Text('“${list.name ?? ''}”将从当前网易云账号删除。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(d, false),
                        child: const Text('取消')),
                    TextButton(
                        onPressed: () => Navigator.pop(d, true),
                        child: const Text('删除'))
                  ]));
      if (yes == true && mounted)
        await libraryAction(context, () async {
          await api.delete(list);
          await UserController.to.getUserPlayList();
        });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: Listenable.merge([qq, folders]),
      builder: (context, _) => Obx(() {
            final user = UserController.to;
            final source = user.playlistSource.value;
            final cloud = user.cloudPlaylistsExpanded.value;
            final cards = <Widget>[
              ListTile(
                  leading: const Icon(TablerIcons.heart),
                  title: const Text('聚合收藏'),
                  subtitle: const Text('所有来源始终显示'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const MixedLibraryView()))),
              for (final folder in folders.folders)
                ListTile(
                    leading: const Icon(TablerIcons.folder),
                    title: Text(folder.name),
                    subtitle: Text('${folder.songs.length} 首 · 本地文件夹'),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => MixedLibraryView(folderId: folder.id))),
                    trailing: PopupMenuButton<String>(
                        icon: const Icon(TablerIcons.dots_vertical),
                        onSelected: (action) async {
                          if (action == 'rename') {
                            final name = await libraryNameDialog(
                                context, '修改文件夹名称',
                                initial: folder.name);
                            if (name != null && context.mounted)
                              await libraryAction(context,
                                  () => folders.rename(folder.id, name));
                          } else {
                            final yes = await showDialog<bool>(
                                context: context,
                                builder: (d) => AlertDialog(
                                        title: const Text('删除本地文件夹？'),
                                        content:
                                            const Text('只删除分类，不影响聚合收藏和云端歌曲。'),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(d, false),
                                              child: const Text('取消')),
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(d, true),
                                              child: const Text('删除'))
                                        ]));
                            if (yes == true && context.mounted)
                              await libraryAction(
                                  context, () => folders.remove(folder.id));
                          }
                        },
                        itemBuilder: (_) => [
                              const PopupMenuItem(
                                  value: 'rename', child: Text('重命名')),
                              const PopupMenuItem(
                                  value: 'delete', child: Text('删除文件夹'))
                            ])),
              if (cloud && source != PlaylistSource.netease)
                for (final list in qq.playlists)
                  ListTile(
                      leading: const Icon(TablerIcons.playlist),
                      title: Text(list.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${list.count} 首 · QQ音乐'),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => MixedLibraryView(playlist: list))),
                      trailing: qq.editablePlaylist(list)
                          ? PopupMenuButton<String>(
                              icon: const Icon(TablerIcons.dots_vertical),
                              onSelected: (action) => editQq(list, action),
                              itemBuilder: (_) => [
                                    const PopupMenuItem(
                                        value: 'rename', child: Text('重命名')),
                                    const PopupMenuItem(
                                        value: 'delete', child: Text('删除云端歌单'))
                                  ])
                          : null),
              if (cloud && source != PlaylistSource.qq)
                for (final list in user.playlist)
                  ListTile(
                      leading: const Icon(TablerIcons.playlist),
                      title: Text(list.name ?? '',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${list.trackCount ?? 0} 首 · 网易云'),
                      trailing: NeteaseLibrary(Home.to.box).owns(list)
                          ? PopupMenuButton<String>(
                              icon: const Icon(TablerIcons.dots_vertical),
                              onSelected: (action) => editNetease(list, action),
                              itemBuilder: (_) => [
                                    const PopupMenuItem(
                                        value: 'rename', child: Text('重命名')),
                                    const PopupMenuItem(
                                        value: 'delete', child: Text('删除云端歌单'))
                                  ])
                          : null,
                      onTap: () => context.router.push(
                          const routes.PlayListView().copyWith(args: list))),
            ];
            return Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(title: const Text('我的歌单'), actions: [
                  IconButton(
                      tooltip: '新建文件夹或歌单',
                      icon: const Icon(TablerIcons.folder_plus),
                      onPressed: create),
                  IconButton(
                      tooltip: '刷新',
                      onPressed: loading ? null : refresh,
                      icon: const Icon(TablerIcons.refresh))
                ]),
                body: SafeArea(
                    top: false,
                    child: Column(children: [
                      Row(children: [
                        Expanded(
                            child: PlaylistSourceFilter(
                                value: source,
                                onChanged: user.setPlaylistSource)),
                        IconButton(
                            tooltip: cloud ? '折叠云端歌单' : '展开云端歌单',
                            icon: Icon(cloud
                                ? TablerIcons.chevron_up
                                : TablerIcons.chevron_down),
                            onPressed: user.toggleCloudPlaylists)
                      ]),
                      if (loading) const LinearProgressIndicator(),
                      if (error.isNotEmpty) Text(error),
                      Expanded(
                          child: GridView.count(
                              key: const ValueKey('playlist-manager-landscape'),
                              crossAxisCount: phoneLandscape(context) ? 3 : 1,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 10,
                              childAspectRatio:
                                  phoneLandscape(context) ? 3.1 : 4.8,
                              padding: const EdgeInsets.all(12),
                              children: cards
                                  .map((c) => LandscapeCardSurface(child: c))
                                  .toList())),
                    ])));
          }));
}
