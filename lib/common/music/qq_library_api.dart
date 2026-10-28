// Community maintenance and new features: tiancaiProgramer.
import 'package:audio_service/audio_service.dart';
import 'music_source.dart';
import 'qq_music.dart';

class QqCommentPage {
  const QqCommentPage(this.comments, this.more, this.cursor);
  final List<Map<String, dynamic>> comments;
  final bool more;
  final String cursor;
}

extension QqLibraryApi on QqMusic {
  bool editablePlaylist(SourcePlaylist list) {
    final directory = int.tryParse(list.directory) ?? 0;
    return directory > 0 && !(directory >= 201 && directory <= 206);
  }

  Future<SourcePlaylist> requireOwned(SourcePlaylist list) async {
    final bound = account;
    final own = (await userPlaylists())
        .where((p) => p.id == list.id && p.directory == list.directory)
        .toList();
    if (account != bound || own.length != 1 || !editablePlaylist(own.single)) {
      throw const MusicServiceError('当前账号不能编辑此歌单');
    }
    return own.single;
  }

  Future<SourcePlaylist> createPlaylist(String name) async {
    name = name.trim();
    if (name.isEmpty || name.length > 20)
      throw const MusicServiceError('歌单名称需为1—20个字符');
    final bound = account;
    final data = await rpc(
        'music.musicasset.PlaylistBaseWrite', 'AddPlaylist', {'dirName': name},
        auth: true, expectedAccount: bound);
    final result = data['result'];
    if (data['retCode'] != 0 || result is! Map || result['tid'] == null)
      throw const MusicServiceError('QQ歌单创建未确认，请刷新检查');
    final lists = await userPlaylists();
    if (account != bound) throw const MusicServiceError('QQ账号已切换，请刷新歌单');
    return lists.firstWhere((p) => p.id == '${result['tid']}',
        orElse: () => throw const MusicServiceError('QQ歌单尚未读回，请刷新检查'));
  }

  Future<void> deletePlaylist(SourcePlaylist list) async {
    final own = await requireOwned(list);
    final bound = account;
    final data = await rpc('music.musicasset.PlaylistBaseWrite', 'DelPlaylist',
        {'dirId': int.parse(own.directory)},
        auth: true, expectedAccount: bound);
    if (data['retCode'] != 0) throw const MusicServiceError('QQ歌单删除未完成');
    final lists = await userPlaylists();
    if (account != bound || lists.any((p) => p.id == own.id))
      throw const MusicServiceError('QQ歌单删除尚未确认，请刷新检查');
  }

  Future<void> renamePlaylist(SourcePlaylist list, String name) async {
    name = name.trim();
    if (name.isEmpty || name.length > 20)
      throw const MusicServiceError('歌单名称需为1—20个字符');
    final own = await requireOwned(list);
    final bound = account;
    final detail = await rpc(
        'music.srfDissInfo.DissInfo',
        'CgiGetDiss',
        {
          'disstid': int.parse(own.id),
          'dirid': int.parse(own.directory),
          'tag': 1,
          'song_begin': 0,
          'song_num': 1,
          'userinfo': 1,
          'orderlist': 1,
          'onlysonglist': 0
        },
        auth: true);
    final info = detail['dirinfo'];
    if (info is! Map ||
        !['desc', 'picurl', 'picurl2', 'vec_tagid', 'dir_show']
            .every(info.containsKey) ||
        info['vec_tagid'] is! List)
      throw const MusicServiceError('QQ未返回完整歌单信息，暂不能安全改名');
    if (account != bound) throw const MusicServiceError('QQ账号已切换');
    final data = await rpc(
        'music.musicasset.PlaylistBaseWrite',
        'EditPlaylist',
        {
          'dirId': int.parse(own.directory),
          'dirName': name,
          'mask': 95,
          'dirDesc': info['desc'],
          'dirPicUrl': info['picurl'],
          'dirPicUrl2': info['picurl2'],
          'taglist': (info['vec_tagid'] as List).join(','),
          'dirShow': info['dir_show']
        },
        auth: true,
        expectedAccount: bound);
    if (data['retCode'] != null && data['retCode'] != 0)
      throw const MusicServiceError('QQ歌单改名未完成');
    final lists = await userPlaylists();
    if (account != bound || !lists.any((p) => p.id == own.id && p.name == name))
      throw const MusicServiceError('QQ歌单新名称尚未读回，请刷新检查');
  }

  Future<void> changePlaylistSong(
      SourcePlaylist list, MediaItem song, bool add) async {
    final bound = account;
    final own = await requireOwned(list);
    await syncFavorite(own, song, add, expectedAccount: bound);
    await userPlaylists();
  }

  Future<QqCommentPage> songComments(MediaItem track,
      {bool hot = true, int page = 1, String cursor = ''}) async {
    final id = '${track.extras?['qqId'] ?? ''}';
    if ((int.tryParse(id) ?? 0) <= 0)
      throw const MusicServiceError('歌曲缺少评论编号，请重新搜索');
    final data = await rpc('music.globalComment.CommentRead',
        hot ? 'GetHotCommentList' : 'GetNewCommentList', {
      'BizType': 1,
      'BizId': id,
      'PageSize': 20,
      'PageNum': page - 1,
      'LastCommentSeqNo': cursor,
      'HotType': 1,
      'WithAirborne': 0,
      'PicEnable': 1,
      if (!hot) 'SelfSeeEnable': 1,
      if (!hot) 'AudioEnable': 1,
    });
    final list = data['CommentList'];
    if (list is! Map ||
        list['Comments'] is! List ||
        (data['SubCode'] is num && data['SubCode'] != 0))
      throw const MusicServiceError('QQ评论暂未返回，请重试');
    final comments = (list['Comments'] as List)
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    return QqCommentPage(
        comments,
        list['HasMore'] == 1 || list['HasMore'] == true,
        comments.isEmpty ? cursor : '${comments.last['SeqNo'] ?? ''}');
  }
}
