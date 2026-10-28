import '../../widget/adaptive_option_sheet.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
// Community maintenance and new features: tiancaiProgramer.
import 'package:flutter/material.dart';
import '../../common/downloads.dart';
import '../../common/music/music_source.dart';
import '../../common/audio_quality.dart';
import '../../widget/landscape_cards.dart';
import '../home/home_controller.dart';

class DownloadsView extends StatelessWidget {
  const DownloadsView({super.key});
  String _time(DateTime? time) => time == null
      ? '旧记录未保存时间'
      : '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  Future<void> _details(BuildContext context, DownloadJob job) =>
      showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (sheet) => SelectionArea(
                  child: AdaptiveOptionSheet(title: job.song.title, children: [
                for (final field in <String, String>{
                  '来源': sourceOf(job.song).label,
                  '歌手': job.song.artist ?? '',
                  '状态': job.status,
                  '请求音质': job.quality.label,
                  '接口档位': job.resolvedQuality == null
                      ? '旧记录未保存'
                      : AudioQuality.parse(job.resolvedQuality).label,
                  '文件头规格': job.actual ?? '尚未完成核验',
                  '文件大小':
                      '${job.received} 字节 / ${(job.received / 1048576).toStringAsFixed(2)} MiB',
                  '开始记录': _time(job.createdAt),
                  '完成或结束': _time(job.finishedAt),
                  '尝试次数': '${job.attempts}',
                  '保存文件夹': job.savedFolder ?? '旧记录未保存文件夹',
                  '文件名': job.filename ?? '尚未保存',
                  '文件位置': job.uri ?? '尚未保存',
                  if (job.error != null) '错误': job.error!
                }.entries)
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('${field.key}：${field.value}',
                          style: const TextStyle(fontSize: 14))),
              ])));

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
                            '${job.song.artist ?? ''} · ${sourceOf(job.song).label} · ${job.quality.label}\n${job.status}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis),
                        trailing:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                              tooltip: '下载记录信息',
                              icon: const Icon(TablerIcons.info_circle),
                              onPressed: () => _details(context, job)),
                          job.active
                              ? IconButton(
                                  tooltip: '取消下载',
                                  onPressed: job.state == DownloadState.saving
                                      ? null
                                      : () => downloads.cancel(job),
                                  icon: const Icon(TablerIcons.x))
                              : job.state == DownloadState.complete
                                  ? const Icon(TablerIcons.player_play)
                                  : IconButton(
                                      tooltip: '重试下载',
                                      onPressed: () => downloads.add(job.song,
                                          quality: job.quality),
                                      icon: const Icon(TablerIcons.refresh)),
                        ]),
                        onTap: job.state == DownloadState.complete
                            ? () async {
                                await Home.to.playByIndex(0, '已下载',
                                    mediaItem: [job.localSong]);
                              }
                            : null);
                  }

                  return Column(children: [
                    Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                            '保存位置：${downloads.folderLabel} · 点击已下载歌曲可离线播放')),
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
                                itemBuilder: (context, index) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 4),
                                    child: LandscapeCardSurface(
                                        child: item(context, index))))),
                  ]);
                })));
  }
}
