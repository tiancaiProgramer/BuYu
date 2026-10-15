import 'package:audio_service/audio_service.dart';
import 'audio_quality.dart';
import 'netease_api/src/dio_ext.dart';
import 'netease_api/src/netease_api.dart';

class DownloadAvailability {
  const DownloadAvailability(this.labels, this.allowed);
  final Map<AudioQuality, String> labels;
  final Set<AudioQuality>? allowed;
  static Future<DownloadAvailability> load(MediaItem song) async {
    final response = await Https.dioProxy
        .postUri(NeteaseMusicApi().songDetailDioMetaData([song.id]));
    return parse(response.data as Map, song.id);
  }
  static DownloadAvailability parse(Map body, String songId) {
    final songs = body['songs'] as List? ?? [];
    final privileges = body['privileges'] as List? ?? [];
    final record =
        songs.cast<Map>().where((r) => '${r['id']}' == songId).first;
    final access =
        privileges.cast<Map>().where((r) => '${r['id']}' == songId).toList();
    final privilege =
        access.isEmpty ? record['privilege'] as Map? : access.first;
    final maxLevel = privilege?['downloadMaxBrLevel'];
    final maxIndex = AudioQuality.values.indexWhere((q) => q.name == maxLevel);
    final noDownload = privilege?['dl'] == 0;
    final allowed = noDownload
        ? <AudioQuality>{}
        : maxIndex < 0
            ? null
            : AudioQuality.values.take(maxIndex + 1).toSet();
    final fields = {
      AudioQuality.standard: 'l',
      AudioQuality.higher: 'm',
      AudioQuality.exhigh: 'h',
      AudioQuality.lossless: 'sq',
      AudioQuality.hires: 'hr'
    };
    final labels = <AudioQuality, String>{};
    for (final quality in AudioQuality.values) {
      final resource = record[fields[quality]];
      if (resource is Map) {
        final size = resource['size'] as num?;
        final br = resource['br'] as num?;
        labels[quality] = [
          if (br != null) '${br ~/ 1000} kbps',
          if (size != null) '${(size / 1048576).toStringAsFixed(1)} MB'
        ].join(' · ');
      } else
        labels[quality] = '官方未列出此档资源，下载时确认';
      if (allowed != null && !allowed.contains(quality))
        labels[quality] = '当前账号或歌曲暂不提供';
    }
    return DownloadAvailability(labels, allowed);
  }
}
