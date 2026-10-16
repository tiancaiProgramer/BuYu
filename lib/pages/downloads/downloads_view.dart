// Community maintenance and new features: tiancaiProgramer.
import 'package:flutter/material.dart';
import '../../common/downloads.dart';
import '../../widget/landscape_cards.dart';
import '../home/home_controller.dart';

class DownloadsView extends StatelessWidget {
  const DownloadsView({super.key});
  @override
  Widget build(BuildContext context) {
    final downloads = Downloads.instance;
    return Scaffold(
        appBar: AppBar(title: const Text('下载管理')),
        body: SafeArea(
            top: false,
            child: AnimatedBuilder(
                animation: downloads,
                builder: (context, _) {
                  if (downloads.jobs.isEmpty)
                    return const Center(
                        child: Text('暂无下载\n在歌曲菜单中选择“下载歌曲”',
                            textAlign: TextAlign.center));
                  Widget item(BuildContext context, int index) {
                    final job = downloads.jobs[index];
                    return ListTile(
                        title: Text(job.song.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            '${job.song.artist ?? ''}\n${job.status}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis),
                        trailing: job.active
                            ? IconButton(
                                tooltip: '取消下载',
                                onPressed: job.state == DownloadState.saving
                                    ? null
                                    : () => downloads.cancel(job),
                                icon: const Icon(Icons.close))
                            : job.state == DownloadState.complete
                                ? const Icon(Icons.play_arrow)
                                : IconButton(
                                    tooltip: '重试下载',
                                    onPressed: () => downloads.add(job.song,
                                        quality: job.quality),
                                    icon: const Icon(Icons.refresh)),
                        onTap: job.state == DownloadState.complete
                            ? () async {
                                await Home.to.playByIndex(0, '已下载',
                                    mediaItem: [job.localSong]);
                              }
                            : null);
                  }

                  return Column(children: [
                    Padding(padding: const EdgeInsets.all(12), child: Text('保存位置：${downloads.folderLabel} · 点击已下载歌曲可离线播放')),
                    Expanded(
                        child: phoneLandscape(context)
                            ? GridView.builder(
                                padding: const EdgeInsets.all(12),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 3,
                                        mainAxisExtent: 108,
                                        mainAxisSpacing: 8,
                                        crossAxisSpacing: 10),
                                itemCount: downloads.jobs.length,
                                itemBuilder: (context, index) =>
                                    LandscapeCardSurface(
                                        child: item(context, index)))
                            : ListView.builder(
                                itemCount: downloads.jobs.length,
                                itemBuilder: item)),
                  ]);
                })));
  }
}
