// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'music_source.dart';

class LocalFolder {
  LocalFolder(this.id, this.name, this.songs);
  final String id;
  final String name;
  final List<MediaItem> songs;
}

class LocalFolders extends ChangeNotifier {
  LocalFolders(this.box) {
    for (final raw in box.get(key, defaultValue: []) as List) {
      try {
        final item = raw as Map;
        folders.add(LocalFolder(
            item['id'],
            item['name'],
            (item['songs'] as List)
                .map((s) => restoreSong(s as Map))
                .toList()));
      } catch (_) {/* Keep other valid folders accessible. */}
    }
  }
  static const key = 'BUYU_LOCAL_FOLDERS_V1';
  static LocalFolders get instance {
    if (!GetIt.I.isRegistered<LocalFolders>())
      GetIt.I.registerSingleton<LocalFolders>(LocalFolders(GetIt.I<Box>()),
          dispose: (s) => s.dispose());
    return GetIt.I<LocalFolders>();
  }

  final Box box;
  final List<LocalFolder> folders = [];
  Future<void> _save(List<LocalFolder> next) async {
    await box.put(
        key,
        next
            .map((f) => {
                  'id': f.id,
                  'name': f.name,
                  'songs': f.songs.map(saveSong).toList()
                })
            .toList());
    folders
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  Future<void> _pending = Future<void>.value();
  Future<void> _enqueue(Future<void> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.catchError((Object _) {});
    return result;
  }

  Future<void> create(String name) => _enqueue(() async {
        name = name.trim();
        if (name.isEmpty || name.length > 40)
          throw const MusicServiceError('文件夹名称需为1—40个字符');
        if (folders.any((f) => f.name == name))
          throw const MusicServiceError('文件夹名称已存在');
        await _save([
          ...folders,
          LocalFolder('${DateTime.now().microsecondsSinceEpoch}', name, [])
        ]);
      });
  Future<void> rename(String id, String name) => _enqueue(() async {
        name = name.trim();
        if (name.isEmpty ||
            name.length > 40 ||
            folders.any((f) => f.id != id && f.name == name))
          throw const MusicServiceError('文件夹名称为空、过长或已存在');
        await _save(folders
            .map((f) => f.id == id ? LocalFolder(id, name, f.songs) : f)
            .toList());
      });
  Future<void> remove(String id) =>
      _enqueue(() => _save(folders.where((f) => f.id != id).toList()));
  Future<void> putSong(String id, MediaItem song, bool selected) =>
      _enqueue(() async {
        if (!folders.any((f) => f.id == id))
          throw const MusicServiceError('文件夹已不存在');
        await _save(folders
            .map((f) => f.id != id
                ? f
                : LocalFolder(id, f.name, [
                    ...f.songs.where((s) => sourceKey(s) != sourceKey(song)),
                    if (selected) song,
                  ]))
            .toList());
      });
}
