import 'package:bujuan/pages/home/view/phone_landscape_player.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/common/lyric_parser/lyrics_reader_model.dart';
import 'package:bujuan/pages/wide/wide_playback.dart';
import 'package:bujuan/pages/wide/wide_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'wide_remote_test.dart' as fixture;
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/display_mode.dart';
import 'package:bujuan/pages/tv/tv_player.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

void main() {
  test('artwork uses the alternate media URI and normalizes local file URIs',
      () {
    expect(
        TvArtwork.forSong(MediaItem(
            id: '1',
            title: '封面',
            artUri: Uri.parse('https://example.test/cover.jpg'),
            extras: const {'image': ''})),
        'https://example.test/cover.jpg');
    expect(
        TvArtwork.forSong(MediaItem(
            id: '1', title: '封面', artUri: Uri.file('/tmp/album art.jpg'))),
        '/tmp/album art.jpg');
    expect(
        TvArtwork.forSong(const MediaItem(
            id: '1', title: '封面', extras: {'image': '/tmp/preferred.jpg'})),
        '/tmp/preferred.jpg');
    expect(
        DisplayMode.overlayForBackground(AppTheme.light.scaffoldBackgroundColor)
            .statusBarIconBrightness,
        Brightness.dark);
    expect(
        DisplayMode.overlayForBackground(AppTheme.dark.scaffoldBackgroundColor)
            .statusBarIconBrightness,
        Brightness.light);
  });

  testWidgets('network artwork retains image headers and thumbnail query',
      (tester) async {
    await fixture.mount(
        tester,
        const TvArtwork(
            url: 'https://p1.music.126.net/cover.jpg?param=300y300',
            size: 120));
    final network =
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(network.httpHeaders!['User-Agent'], contains('Mozilla/5.0'));
    expect(
        network.imageUrl, 'https://p1.music.126.net/cover.jpg?param=300y300');
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape cover actually paints a local media artwork URI',
      (tester) async {
    final file = await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('bujuan-cover');
      final bytes = await rootBundle.load('assets/images/logo.png');
      return File('${directory.path}/cover.png')
          .writeAsBytes(bytes.buffer.asUint8List());
    });
    final model = fixture.playback();
    model.value = WidePlaybackData(
        song: MediaItem(
            id: 'cover', title: '封面测试', artUri: file!.uri, artist: '歌手'));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      await tester.runAsync(() => file.parent.delete(recursive: true));
    });
    await tester.runAsync(() async {
      await fixture.mount(
          tester, PhoneLandscapePlayer(playback: model, perform: (a) => a()),
          size: const Size(770, 300));
      final image = tester.widget<Image>(find.byType(Image));
      await precacheImage(image.image, tester.element(find.byType(Image)))
          .timeout(const Duration(seconds: 10));
    });
    expect(tester.widget<TvArtwork>(find.byType(TvArtwork)).url, file.path);
    final image = tester.widget<Image>(find.byType(Image));
    expect(((image.image as ResizeImage).imageProvider as FileImage).file.path,
        file.path);
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(tester.getSize(find.byType(Image)).height, greaterThan(80));
    expect(tester.takeException(), isNull);
  });
  for (final size in [const Size(770, 282), const Size(588, 240)]) {
    testWidgets('song controls stay left and lyrics use full height at $size',
        (tester) async {
      var toggles = 0;
      Duration? sought;
      final model =
          fixture.playback(toggle: () => toggles++, seek: (p) => sought = p);
      model.value = WidePlaybackData(
          song: fixture.song,
          lyrics: List.generate(
              12,
              (i) => LyricsLineModel()
                ..startTime = i * 5000
                ..mainText = '一段足够长的歌词文字会正确换行显示 $i'
                ..extText = '翻译歌词'),
          position: const Duration(seconds: 10));
      addTearDown(model.dispose);
      await fixture.mount(
          tester,
          Theme(
              data: AppTheme.light,
              child: Scaffold(
                  body: PhoneLandscapePlayer(
                      playback: model, perform: (a) => a()))),
          size: size);
      final song =
          tester.getRect(find.byKey(const ValueKey('phone-player-song')));
      final lyrics =
          tester.getRect(find.byKey(const ValueKey('phone-player-lyrics')));
      expect(song.right, lessThan(lyrics.left));
      expect(lyrics.height, greaterThan(size.height - 20));
      final toggle = find.byKey(const ValueKey('control:toggle'));
      expect(tester.getRect(toggle).right, lessThan(lyrics.left));
      expect(tester.getRect(find.byKey(const ValueKey('control:收藏'))).right,
          lessThan(lyrics.left));
      await tester.tap(toggle);
      await tester.pump();
      expect(toggles, 1);
      final list = tester.widget<ListView>(find.descendant(
          of: find.byType(WideLyrics), matching: find.byType(ListView)));
      expect(list.itemExtent, 68);
      await tester.tap(find.byKey(const ValueKey('lyric:1:2')));
      await tester.pump();
      expect(sought, const Duration(seconds: 10));
      await tester.drag(find.byType(Slider), const Offset(50, 0));
      await tester.pump(const Duration(milliseconds: 180));
      expect(sought, greaterThan(const Duration(seconds: 10)));
      expect(tester.takeException(), isNull);
    });
  }
}
