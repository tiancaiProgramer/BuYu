import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
// Community maintenance and new features: tiancaiProgramer.
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import '../../common/music/music_source.dart';
import '../../common/music/local_folders.dart';
import '../../common/music/qq_library_api.dart';
import 'library_actions.dart';
import '../../common/music/qq_music.dart';
import '../../common/music/unified_library.dart';
import '../../widget/landscape_cards.dart';
import '../home/home_controller.dart';
import '../play_list/playlist_view.dart';

class MixedLibraryView extends StatefulWidget {
  const MixedLibraryView({super.key, this.playlist, this.folderId});
  final String? folderId;
  final SourcePlaylist? playlist;
  @override
  State<MixedLibraryView> createState() => _MixedLibraryViewState();
}

class _MixedLibraryViewState extends State<MixedLibraryView> {
  final library = UnifiedLibrary.instance;
  final folders = LocalFolders.instance;
  List<MediaItem> remote = [];
  bool loading = false;
  String? error;
  int page = 0;
  bool ended = false;
  @override
  void initState() {
    super.initState();
    if (widget.playlist != null) {
      load();
    } else if (widget.folderId == null) {
      library.refreshFromCloud();
    }
  }

  Future<void> load() async {
    if (loading || ended) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final items = await QqMusic.instance
          .playlistSongs(widget.playlist!, page: page + 1);
      if (mounted) {
        final ids = remote.map((s) => s.id).toSet();
        remote.addAll(items.where((s) => ids.add(s.id)));
        page++;
        ended = items.length < 100;
      }
    } catch (_) {
      error = 'QQ歌单读取失败，点击加载更多重试';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: Listenable.merge([library, folders]),
      builder: (context, _) {
        final local =
            folders.folders.where((f) => f.id == widget.folderId).toList();
        final folder = local.isEmpty ? null : local.single;
        final songs = widget.playlist != null
            ? remote
            : widget.folderId != null
                ? folder?.songs ?? <MediaItem>[]
                : library.songs;
        return Scaffold(
            appBar: AppBar(
                title: Text(widget.playlist?.name ?? folder?.name ?? '聚合收藏'),
                actions: [
                  if (widget.playlist == null)
                    IconButton(
                        tooltip: '新建本地文件夹',
                        icon: const Icon(TablerIcons.folder_plus),
                        onPressed: () async {
                          final name =
                              await libraryNameDialog(context, '新建本地文件夹');
                          if (name != null && context.mounted)
                            await libraryAction(
                                context, () => folders.create(name));
                        }),
                  if (widget.playlist != null)
                    IconButton(
                        tooltip: '加入聚合收藏',
                        icon: const Icon(TablerIcons.heart),
                        onPressed: () => libraryAction(context, () async {
                              for (final song in remote) {
                                if (!library.contains(song))
                                  await library.setFavorite(song, true);
                              }
                            }, success: '当前已加载歌曲已加入聚合收藏')),
                  if (widget.playlist == null)
                    IconButton(
                        tooltip: '读取并同步云端收藏',
                        icon: const Icon(TablerIcons.refresh),
                        onPressed: library.syncing || library.refreshing
                            ? null
                            : () async {
                                await QqMusic.instance.restore();
                                await library.refreshFromCloud();
                                await library.sync();
                              })
                ]),
            body: SafeArea(
                top: false,
                child: Column(children: [
                  if (widget.playlist == null &&
                      widget.folderId == null &&
                      folders.folders.isNotEmpty)
                    SizedBox(
                        height: 60,
                        child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final f in folders.folders)
                                Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: ActionChip(
                                        avatar: const Icon(TablerIcons.folder),
                                        label: Text(f.name),
                                        onPressed: () => Navigator.of(context)
                                            .push(MaterialPageRoute(
                                                builder: (_) =>
                                                    MixedLibraryView(
                                                        folderId: f.id)))))
                            ])),
                  if (widget.playlist == null)
                    Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(library.refreshing
                            ? '正在读取两平台BuYu收藏…'
                            : library.syncing
                                ? '正在同步收藏…'
                                : library.pendingCount > 0
                                    ? '本地已保存 · ${library.pendingCount} 项等待同步，点右上角重试'
                                    : '聚合收藏 · 网易云 / QQ音乐 BuYu收藏')),
                  if (widget.playlist == null &&
                      widget.folderId == null &&
                      library.refreshing)
                    const LinearProgressIndicator(),
                  if (widget.playlist == null && widget.folderId == null)
                    for (final message in library.readErrors.values)
                      Text(message),
                  if (error != null) Text(error!),
                  if (loading) const LinearProgressIndicator(),
                  Expanded(
                      child: songs.isEmpty
                          ? Center(
                              child: Text(
                                  loading ? '正在加载…' : '暂无歌曲，点击歌曲菜单的“聚合收藏”即可添加'))
                          : GridView.builder(
                              padding: const EdgeInsets.all(12),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount:
                                          phoneLandscape(context) ? 3 : 1,
                                      mainAxisExtent: 90,
                                      mainAxisSpacing: 8,
                                      crossAxisSpacing: 10),
                              itemCount: songs.length,
                              itemBuilder: (context, index) =>
                                  LandscapeCardSurface(
                                      child: Column(children: [
                                    Expanded(
                                        child: Row(children: [
                                      Expanded(
                                          child: SongItem(
                                              index: index,
                                              mediaItem: songs[index],
                                              showArtwork: true,
                                              onTap: () => Home.to.playByIndex(
                                                  index,
                                                  widget.playlist?.name ??
                                                      '聚合收藏',
                                                  mediaItem: songs))),
                                      if (folder != null ||
                                          widget.playlist != null &&
                                              QqMusic.instance.editablePlaylist(
                                                  widget.playlist!))
                                        IconButton(
                                            tooltip: '从此列表移除',
                                            icon: const Icon(
                                                TablerIcons.circle_minus),
                                            onPressed: () => libraryAction(
                                                    context, () async {
                                                  if (folder != null) {
                                                    await folders.putSong(
                                                        folder.id,
                                                        songs[index],
                                                        false);
                                                  } else {
                                                    await QqMusic.instance
                                                        .changePlaylistSong(
                                                            widget.playlist!,
                                                            songs[index],
                                                            false);
                                                    if (mounted) {
                                                      setState(() {
                                                        remote.clear();
                                                        page = 0;
                                                        ended = false;
                                                      });
                                                      await load();
                                                    }
                                                  }
                                                }))
                                    ])),
                                    if (widget.playlist == null &&
                                        library.entries[sourceKey(songs[index])]
                                                ?.error !=
                                            null)
                                      Text(
                                          library
                                              .entries[sourceKey(songs[index])]!
                                              .error!,
                                          style: const TextStyle(fontSize: 11)),
                                  ])))),
                  if (widget.playlist != null && !ended)
                    TextButton(
                        onPressed: loading ? null : load,
                        child: const Text('加载更多')),
                ])));
      });
}
