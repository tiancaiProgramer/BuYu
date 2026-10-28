// Community maintenance and new features: tiancaiProgramer.
import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../constants/key.dart';
import '../netease_api/src/netease_api.dart';
import '../netease_api/src/api/play/bean.dart';
import 'music_source.dart';

class NeteaseLibrary {
  NeteaseLibrary(this.box, {NeteaseMusicApi? api}) : _providedApi = api;
  final Box box;
  final NeteaseMusicApi? _providedApi;
  NeteaseMusicApi get api => _providedApi ?? NeteaseMusicApi();
  String get account {
    try {
      final raw = box.get(loginData);
      final data = raw is String ? jsonDecode(raw) : raw;
      return '${data?['profile']?['userId'] ?? ''}';
    } catch (_) {
      return '';
    }
  }

  void checkAccount(String bound) {
    if (bound.isEmpty || account != bound)
      throw const MusicServiceError('网易云账号已切换，请刷新后重试');
  }

  bool owns(Play list) =>
      account.isNotEmpty &&
      (list.creator?.userId ?? list.userId) == account &&
      list.specialType != 5;
  Future<List<Play>> lists() async {
    final bound = account;
    if (bound.isEmpty) throw const MusicServiceError('请先登录网易云');
    final items = <Play>[];
    for (var offset = 0; offset < 10000; offset += 100) {
      final result = await api.userPlayList(bound, offset: offset, limit: 100);
      checkAccount(bound);
      if (result.code != 200) throw const MusicServiceError('网易云歌单读取失败，请重试');
      final page = result.playlist ?? <Play>[];
      items.addAll(page);
      if (page.length < 100) return items;
    }
    throw const MusicServiceError('网易云歌单数量过多，尚未完整读取');
  }

  Future<Play> requireOwned(Play list) async {
    final matches = (await lists()).where((p) => p.id == list.id).toList();
    if (matches.length != 1 || !owns(matches.single))
      throw const MusicServiceError('只能管理当前账号自己创建的普通歌单');
    return matches.single;
  }

  Future<void> create(String name) async {
    name = name.trim();
    if (name.isEmpty || name.length > 40)
      throw const MusicServiceError('歌单名称需为1—40个字符');
    final bound = account;
    checkAccount(bound);
    final result = await api.playlistCreate(name, true);
    checkAccount(bound);
    if (result.code != 200 || result.id.isEmpty)
      throw const MusicServiceError('网易云歌单创建未确认');
    if (!(await lists()).any((p) => p.id == result.id))
      throw const MusicServiceError('新歌单尚未读回，请刷新检查');
  }

  Future<void> rename(Play list, String name) async {
    name = name.trim();
    if (name.isEmpty || name.length > 40)
      throw const MusicServiceError('歌单名称需为1—40个字符');
    final bound = account;
    final own = await requireOwned(list);
    checkAccount(bound);
    final response = await api
        .updateUserPlayListName(own.id, name)
        .timeout(const Duration(seconds: 15));
    checkAccount(bound);
    if (response.code != 200)
      throw MusicServiceError('网易云歌单改名未完成（${response.code}）');
    if (!(await lists()).any((p) => p.id == own.id && p.name == name))
      throw const MusicServiceError('新歌单名称尚未读回，请刷新检查');
  }

  Future<void> delete(Play list) async {
    final bound = account;
    final own = await requireOwned(list);
    checkAccount(bound);
    final result = await api.playlistDelete([own.id]);
    checkAccount(bound);
    if (result.code != 200) throw const MusicServiceError('网易云歌单删除未完成');
    if ((await lists()).any((p) => p.id == own.id))
      throw const MusicServiceError('删除结果尚未确认，请刷新检查');
  }

  static MediaItem song(Song2 value) => MediaItem(
          id: value.id,
          title: value.name ?? '',
          artist: (value.ar ?? []).map((a) => a.name).join(' / '),
          album: value.al?.name,
          duration: Duration(milliseconds: value.dt ?? 0),
          artUri: Uri.tryParse(value.al?.picUrl ?? ''),
          extras: {
            'source': 'netease',
            'type': 'playlist',
            'image': value.al?.picUrl ?? '',
            'liked': false,
            'artist':
                (value.ar ?? []).map((a) => jsonEncode(a.toJson())).join(' / '),
            'album': jsonEncode(value.al?.toJson()),
            'mv': value.mv,
            'fee': value.fee
          });
  Future<List<MediaItem>> favorites() async {
    final bound = account;
    final selected = (await lists())
        .where(
            (p) => owns(p) && (p.name ?? '').trim().toLowerCase() == 'buyu收藏')
        .toList();
    final songs = <String, MediaItem>{};
    for (final list in selected) {
      final result = await api.playListDetail(list.id);
      checkAccount(bound);
      if (result.code != 200 || result.playlist == null)
        throw const MusicServiceError('网易云BuYu收藏读取失败');
      final ids = result.playlist!.trackIds?.map((t) => t.id).toList();
      if (ids == null) {
        if (result.playlist!.trackCount == 0) continue;
        throw const MusicServiceError('网易云未返回完整收藏编号，请重试');
      }
      for (var start = 0; start < ids.length; start += 200) {
        final end = (start + 200).clamp(0, ids.length);
        final detail = await api.songDetail(ids.sublist(start, end));
        checkAccount(bound);
        if (detail.code != 200 || detail.songs == null)
          throw const MusicServiceError('网易云收藏歌曲读取失败');
        final requested = ids.sublist(start, end).toSet();
        for (final value in detail.songs!) {
          if (requested.contains(value.id)) songs[value.id] = song(value);
        }
      }
    }
    return songs.values.toList();
  }
}
