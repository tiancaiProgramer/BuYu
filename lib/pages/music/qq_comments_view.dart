import '../../widget/buyu_components.dart';
// Community maintenance and new features: tiancaiProgramer.
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import '../../common/music/qq_music.dart';
import '../../common/music/qq_library_api.dart';
import '../../common/music/music_source.dart';
import '../../widget/simple_extended_image.dart';

class QqCommentsView extends StatefulWidget {
  const QqCommentsView(
      {super.key, required this.song, this.embedded = false, this.color});
  final MediaItem song;
  final bool embedded;
  final Color? color;
  @override
  State<QqCommentsView> createState() => _QqCommentsState();
}

class _QqCommentsState extends State<QqCommentsView> {
  bool hot = true, loading = false, more = true;
  int page = 0, generation = 0;
  String cursor = '', error = '';
  final List<Map<String, dynamic>> comments = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant QqCommentsView old) {
    super.didUpdateWidget(old);
    if (old.song.id != widget.song.id) reset(hot);
  }

  void reset(bool value) {
    generation++;
    setState(() {
      hot = value;
      comments.clear();
      page = 0;
      cursor = '';
      more = true;
      loading = false;
      error = '';
    });
    load();
  }

  Future<void> load() async {
    if (loading || !more) return;
    final request = generation;
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final result = await QqMusic.instance
          .songComments(widget.song, hot: hot, page: page + 1, cursor: cursor);
      if (!mounted || request != generation) return;
      setState(() {
        final ids = comments.map((c) => c['CmId']).toSet();
        comments.addAll(result.comments.where((c) => ids.add(c['CmId'])));
        page++;
        cursor = result.cursor;
        more = result.more && result.comments.isNotEmpty;
      });
    } catch (e) {
      if (mounted && request == generation)
        setState(() => error = e is MusicServiceError ? e.message : 'QQ评论加载失败');
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(children: [
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Wrap(spacing: 8, children: [
            BuYuChoiceChip(
                label: const Text('热评'),
                selected: hot,
                onSelected: (_) => reset(true)),
            BuYuChoiceChip(
                label: const Text('最新'),
                selected: !hot,
                onSelected: (_) => reset(false))
          ])),
      if (loading) const LinearProgressIndicator(),
      Expanded(
          child: ListView(children: [
        for (final c in comments)
          Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      SimpleExtendedImage.avatar('${c['Avatar'] ?? ''}',
                          width: 32),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text('${c['Nick'] ?? 'QQ音乐用户'}',
                              style: TextStyle(color: widget.color))),
                      Text('${c['PraiseNum'] ?? 0} 赞',
                          style: TextStyle(color: widget.color))
                    ]),
                    const SizedBox(height: 10),
                    SelectableText(QqMusic.clean(c['Content']),
                        style: TextStyle(color: widget.color, height: 1.5)),
                    const Divider(),
                  ])),
        if (error.isNotEmpty)
          TextButton(onPressed: load, child: Text('$error · 重试')),
        if (!loading && error.isEmpty && comments.isEmpty)
          const Padding(padding: EdgeInsets.all(20), child: Text('暂无评论')),
        if (more && error.isEmpty)
          TextButton(
              onPressed: loading ? null : load, child: const Text('加载更多')),
      ]))
    ]);
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: Text('${widget.song.title} · QQ评论')),
            body: SafeArea(top: false, child: body));
  }
}
