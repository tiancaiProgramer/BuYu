// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'music_source.dart';

typedef SongSearch = Future<List<MediaItem>> Function(String query, int page);

class MixedSearch extends ChangeNotifier {
  MixedSearch({required this.providers});
  final Map<MusicSource, SongSearch> providers;
  final results = <MusicSource, List<MediaItem>>{};
  final errors = <MusicSource, String>{};
  final busy = <MusicSource>{};
  final pages = <MusicSource, int>{};
  final ended = <MusicSource>{};
  String query = '';
  int _generation = 0;
  bool _disposed = false;
  List<MediaItem> get songs {
    final a = results[MusicSource.netease] ?? <MediaItem>[];
    final b = results[MusicSource.qq] ?? <MediaItem>[];
    return [
      for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) ...[
        if (i < a.length) a[i],
        if (i < b.length) b[i]
      ]
    ];
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> search(String value) async {
    query = value.trim();
    _generation++;
    results.clear();
    errors.clear();
    busy.clear();
    pages.clear();
    ended.clear();
    _notify();
    if (query.isEmpty) return;
    await Future.wait(providers.keys.map(load));
  }

  Future<void> load(MusicSource source) async {
    if (busy.contains(source) || ended.contains(source) || query.isEmpty)
      return;
    final generation = _generation;
    final text = query;
    final page = (pages[source] ?? 0) + 1;
    busy.add(source);
    errors.remove(source);
    _notify();
    try {
      final items = await providers[source]!(text, page)
          .timeout(const Duration(seconds: 18));
      if (_disposed || generation != _generation) return;
      final old = results.putIfAbsent(source, () => []);
      final ids = old.map(sourceKey).toSet();
      old.addAll(items.where((s) => ids.add(sourceKey(s))));
      pages[source] = page;
      if (items.isEmpty) ended.add(source);
    } catch (_) {
      if (generation == _generation && !_disposed)
        errors[source] = '${source.label}暂不可用，点击重试';
    } finally {
      if (generation == _generation && !_disposed) {
        busy.remove(source);
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
