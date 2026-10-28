// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'dart:convert';
import 'package:bujuan/common/constants/key.dart';
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/music/music_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'download_preferences_test.dart' show MemoryBox;
import 'playback_regression_test.dart' show FakePlayer;

const a = MediaItem(id: 'qq:a', title: 'QQ第一首');
const b = MediaItem(id: 'qq:b', title: 'QQ第二首');
const c = MediaItem(id: 'qq:c', title: 'QQ新推荐');
BujuanAudioHandler handler(FakePlayer p, {MemoryBox? box}) =>
    BujuanAudioHandler(
        player: p,
        box: box ?? MemoryBox(),
        restoreQueue: false,
        urlResolver: (s) async => 'https://example.invalid/${s.id}');
void main() {
  test('a failed FM refill can be retried without keeping the failed request',
      () async {
    final player = FakePlayer();
    final audio = handler(player);
    var calls = 0;
    await audio.startRadio('QQ音乐', (_) async {
      calls++;
      if (calls == 1) return [a];
      if (calls == 2) throw const MusicServiceError('暂时断网');
      return [b];
    });
    await audio.skipToNext();
    expect(audio.playbackState.value.processingState, AudioProcessingState.error);
    expect(player.playing, false);
    await audio.skipToNext();
    expect(audio.mediaItem.value?.id, b.id);
    expect(audio.playbackState.value.errorMessage, isNull);
    await audio.play();
    expect(player.playing, true);
    expect(calls, 3);
    await audio.dispose();
  });
  test('FM refills after the batch ends and keeps the playing title aligned',
      () async {
    final audio = handler(FakePlayer());
    var requests = 0;
    await audio.startRadio('QQ音乐', (history) async {
      requests++;
      if (requests == 1) return [a, b];
      expect(history.map((e) => e.id), containsAll(['qq:a', 'qq:b']));
      return [a, c];
    });
    await audio.skipToNext();
    expect(audio.mediaItem.value?.id, 'qq:b');
    await audio.skipToNext();
    expect(audio.mediaItem.value?.id, 'qq:c');
    expect(requests, 2);
    expect(audio.queue.value.map((e) => e.id), ['qq:b', 'qq:c']);
    await audio.dispose();
  });
  test('late FM refill cannot overwrite a manually selected normal queue',
      () async {
    final audio = handler(FakePlayer());
    final pending = Completer<List<MediaItem>>();
    var calls = 0;
    await audio.startRadio(
        'QQ音乐', (_) async => ++calls == 1 ? [a] : await pending.future);
    final next = audio.skipToNext();
    const selected = MediaItem(id: 'netease:normal', title: '手动选择');
    await audio.changeQueueLists([selected]);
    pending.complete([b]);
    await next;
    expect(audio.mediaItem.value?.id, selected.id);
    expect(audio.queue.value, [selected]);
    await audio.dispose();
  });
  test('pause during an FM refill is retained when new songs arrive', () async {
    final player = FakePlayer(), pending = Completer<List<MediaItem>>();
    final box = MemoryBox();
    final audio = handler(player, box: box);
    var calls = 0;
    await audio.startRadio(
        'QQ音乐', (_) async => ++calls == 1 ? [a] : await pending.future);
    final next = audio.skipToNext();
    await audio.pause();
    pending.complete([b]);
    await next;
    expect(player.playing, false);
    expect(audio.mediaItem.value?.id, 'qq:b');
    final saved = (box.get(playQueue) as List)
        .map((value) => jsonDecode(value as String)['id'])
        .toList();
    expect(saved, ['qq:a', 'qq:b']);
    await audio.dispose();
  });
  test('repeated or failed recommendations do not loop old tracks indefinitely',
      () async {
    final audio = handler(FakePlayer());
    var calls = 0;
    await audio.startRadio('QQ音乐', (_) async {
      calls++;
      return [a];
    });
    await audio.skipToNext();
    expect(calls, 3);
    expect(audio.mediaItem.value?.id, 'qq:a');
    expect(
        audio.playbackState.value.processingState, AudioProcessingState.error);
    await audio.dispose();
  });
  test('duplicate next controls share one FM refill request', () async {
    final audio = handler(FakePlayer()), pending = Completer<List<MediaItem>>();
    var calls = 0;
    await audio.startRadio(
        'QQ音乐', (_) async => ++calls == 1 ? [a] : await pending.future);
    final first = audio.skipToNext(), second = audio.skipToNext();
    pending.complete([b]);
    await Future.wait([first, second]);
    expect(calls, 2);
    expect(audio.mediaItem.value?.id, 'qq:b');
    await audio.dispose();
  });
  test('FM automatically refills on natural completion', () async {
    final player = FakePlayer();
    final live = handler(player);
    var calls = 0;
    await live.startRadio('QQ音乐', (_) async => ++calls == 1 ? [a] : [b]);
    player.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(live.mediaItem.value?.id, 'qq:b');
    expect(calls, 2);
    await live.dispose();
  });
  test('a previous-song control cancels a pending FM refill', () async {
    final audio = handler(FakePlayer()), pending = Completer<List<MediaItem>>();
    var calls = 0;
    await audio.startRadio(
        'QQ音乐', (_) async => ++calls == 1 ? [a, b] : await pending.future);
    await audio.skipToNext();
    final next = audio.skipToNext();
    await audio.skipToPrevious();
    pending.complete([c]);
    await next;
    expect(audio.mediaItem.value?.id, 'qq:a');
    expect(audio.queue.value, [a, b]);
    await audio.dispose();
  });
  test('an old pending refill cannot block or erase a newly selected radio',
      () async {
    final audio = handler(FakePlayer()), old = Completer<List<MediaItem>>();
    var calls = 0;
    await audio.startRadio(
        'QQ音乐', (_) async => ++calls == 1 ? [a] : await old.future);
    final pending = audio.skipToNext();
    var newCalls = 0;
    const netA = MediaItem(id: 'netease:a', title: '网易云FM'),
        netB = MediaItem(id: 'netease:b', title: '网易云新歌');
    await audio.startRadio(
        '网易云', (_) async => ++newCalls == 1 ? [netA] : [netB]);
    await audio.skipToNext();
    expect(audio.mediaItem.value?.id, netB.id);
    old.complete([c]);
    await pending;
    expect(audio.mediaItem.value?.id, netB.id);
    await audio.dispose();
  });
}
