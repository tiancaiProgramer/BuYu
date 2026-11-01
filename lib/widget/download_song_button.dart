import '../common/music/music_source.dart';
// Community maintenance and new features: tiancaiProgramer.
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import '../common/downloads.dart';
import '../common/audio_quality.dart';
import '../common/audio_quality_preferences.dart';
import 'adaptive_option_sheet.dart';
import '../common/download_availability.dart';

Future<void> downloadSong(BuildContext context, MediaItem song) async {
  final downloads = Downloads.instance;
  final selected = await showModalBottomSheet<AudioQuality>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => DownloadQualityPicker(song: song));
  if (selected == null) return;
  try {
    final notifications = await Downloads.prepareNotifications();
    await downloads.add(song, quality: selected);
    final completed = downloads.forSong(song, quality: selected)?.state ==
        DownloadState.complete;
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: const Color(0xff333333),
          content: Text(
              completed
                  ? '该音质已下载，可在本地音乐 → 下载管理查看'
                  : notifications
                      ? '已开始下载，通知栏可查看进度'
                      : '已开始下载；系统通知未开启，可在本地音乐 → 下载管理查看',
              style: const TextStyle(color: Colors.white))));
  } catch (error) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              error is StateError ? error.message.toString() : '暂时无法开始下载')));
  }
}

class DownloadSongButton extends StatelessWidget {
  const DownloadSongButton({super.key, required this.song});
  final MediaItem song;
  @override
  Widget build(BuildContext context) {
    if (song.id.isEmpty || isLocalSong(song)) return const SizedBox.shrink();
    final downloads = Downloads.instance;
    return AnimatedBuilder(
        animation: downloads,
        builder: (context, _) {
          final job = downloads.forSong(song);
          return ListTile(
              key: const ValueKey('download-current-song'),
              leading: const Icon(Icons.download_outlined),
              title: const Text('下载当前歌曲'),
              subtitle: Text(job?.status ?? '选择音质 · ${downloads.folderLabel}'),
              trailing: job?.active == true
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
              onTap: () => downloadSong(context, song));
        });
  }
}

class DownloadQualityPicker extends StatefulWidget {
  const DownloadQualityPicker({super.key, required this.song, this.loader});
  final MediaItem song;
  final Future<DownloadAvailability> Function(MediaItem)? loader;
  @override
  State<DownloadQualityPicker> createState() => _DownloadQualityPickerState();
}

class _DownloadQualityPickerState extends State<DownloadQualityPicker> {
  late Future<DownloadAvailability> availability = _load();

  Future<DownloadAvailability> _load() =>
      (widget.loader ?? DownloadAvailability.load)(widget.song)
          .timeout(const Duration(seconds: 10));
  @override
  Widget build(BuildContext context) => FutureBuilder<DownloadAvailability>(
      future: availability,
      builder: (context, snapshot) {
        final downloads = Downloads.instance;
        final data = snapshot.data;
        final qualities = AudioQualityOptions.supported(
                sourceOf(widget.song), AudioQualityUse.download)
            .where((q) => data?.allowed == null || data!.allowed!.contains(q))
            .toList();
        return AdaptiveOptionSheet(
            title: '选择下载音质',
            children: [
              if (snapshot.connectionState != ConnectionState.done)
                const ListTile(
                    title: Text('正在查询官方资源…'),
                    trailing: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)))
              else if (snapshot.hasError || data == null)
                ListTile(
                    title: const Text('资源信息读取失败，点击重试'),
                    trailing: const Icon(Icons.refresh),
                    onTap: () => setState(() {
                          availability = _load();
                        }))
              else if (qualities.isEmpty)
                const ListTile(title: Text('当前歌曲暂无可用下载音质'))
              else
                for (final quality in qualities)
                  RadioListTile<AudioQuality>(
                      title: Text(quality.label),
                      subtitle: Text(data.labels[quality] ?? '下载时按账号确认'),
                      value: quality,
                      toggleable: true,
                      groupValue:
                          downloads.defaultQualityFor(sourceOf(widget.song)),
                      onChanged: (_) => Navigator.pop(context, quality)),
            ],
            footer: Text(
                '保存至：${downloads.folderLabel}\n仅显示当前歌曲可用档位。按所选音质下载，失败时提示，不自动降级。'));
      });
}
