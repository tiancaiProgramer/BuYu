// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../constants/key.dart';
import '../netease_api/src/netease_api.dart';
import 'music_source.dart';
import 'netease_library.dart';
import 'qq_music.dart';
import 'qq_library_api.dart';
import 'favorite_targets.dart';

abstract class FavoritesRemote {
  String get account;
  Future<SourcePlaylist> ensurePlaylist();
  Future<void> apply(SourcePlaylist list, MediaItem song, bool add);
}

abstract class FavoritesReader {
  Future<List<MediaItem>> readFavorites();
}

abstract class FavoritesSnapshotReader implements FavoritesReader {
  Future<FavoritesSnapshot> readSnapshot();
}

class NeteaseFavoritesRemote
    implements
        FavoritesRemote,
        FavoritesSnapshotReader,
        FavoritesTargetProvider {
  NeteaseFavoritesRemote(this.box, {NeteaseMusicApi? api}) : _providedApi = api;
  final Box box;
  final NeteaseMusicApi? _providedApi;
  NeteaseMusicApi get api => _providedApi ?? NeteaseMusicApi();
  @override
  Future<FavoritesSnapshot> readSnapshot() =>
      NeteaseLibrary(box, api: api).favoritesSnapshot(
          target: FavoriteTargets(box).get(MusicSource.netease, account));
  @override
  Future<List<SourcePlaylist>> targetOptions() async {
    final library = NeteaseLibrary(box, api: api);
    return (await library.lists())
        .where(library.owns)
        .map((p) => SourcePlaylist(
            source: MusicSource.netease, id: p.id, name: p.name ?? ""))
        .toList();
  }

  @override
  Future<List<MediaItem>> readFavorites() async => (await readSnapshot()).songs;
  @override
  String get account {
    try {
      final raw = box.get(loginData);
      final data = raw is String ? jsonDecode(raw) : raw;
      return '${data?['profile']?['userId'] ?? ''}';
    } catch (_) {
      return '';
    }
  }

  @override
  Future<SourcePlaylist> ensurePlaylist() async {
    if (account.isEmpty) throw const MusicServiceError('请先登录网易云');
    final bound = account;
    final target = FavoriteTargets(box).get(MusicSource.netease, bound);
    if (target != null) {
      final options = await targetOptions();
      if (account != bound) throw const MusicServiceError("网易云账号已切换");
      return options.firstWhere((p) => p.id == target.id,
          orElse: () => throw const MusicServiceError("指定收藏歌单已删除或不可编辑，请重新选择"));
    }
    final items = await NeteaseLibrary(box, api: api).lists();
    for (final p in items) {
      if ((p.name ?? '').trim().toLowerCase() == 'buyu收藏' &&
          (p.creator?.userId ?? p.userId) == bound)
        return SourcePlaylist(
            source: MusicSource.netease, id: p.id, name: 'BuYu收藏');
    }
    final created = await api.playlistCreate('BuYu收藏', true);
    if (account != bound) throw const MusicServiceError('网易云账号已切换');
    if (created.code != 200 || created.id.isEmpty)
      throw const MusicServiceError('网易云收藏歌单创建失败');
    return SourcePlaylist(
        source: MusicSource.netease, id: created.id, name: 'BuYu收藏');
  }

  @override
  Future<void> apply(SourcePlaylist list, MediaItem song, bool add) async {
    final bound = account;
    if (bound.isEmpty) throw const MusicServiceError('请先登录网易云');
    final result = await api.playlistManipulateTracks(list.id, song.id, add);
    // 502 is the documented "already exists" response for this operation.
    if (result.code != 200 && !(add && result.code == 502))
      throw const MusicServiceError('网易云收藏同步失败，请检查登录后重试');
    for (var attempt = 0; attempt < 2; attempt++) {
      final detail = await api.playListDetail(list.id);
      if (account != bound) throw const MusicServiceError('网易云账号已切换');
      final ids = detail.playlist?.trackIds;
      final complete =
          ids != null && ids.length >= (detail.playlist?.trackCount ?? 0);
      if (detail.code == 200 &&
          complete &&
          ids.any((id) => id.id == song.id) == add) return;
      if (attempt == 0)
        await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    throw const MusicServiceError('网易云尚未确认收藏变更，已保留待同步记录');
  }
}

class QqFavoritesRemote
    implements
        FavoritesRemote,
        FavoritesSnapshotReader,
        FavoritesTargetProvider {
  QqFavoritesRemote(this.qq, {this.box});
  final Box? box;
  SourcePlaylist? get target =>
      box == null ? null : FavoriteTargets(box!).get(MusicSource.qq, account);
  @override
  Future<List<SourcePlaylist>> targetOptions() async =>
      (await qq.userPlaylists()).where(qq.editablePlaylist).toList();
  final QqMusic qq;
  @override
  Future<List<MediaItem>> readFavorites() async => (await readSnapshot()).songs;
  @override
  Future<FavoritesSnapshot> readSnapshot() async {
    final bound = account;
    if (bound.isEmpty) throw const MusicServiceError('请先登录QQ音乐');
    final selected = target;
    final lists = (await qq.userPlaylists())
        .where((p) => selected == null
            ? p.name.trim().toLowerCase() == 'buyu收藏'
            : p.id == selected.id && qq.editablePlaylist(p))
        .toList();
    if (selected != null && lists.isEmpty)
      throw const MusicServiceError('指定QQ收藏歌单已删除或不可编辑，请重新选择');
    final songs = <String, MediaItem>{};
    for (final list in lists) {
      var ended = false;
      final membership = <String>{};
      for (var page = 1; page <= 100; page++) {
        final items = await qq.playlistSongs(list, page: page);
        if (account != bound) throw const MusicServiceError('QQ账号已切换，请重新读取收藏');
        for (final song in items) {
          songs[sourceKey(song)] = song;
          membership.add(sourceKey(song));
        }
        if (items.length < 100) {
          ended = true;
          break;
        }
      }
      if (!ended || membership.length < list.count)
        throw const MusicServiceError('QQ收藏尚未完整读取，请重试');
    }
    if (account != bound) throw const MusicServiceError('QQ账号已切换，请重新读取收藏');
    return FavoritesSnapshot(songs.values.toList(),
        playlistExists: lists.isNotEmpty);
  }

  @override
  String get account => qq.loggedIn ? qq.account : '';
  @override
  Future<SourcePlaylist> ensurePlaylist() async {
    final selected = target;
    return selected == null ? qq.createFavorites() : qq.requireOwned(selected);
  }

  @override
  Future<void> apply(SourcePlaylist list, MediaItem song, bool add) =>
      qq.syncFavorite(list, song, add);
}

class FavoriteEntry {
  FavoriteEntry(this.song,
      {this.selected = true,
      this.owner = '',
      this.revision = 0,
      this.synced = -1,
      this.target = "auto"});
  final MediaItem song;
  bool selected;
  String owner;
  int revision, synced;
  String target;
  String? error;
  bool get pending => revision != synced;
  Map<String, dynamic> toMap() => {
        'song': saveSong(song),
        'selected': selected,
        'owner': owner,
        'revision': revision,
        'synced': synced,
        'target': target,
        'cloudReadbackVersion': 1
      };
  static FavoriteEntry fromMap(Map m) {
    final entry = FavoriteEntry(restoreSong(m['song'] as Map),
        selected: m['selected'] == true,
        owner: m['owner'] as String? ?? '',
        revision: m['revision'] as int? ?? 0,
        synced: m['synced'] as int? ?? -1,
        target: m['target'] as String? ?? 'auto');
    if (sourceOf(entry.song) == MusicSource.qq &&
        m['cloudReadbackVersion'] != 1 &&
        !entry.pending) {
      entry.synced = -1;
    }
    return entry;
  }
}

/// Pending local operations win; complete snapshots reconcile cloud changes.
class UnifiedLibrary extends ChangeNotifier {
  UnifiedLibrary(this.box, {Map<MusicSource, FavoritesRemote>? remotes})
      : remotes = remotes ??
            {
              MusicSource.netease: NeteaseFavoritesRemote(box),
              MusicSource.qq: QqFavoritesRemote(QqMusic.instance, box: box)
            } {
    for (final raw in box.get(storageKey, defaultValue: <dynamic>[]) as List) {
      try {
        final item = FavoriteEntry.fromMap(raw as Map);
        entries[sourceKey(item.song)] = item;
      } catch (_) {}
    }
  }
  static bool peekContains(MediaItem song) =>
      GetIt.I.isRegistered<UnifiedLibrary>() &&
      GetIt.I<UnifiedLibrary>().contains(song);
  static const storageKey = 'BUYU_MIXED_FAVORITES_V1';
  static UnifiedLibrary get instance {
    if (!GetIt.I.isRegistered<UnifiedLibrary>())
      GetIt.I.registerSingleton<UnifiedLibrary>(UnifiedLibrary(GetIt.I<Box>()),
          dispose: (l) => l.dispose());
    return GetIt.I<UnifiedLibrary>();
  }

  final Box box;
  final Map<MusicSource, FavoritesRemote> remotes;
  final Map<String, FavoriteEntry> entries = {};
  Future<void>? _running;
  final Map<MusicSource, Future<void>> _sourceRuns = {};
  bool _disposed = false;
  bool _changingTarget = false;
  bool get changingTarget => _changingTarget;
  FavoriteTargets get targets => FavoriteTargets(box);
  String _target(MusicSource source) =>
      targets.token(source, remotes[source]!.account);
  bool _again = false;
  Future<void>? _pulling;
  Future<void>? _reconciling;
  DateTime? lastCheckedAt;
  bool get hasRetryableWork =>
      readErrors.keys.any((s) => remotes[s]!.account.isNotEmpty) ||
      entries.values.any((entry) {
        final account = remotes[sourceOf(entry.song)]!.account;
        return entry.pending &&
            entry.target == _target(sourceOf(entry.song)) &&
            account.isNotEmpty &&
            (entry.owner.isEmpty || entry.owner == account);
      });

  Future<void> reconcile() => _reconciling ??= _reconcile();
  Future<void> _reconcile() async {
    // Assign before the first notification, and always clear after completion.
    await Future<void>.value();
    try {
      if (_disposed) return;
      await refreshFromCloud();
      if (!_disposed) await sync();
      lastCheckedAt = DateTime.now();
    } finally {
      _reconciling = null;
      _notify();
    }
  }

  bool get refreshing => _pulling != null;
  final Map<MusicSource, String> readErrors = {};
  Future<void> refreshFromCloud() {
    if (_changingTarget) return Future<void>.value();
    if (_pulling != null) return _pulling!;
    final done = Completer<void>();
    _pulling = done.future;
    _notify();
    () async {
      try {
        await Future.wait(MusicSource.values.map((source) async {
          final remote = remotes[source]!;
          final bound = remote.account;
          readErrors.remove(source);
          if (bound.isEmpty || remote is! FavoritesReader) return;
          try {
            final before = entries.map((key, value) => MapEntry(key, (
                  entry: value,
                  revision: value.revision,
                  pending: value.pending
                )));
            final snapshot = remote is FavoritesSnapshotReader
                ? await (remote as FavoritesSnapshotReader)
                    .readSnapshot()
                    .timeout(const Duration(seconds: 90))
                : null;
            final songs = snapshot?.songs ??
                await (remote as FavoritesReader)
                    .readFavorites()
                    .timeout(const Duration(seconds: 90));
            if (remote.account != bound || _disposed)
              throw const MusicServiceError('账号已切换，忽略旧收藏数据');
            final inserted = <String, FavoriteEntry>{};
            final previous = <String, FavoriteEntry?>{};
            for (final song in songs) {
              if (sourceOf(song) != source) continue;
              final key = sourceKey(song), prior = entries[sourceKey(song)];
              final captured = before[key];
              if (!identical(prior, captured?.entry) ||
                  captured?.pending == true) continue;
              // A user's queued add/remove and a different account always win over a cloud read.
              if (prior != null &&
                  (prior.pending ||
                      prior.owner.isNotEmpty && prior.owner != bound)) continue;
              if (prior?.selected == true) continue;
              final entry = FavoriteEntry(song,
                  owner: bound,
                  revision: 0,
                  synced: 0,
                  target: _target(source));
              previous[key] = prior;
              inserted[key] = entry;
              entries[key] = entry;
            }
            if (snapshot != null) {
              for (final item in before.entries) {
                final prior = entries[item.key], captured = item.value;
                if (prior == null ||
                    !identical(prior, captured.entry) ||
                    captured.pending ||
                    prior.pending ||
                    prior.revision != captured.revision ||
                    !prior.selected ||
                    sourceOf(prior.song) != source ||
                    prior.owner != bound ||
                    prior.target != _target(source)) continue;
                FavoriteEntry? replacement;
                if (!snapshot.playlistExists) {
                  // A missing entire playlist is repaired, never interpreted as mass deletion.
                  replacement = FavoriteEntry(prior.song,
                      owner: bound,
                      target: prior.target,
                      revision: prior.revision + 1,
                      synced: prior.synced);
                } else if (!snapshot.keys.contains(item.key)) {
                  replacement = FavoriteEntry(prior.song,
                      selected: false,
                      owner: bound,
                      target: prior.target,
                      revision: prior.revision,
                      synced: prior.synced);
                }
                if (replacement != null) {
                  previous[item.key] = prior;
                  inserted[item.key] = replacement;
                  entries[item.key] = replacement;
                }
              }
            }
            try {
              await _persist();
            } catch (_) {
              for (final item in inserted.entries) {
                if (identical(entries[item.key], item.value)) {
                  final prior = previous[item.key];
                  if (prior == null) {
                    entries.remove(item.key);
                  } else {
                    entries[item.key] = prior;
                  }
                }
              }
              rethrow;
            }
          } catch (e) {
            readErrors[source] = e is MusicServiceError
                ? e.message
                : '${source.label}收藏读取失败，将自动重试';
          }
          _notify();
        }));
      } finally {
        _pulling = null;
        _notify();
        done.complete();
      }
    }();
    return done.future;
  }

  bool get syncing => _running != null;
  int get pendingCount => entries.values.where((e) => e.pending).length;
  List<MediaItem> get songs =>
      entries.values.where((e) => e.selected).map((e) => e.song).toList();
  bool contains(MediaItem song) => entries[sourceKey(song)]?.selected == true;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _saving = Future<void>.value();
  Future<void> _persist() {
    final result = _saving.then((_) =>
        box.put(storageKey, entries.values.map((e) => e.toMap()).toList()));
    _saving = result.catchError((Object _) {});
    return result;
  }

  Future<List<SourcePlaylist>> targetOptions(MusicSource source) async {
    final remote = remotes[source]!;
    final bound = remote.account;
    if (bound.isEmpty) throw MusicServiceError('请先登录${source.label}');
    if (remote is! FavoritesTargetProvider)
      throw const MusicServiceError('此来源暂不支持选择歌单');
    final lists = await (remote as FavoritesTargetProvider).targetOptions();
    if (remote.account != bound) throw const MusicServiceError('账号已切换，请重新选择');
    return lists;
  }

  Future<void> changeTarget(MusicSource source, SourcePlaylist? list,
      {required bool mergeCurrent}) async {
    if (_changingTarget) throw const MusicServiceError('正在切换收藏歌单，请稍候');
    final remote = remotes[source]!, bound = remotes[source]!.account;
    if (bound.isEmpty) throw MusicServiceError('请先登录${source.label}');
    if (list != null && list.source != source)
      throw const MusicServiceError('歌单来源不一致');
    if (list != null &&
        !(await targetOptions(source))
            .any((p) => p.id == list.id && p.directory == list.directory)) {
      throw const MusicServiceError('请选择当前账号自己创建的普通歌单');
    }
    if (remote.account != bound) throw const MusicServiceError('账号已切换');
    if (mergeCurrent) {
      await refreshFromCloud();
      if (readErrors.containsKey(source))
        throw MusicServiceError(readErrors[source]!);
    }
    if (_changingTarget || remote.account != bound)
      throw const MusicServiceError('账号或歌单正在切换，请重试');
    _changingTarget = true;
    _notify();
    try {
      if (_running != null) await _running;
      if (_pulling != null) await _pulling;
      await Future.wait(_sourceRuns.values.toList());
      await _saving;
      if (remote.account != bound || _disposed)
        throw const MusicServiceError('账号已切换');
      final token = list?.id ?? 'auto';
      if (_target(source) == token) return;
      final copies =
          entries.map((k, v) => MapEntry(k, FavoriteEntry.fromMap(v.toMap())));
      for (final entry in copies.values) {
        if (sourceOf(entry.song) != source ||
            entry.owner.isNotEmpty && entry.owner != bound) continue;
        // Never replay an old playlist's removals into the newly selected one.
        entry.synced = entry.revision;
        if (mergeCurrent && entry.selected) {
          entry.owner = bound;
          entry.target = token;
          entry.revision++;
        }
      }
      await box.putAll({
        FavoriteTargets.storageKey: targets.withTarget(source, bound, list),
        storageKey: copies.values.map((e) => e.toMap()).toList()
      });
      entries
        ..clear()
        ..addAll(copies);
      readErrors.remove(source);
    } finally {
      _changingTarget = false;
      _notify();
    }
    await reconcile();
  }

  Future<void> setFavorite(MediaItem song, bool value) async {
    if (_changingTarget) throw const MusicServiceError("正在切换收藏歌单，请稍后操作");
    if (song.id.isEmpty || isLocalSong(song)) return;
    final key = sourceKey(song);
    final prior = entries[key];
    if (prior?.selected == value) return;
    final entry = FavoriteEntry(song,
        selected: value,
        owner: prior?.owner ?? '',
        revision: (prior?.revision ?? -1) + 1,
        synced: prior?.synced ?? -1,
        target: _target(sourceOf(song)));
    // Capture the intended account at the user's action, never on a later account switch.
    final current = remotes[sourceOf(song)]!.account;
    if (entry.owner.isEmpty && current.isNotEmpty) entry.owner = current;
    entries[key] = entry;
    try {
      await _persist();
    } catch (_) {
      if (identical(entries[key], entry)) {
        if (prior == null) {
          entries.remove(key);
        } else {
          entries[key] = prior;
        }
      }
      _notify();
      throw const MusicServiceError('本地收藏保存失败，请检查存储空间后重试');
    }
    _notify();
    unawaited(sync());
  }

  Future<void> sync() {
    if (_changingTarget) return Future<void>.value();
    if (_running != null) {
      _again = true;
      // A slow source must not hold up a new operation on the other platform.
      unawaited(_sync());
      return _running!;
    }
    final done = Completer<void>();
    _running = done.future;
    _notify();
    () async {
      try {
        do {
          _again = false;
          await _sync();
        } while (_again && !_disposed);
      } catch (_) {
        for (final entry in entries.values.where((e) => e.pending)) {
          entry.error = '收藏同步中断，将自动重试；请检查存储空间';
        }
      } finally {
        _running = null;
        _notify();
        done.complete();
      }
    }();
    return done.future;
  }

  Future<void> _sync() async {
    await Future.wait(MusicSource.values.map(_startSource));
  }

  Future<void> _startSource(MusicSource source) {
    if (_sourceRuns.containsKey(source)) return _sourceRuns[source]!;
    final done = Completer<void>();
    _sourceRuns[source] = done.future;
    () async {
      try {
        await _syncSource(source);
      } catch (_) {
        for (final entry in entries.values
            .where((e) => sourceOf(e.song) == source && e.pending)) {
          entry.error = '${source.label}同步中断，将自动重试';
        }
      } finally {
        _sourceRuns.remove(source);
        _notify();
        done.complete();
      }
    }();
    return done.future;
  }

  Future<void> _syncSource(MusicSource source) async {
    final remote = remotes[source]!;
    final account = remote.account;
    final pending = entries.values
        .where((e) => sourceOf(e.song) == source && e.pending)
        .toList();
    if (pending.isEmpty) return;
    if (account.isEmpty) {
      for (final e in pending) e.error = '等待登录${source.label}';
      _notify();
      return;
    }
    final eligible = pending.where((entry) {
      if (entry.target != _target(source)) return false;
      if (entry.owner.isNotEmpty && entry.owner != account) {
        entry.error = '属于其他${source.label}账号，未同步';
        return false;
      }
      entry.owner = account;
      return true;
    }).toList();
    if (eligible.isEmpty) return;
    await _persist();
    if (_disposed || remote.account != account) return;
    // Resolve once per source, including failures; do not repeat a failed
    // playlist lookup once for every pending song while offline.
    final playlist =
        await remote.ensurePlaylist().timeout(const Duration(seconds: 60));
    for (final captured in eligible) {
      var entry = entries[sourceKey(captured.song)];
      while (entry != null && entry.pending && !_disposed) {
        if (remote.account != account) break;
        if (entry.owner.isNotEmpty && entry.owner != account) {
          entry.error = '属于其他${source.label}账号，未同步';
          break;
        }
        entry.owner = account;
        await _persist();
        final revision = entry.revision;
        final selected = entry.selected;
        try {
          if (remote.account != account)
            throw const MusicServiceError('账号已切换，请使用原账号重试');
          await remote
              .apply(playlist, entry.song, selected)
              .timeout(const Duration(seconds: 90));
          if (remote.account != account)
            throw const MusicServiceError('账号已切换，请使用原账号重试');
          final latest = entries[sourceKey(entry.song)];
          if (identical(latest, entry) && latest!.revision == revision) {
            final previousSynced = entry.synced;
            entry.synced = revision;
            try {
              await _persist();
              entry.error = null;
            } catch (_) {
              entry.synced = previousSynced;
              rethrow;
            }
          }
        } catch (error) {
          entry.error = error is MusicServiceError
              ? error.message
              : '${source.label}同步失败，将自动重试';
          break;
        }
        _notify();
        entry = entries[sourceKey(captured.song)];
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
