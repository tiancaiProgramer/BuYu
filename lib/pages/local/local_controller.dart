import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../common/constants/enmu.dart';

class Local extends GetxController {
  RootIsolateToken get rootIsolateToken => RootIsolateToken.instance!;
  OnAudioQuery query = GetIt.instance<OnAudioQuery>();
  RxBool loading = true.obs;
  RxBool loadingSong = true.obs;
  RxList<AlbumModel> albums = <AlbumModel>[].obs;
  RxList<ArtistModel> artists = <ArtistModel>[].obs;
  RxList<MediaItem> songs = <MediaItem>[].obs;
  Directory? directory;
  late BuildContext context;
  final List<AlbumModel> albumsAll = <AlbumModel>[];
  final List<ArtistModel> artistsAll = <ArtistModel>[];

  @override
  void onReady() {
    super.onReady();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      //不是获取歌曲的
      _getAlbumAndArtists();
    });
  }

  static Local get to => Get.find();

  Future<bool> _requestAudioAccess() async {
    if (!Platform.isAndroid) return query.permissionsRequest();
    final device = await query.queryDeviceInfo();
    final permission =
        device.version >= 33 ? Permission.audio : Permission.storage;
    return (await permission.request()).isGranted;
  }

  Future<void> getLocalSong() async {
    loadingSong.value = true;
    try {
      if (!await _requestAudioAccess()) return;
      directory ??= await getExternalStorageDirectory();
      final type = context.routeData.queryParams.getString('type');
      final id = context.routeData.queryParams.getInt('id');
      final songList = await compute(getSongs,
          IsolateData(rootIsolateToken, query, directory, type: type, id: id));
      if (!isClosed) songs.assignAll(songList);
    } catch (_) {
      debugPrint('Local music query failed');
    } finally {
      if (!isClosed) loadingSong.value = false;
    }
  }

  Future<void> _getAlbumAndArtists() async {
    try {
      directory = await getExternalStorageDirectory();
      if (!await _requestAudioAccess()) return;
      final albumList = await compute(
          getAlbum, IsolateData(rootIsolateToken, query, directory));
      final artistList = await compute(
          getArtists, IsolateData(rootIsolateToken, query, directory));
      if (isClosed) return;
      albumsAll
        ..clear()
        ..addAll(albumList);
      artistsAll
        ..clear()
        ..addAll(artistList);
      albums.assignAll(albumList.take(8));
      artists.assignAll(artistList.take(3));
    } catch (_) {
      debugPrint('Local music library query failed');
    } finally {
      if (!isClosed) loading.value = false;
    }
  }
}

Future<List<AlbumModel>> getAlbum(IsolateData isolateData) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(
      isolateData.rootIsolateToken);
  if (isolateData.directory == null) return [];
  List<AlbumModel> albums = await isolateData.onAudioQuery.queryAlbums();
  Directory directory = Directory('${isolateData.directory?.path}/albums');
  if (!directory.existsSync()) directory.createSync();
  for (var album in albums) {
    File file = File('${directory.path}/${album.id}.jpeg');
    if (!await file.exists()) {
      Uint8List? byteData = await isolateData.onAudioQuery.queryArtwork(
          album.id, ArtworkType.ALBUM,
          size: 300, format: ArtworkFormat.JPEG);
      if (byteData != null) {
        await file.create();
        await file.writeAsBytes(byteData);
      }
    }
  }
  return albums;
}

Future<List<ArtistModel>> getArtists(IsolateData isolateData) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(
      isolateData.rootIsolateToken);
  if (isolateData.directory == null) return [];
  List<ArtistModel> artists = await isolateData.onAudioQuery.queryArtists();
  Directory directory = Directory('${isolateData.directory?.path}/artists');
  if (!directory.existsSync()) directory.createSync();
  for (var artist in artists) {
    File file = File('${directory.path}/${artist.id}.jpeg');
    if (!await file.exists()) {
      Uint8List? byteData = await isolateData.onAudioQuery.queryArtwork(
          artist.id, ArtworkType.ARTIST,
          size: 300, format: ArtworkFormat.JPEG);
      if (byteData != null) {
        await file.create();
        await file.writeAsBytes(byteData);
      }
    }
  }
  return artists;
}

Future<List<MediaItem>> getSongs(IsolateData isolateData) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(
      isolateData.rootIsolateToken);
  if (isolateData.directory == null) return [];
  List<SongModel> songs;
  if (isolateData.type == 'all') {
    songs = await isolateData.onAudioQuery.querySongs();
  } else {
    songs = await isolateData.onAudioQuery.queryAudiosFrom(
        isolateData.type == 'album'
            ? AudiosFromType.ALBUM_ID
            : AudiosFromType.ARTIST_ID,
        isolateData.id ?? 0);
  }
  Directory directory = Directory('${isolateData.directory?.path}/albums');
  return songs
      .map((e) => MediaItem(
          id: 'local:${e.id}',
          duration: Duration(milliseconds: e.duration ?? 0),
          artUri: File('${directory.path}/${e.albumId}.jpeg').existsSync()
              ? Uri.file('${directory.path}/${e.albumId}.jpeg')
              : null,
          extras: {
            'url': e.data,
            'image': File('${directory.path}/${e.albumId}.jpeg').existsSync()
                ? '${directory.path}/${e.albumId}.jpeg'
                : '',
            'liked': false,
            'artist': '',
            'mv': 0,
            'type': MediaType.local.name,
          },
          title: e.title,
          album: e.album,
          artist: e.artist))
      .toList();
}

class IsolateData {
  RootIsolateToken rootIsolateToken;
  OnAudioQuery onAudioQuery;
  Directory? directory;
  int? id;
  String? type;

  IsolateData(this.rootIsolateToken, this.onAudioQuery, this.directory,
      {this.id, this.type});
}
