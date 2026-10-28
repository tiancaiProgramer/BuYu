// Community maintenance and new features: tiancaiProgramer.
import 'package:audio_service/audio_service.dart';
import 'audio_quality.dart';
import 'music/music_source.dart';
import 'music/qq_music.dart';
import 'netease_api/src/dio_ext.dart';
import 'netease_api/src/netease_api.dart';

class DownloadAvailability {
  const DownloadAvailability(this.labels, this.allowed);
  final Map<AudioQuality, String> labels;
  final Set<AudioQuality>? allowed;
  static Future<DownloadAvailability> load(MediaItem song) async {
    if (sourceOf(song) == MusicSource.qq) {
      final data = await QqMusic.instance.rpc('music.pf_song_detail_svr','get_song_detail_yqq',{'song_mid':song.extras?['mid']});
      final track = data['track_info'];
      if (track is! Map || track['mid'] != song.extras?['mid']) throw const MusicServiceError('QQ歌曲信息读取失败');
      final file = track['file'] as Map? ?? {};
      const fields = {AudioQuality.standard:'size_128mp3', AudioQuality.exhigh:'size_320mp3', AudioQuality.lossless:'size_flac', AudioQuality.hires:'size_hires'};
      return DownloadAvailability({for (final q in AudioQuality.values) q:
        q == AudioQuality.higher ? 'QQ暂无独立较高档，请选标准或极高' :
        (file[fields[q]] as num? ?? 0) > 0 ? '${((file[fields[q]] as num) / 1048576).toStringAsFixed(1)} MB · 下载时按账号确认' : '未列出资源，下载时确认'},
        AudioQuality.values.where((q)=>q!=AudioQuality.higher).toSet());
    }
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
