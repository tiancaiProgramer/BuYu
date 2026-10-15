import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import '../common/downloads.dart';
import '../common/audio_quality.dart';
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
    if (song.id.isEmpty || song.extras?['type'] == 'local')
      return const SizedBox.shrink();
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
  late final Future<DownloadAvailability> availability =
      (widget.loader ?? DownloadAvailability.load)(widget.song)
          .timeout(const Duration(seconds: 10));
  @override
  Widget build(BuildContext context) => FutureBuilder<DownloadAvailability>(
      future: availability,
      builder: (context, snapshot) {
        final downloads = Downloads.instance;
        return AdaptiveOptionSheet(
            title: '选择下载音质',
            children: [
              for (final quality in AudioQuality.values)
                RadioListTile<AudioQuality>(
                    title: Text(quality.label),
                    subtitle: Text(snapshot.data?.labels[quality] ??
                        (snapshot.connectionState == ConnectionState.done
                            ? '资源信息暂不可用，下载时确认'
                            : '正在查询官方资源…')),
                    value: quality,
                    toggleable: true,
                    groupValue: downloads.defaultQuality,
                    onChanged: snapshot.data?.allowed != null &&
                            !snapshot.data!.allowed!.contains(quality)
                        ? null
                        : (_) => Navigator.pop(context, quality)),
            ],
            footer: Text('保存至：${downloads.folderLabel}\n完成后显示实际音频规格'));
      });
}
