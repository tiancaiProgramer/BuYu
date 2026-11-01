// Community maintenance and new features: tiancaiProgramer.
import 'package:bujuan/common/audio_quality.dart';
import 'package:bujuan/common/requested_audio_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NetEase Hi-Res alias is accepted only for the advertised Hi-Res file',
      () {
    final song = {
      'sq': {'size': 26153114},
      'hr': {'size': 46391367}
    };
    expect(
        matchesRequestedNeteaseResource(
            {'level': 'lossless', 'size': 46391367}, song, AudioQuality.hires),
        isTrue);
    expect(
        matchesRequestedNeteaseResource(
            {'level': 'lossless', 'size': 26153114}, song, AudioQuality.hires),
        isFalse);
    expect(
        matchesRequestedNeteaseResource(
            {'size': 46391367}, song, AudioQuality.lossless),
        isFalse);
  });
  test('missing or empty high quality resources cannot count as an exact match',
      () {
    expect(
        matchesRequestedNeteaseResource({
          'size': 100
        }, {
          'sq': {'size': 100}
        }, AudioQuality.hires),
        isFalse);
    expect(
        matchesRequestedNeteaseResource({
          'size': 0
        }, {
          'hr': {'size': 0}
        }, AudioQuality.hires),
        isFalse);
  });
}
