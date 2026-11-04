// Community maintenance and new features: tiancaiProgramer.
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../widget/landscape_cards.dart';
import '../../widget/buyu_components.dart';
import '../home/home_controller.dart';
import '../play_list/playlist_view.dart';
import 'cache_directory.dart';
import 'qq_cache_scanner.dart';

class MusicCachesView extends StatelessWidget {
  const MusicCachesView(
      {super.key, required this.onNetease, required this.onQq});
  final VoidCallback onNetease, onQq;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('音乐缓存')),
      body: BuYuSettingsList(children: [
        ListTile(
            leading: const Icon(Icons.music_note_outlined),
            title: const Text('网易云缓存歌曲'),
            subtitle: const Text('读取网易云官方客户端的现有缓存'),
            onTap: onNetease),
        ListTile(
            leading: const Icon(Icons.music_note_outlined),
            title: const Text('QQ音乐缓存 / 本地文件'),
            subtitle: const Text('识别可访问目录中的普通音频；加密缓存无法通过改名播放'),
            onTap: onQq),
        const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
                '这两项读取官方客户端留在设备上的文件，BuYu 在线播放不会自动保存完整音频。BuYu 已下载的两平台歌曲请到“下载管理”查看。')),
      ]));
}

class QqCacheView extends StatefulWidget {
  const QqCacheView({super.key, this.scan});
  final Future<QqCacheScan> Function()? scan;
  @override
  State<QqCacheView> createState() => _QqCacheViewState();
}

class _QqCacheViewState extends State<QqCacheView> {
  late Future<QqCacheScan> task;
  Future<QqCacheScan> scan() async {
    if (widget.scan != null) return widget.scan!();
    final app = await getExternalStorageDirectory();
    final root = app == null ? null : cacheStorageRoot(app.path);
    if (root == null) throw StateError('无法定位共享存储');
    return scanQqCache([
      '$root/qqmusic/cache',
      '$root/qqmusic/song',
      '$root/QQMusic/cache',
      '$root/Android/data/com.tencent.qqmusic/cache',
      '$root/Android/data/com.tencent.qqmusic/files'
    ]);
  }

  @override
  void initState() {
    super.initState();
    task = scan();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('QQ音乐缓存 / 本地文件'), actions: [
        IconButton(
            tooltip: '重新扫描',
            onPressed: () => setState(() => task = scan()),
            icon: const Icon(Icons.refresh)),
      ]),
      body: FutureBuilder<QqCacheScan>(
          future: task,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done)
              return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError)
              return const Center(child: Text('无法读取QQ音乐目录，请检查文件访问权限后重新扫描'));
            final data = snapshot.data!;
            return Column(children: [
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                      '${data.songs.length} 首普通音频 · ${data.encryptedOrUnknown} 个加密或未知文件 · ${data.inaccessible} 处目录/文件不可访问${data.truncated ? ' · 已达到扫描上限' : ''}\nQQ缓存与网易云格式不同，加密文件不能只改名播放。Android 受保护目录即使授权也可能无法读取。')),
              Expanded(
                  child: data.songs.isEmpty
                      ? const Center(
                          child: Text('未找到可直接播放的QQ音频\n可在BuYu下载歌曲后从“下载管理”播放',
                              textAlign: TextAlign.center))
                      : GridView.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount:
                                      phoneLandscape(context) ? 3 : 1,
                                  mainAxisExtent: 80),
                          itemCount: data.songs.length,
                          itemBuilder: (_, i) => SongItem(
                              index: i,
                              mediaItem: data.songs[i],
                              onTap: () => Home.to.playByIndex(i, 'QQ本地音频',
                                  mediaItem: data.songs)))),
            ]);
          }));
}
