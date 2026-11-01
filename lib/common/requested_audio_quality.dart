// Community maintenance and new features: tiancaiProgramer.
import 'package:dio/dio.dart';
import 'audio_quality.dart';
import 'netease_api/src/dio_ext.dart';
import 'netease_api/src/netease_api.dart';

/// Some NetEase Hi-Res files are labelled `lossless` by the URL endpoint.
/// Accept that alias only when the returned file matches the requested resource.
bool matchesRequestedNeteaseResource(Map item, Map song, AudioQuality quality) {
  const fields = {
    AudioQuality.standard: 'l',
    AudioQuality.higher: 'm',
    AudioQuality.exhigh: 'h',
    AudioQuality.lossless: 'sq',
    AudioQuality.hires: 'hr'
  };
  final resource = song[fields[quality]];
  final size = item['size'];
  return resource is Map && size is num && size > 0 && resource['size'] == size;
}

Future<bool> isRequestedNeteaseQuality(
    String id, Map item, AudioQuality quality,
    {CancelToken? cancelToken}) async {
  if (item['level'] == quality.name) return true;
  final response = await Https.dioProxy
      .postUri(NeteaseMusicApi().songDetailDioMetaData([id]),
          cancelToken: cancelToken)
      .timeout(const Duration(seconds: 10));
  final body = response.data;
  final songs = body is Map ? body['songs'] : null;
  if (songs is! List) return false;
  for (final song in songs.whereType<Map>()) {
    if ('${song['id']}' == id)
      return matchesRequestedNeteaseResource(item, song, quality);
  }
  return false;
}
