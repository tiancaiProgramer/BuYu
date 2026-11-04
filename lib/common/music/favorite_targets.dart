// Community maintenance and new features: tiancaiProgramer.
import 'package:hive_flutter/hive_flutter.dart';
import 'music_source.dart';

class FavoriteTargets {
  FavoriteTargets(this.box);
  final Box box;
  static const storageKey = 'BUYU_FAVORITE_TARGETS_V1';
  Map<String, dynamic> get all => Map<String, dynamic>.from(
      box.get(storageKey, defaultValue: <String, dynamic>{}) as Map);
  SourcePlaylist? get(MusicSource source, String account) {
    final raw = all['${source.name}:$account'];
    if (raw is! Map || account.isEmpty) return null;
    return SourcePlaylist(
        source: source,
        id: '${raw['id']}',
        name: '${raw['name']}',
        directory: '${raw['directory'] ?? ''}');
  }

  String token(MusicSource source, String account) =>
      get(source, account)?.id ?? 'auto';
  Map<String, dynamic> withTarget(
      MusicSource source, String account, SourcePlaylist? list) {
    final result = all, key = '${source.name}:$account';
    if (list == null) {
      result.remove(key);
    } else {
      result[key] = {
        'id': list.id,
        'name': list.name,
        'directory': list.directory
      };
    }
    return result;
  }
}

abstract class FavoritesTargetProvider {
  Future<List<SourcePlaylist>> targetOptions();
}
