import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:get_it/get_it.dart';
import 'package:get/get.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../common/constants/enmu.dart';
import '../../common/constants/key.dart';
import '../../common/constants/other.dart';
import '../../common/netease_api/netease_music_api.dart';
import '../../common/netease_api/src/dio_ext.dart';
import '../home/home_controller.dart';
import '../user/user_controller.dart';

class WidePlaylist {
  const WidePlaylist(this.id, this.title, this.artwork);
  final String id;
  final String title;
  final String artwork;
}

class WidePage {
  const WidePage(
      {this.songs = const [], this.playlists = const [], this.hasMore = false});
  final List<MediaItem> songs;
  final List<WidePlaylist> playlists;
  final bool hasMore;
}

class WideQr {
  const WideQr(this.url, this.check);
  final String url;
  final Future<int> Function() check;
}

abstract class WideCatalog {
  Future<WidePage> recommendations();
  Future<WidePage> myPlaylists({int offset = 0});
  Future<WidePage> playlistSongs(String id, {int offset = 0});
  Future<WidePage> search(String keyword, {int offset = 0});
  Future<WidePage> localSongs();
  Future<String?> refreshAccount();
  Future<WideQr> loginQr();
  Future<void> logout();
}

class BujuanWideCatalog implements WideCatalog {
  final _api = NeteaseMusicApi();
  final _details = <String, List<String>>{};

  List<WidePlaylist> _playlists(List<Play> list) => list
      .map((p) =>
          WidePlaylist(p.id, p.name ?? '歌单', p.coverImgUrl ?? p.picUrl ?? ''))
      .toList();

  @override
  Future<WidePage> recommendations() async {
    final result = await _api.personalizedPlaylist(limit: 30);
    return WidePage(playlists: _playlists(result.result ?? []));
  }

  @override
  Future<WidePage> myPlaylists({int offset = 0}) async {
    final id = Home.to.userData.value.profile?.userId;
    if (id == null || Home.to.loginStatus.value != LoginStatus.login) {
      throw StateError('请先在账号页面扫码登录');
    }
    final result = await _api.userPlayList(id, offset: offset, limit: 30);
    final list = result.playlist ?? [];
    return WidePage(playlists: _playlists(list), hasMore: list.length == 30);
  }

  @override
  Future<WidePage> playlistSongs(String id, {int offset = 0}) async {
    if (!_details.containsKey(id)) {
      final result = await _api.playListDetail(id);
      _details[id] = result.playlist?.trackIds?.map((e) => e.id).toList() ?? [];
    }
    final all = _details[id]!;
    if (offset >= all.length) return const WidePage();
    final end = (offset + 50).clamp(0, all.length);
    final result = await _api.songDetail(all.sublist(offset, end));
    return WidePage(
        songs: OtherUtils.song2ToMedia(result.songs ?? []),
        hasMore: end < all.length);
  }

  @override
  Future<WidePage> search(String keyword, {int offset = 0}) async {
    // Empty searches omit `songs`; tolerate this instead of parsing a required list.
    final response = await Https.dioProxy.postUri(
        _api.searchSongDioMetaData(keyword, offset: offset, limit: 30));
    final json = response.data as Map<String, dynamic>;
    if (json['code'] != 200) throw StateError('搜索失败，请稍后重试');
    final result = json['result'] as Map<String, dynamic>? ?? {};
    final songs = (result['songs'] as List? ?? [])
        .map((e) => Song.fromJson(Map<String, dynamic>.from(e)))
        .map((s) => MediaItem(
              id: s.id,
              title: s.name ?? '',
              artist: s.artists?.map((a) => a.name).join(' / '),
              album: s.album?.name,
              duration: Duration(milliseconds: s.duration ?? 0),
              artUri: Uri.tryParse(s.album?.picUrl ?? ''),
              extras: {
                'type': MediaType.playlist.name,
                'image': s.album?.picUrl ?? '',
                'liked': false
              },
            ))
        .toList();
    final total = result['songCount'] as int? ?? offset + songs.length;
    return WidePage(
        songs: songs,
        hasMore: songs.isNotEmpty && offset + songs.length < total);
  }

  @override
  Future<WidePage> localSongs() async {
    final query = GetIt.instance<OnAudioQuery>();
    final device = await query.queryDeviceInfo();
    final permission =
        device.version >= 33 ? Permission.audio : Permission.storage;
    if (!(await permission.request()).isGranted) {
      throw StateError('未获得音频读取权限，可重新选择本地音乐授权');
    }
    final directory = await getExternalStorageDirectory();
    final songs = await query.querySongs();
    return WidePage(
        songs: songs.map((s) {
      final art = directory == null
          ? null
          : File('${directory.path}/albums/${s.albumId}.jpeg');
      return MediaItem(
        id: 'local:${s.id}',
        title: s.title,
        artist: s.artist,
        album: s.album,
        duration: Duration(milliseconds: s.duration ?? 0),
        artUri: art?.existsSync() == true ? Uri.file(art!.path) : null,
        extras: {
          'type': MediaType.local.name,
          'url': s.data,
          'image': art?.existsSync() == true ? art!.path : '',
          'liked': false
        },
      );
    }).toList());
  }

  @override
  Future<String?> refreshAccount() async {
    final result = await _api.loginAccountInfo();
    if (result.code != 200 || result.profile == null) return null;
    Home.to.userData.value = result;
    Home.to.loginStatus.value = LoginStatus.login;
    await Home.to.box.put(loginData, jsonEncode(result.toJson()));
    try {
      final liked = await _api.likeSongList(result.profile!.userId);
      Home.to.likeIds.assignAll(liked.ids);
    } catch (_) {
      /* A favorite-list failure must not undo a successful login. */
    }
    return result.profile?.nickname ?? '网易云用户';
  }

  @override
  Future<WideQr> loginQr() async {
    final key = await _api.loginQrCodeKey();
    if (key.code != 200) throw StateError('二维码获取失败，请重试');
    return WideQr(_api.loginQrCodeUrl(key.unikey), () async {
      final response = await _api.loginQrCodeCheck(key.unikey);
      return response.code;
    });
  }

  @override
  Future<void> logout() async {
    final result = await _api.logout();
    if (result.code != 200) throw StateError('退出登录失败，请重试');
    Home.to.loginStatus.value = LoginStatus.noLogin;
    Home.to.userData.value = NeteaseAccountInfoWrap();
    Home.to.likeIds.clear();
    await Home.to.box.put(loginData, '');
  }
}
