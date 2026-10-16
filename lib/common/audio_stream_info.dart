// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'audio_quality.dart';

class AudioStreamInfo {
  const AudioStreamInfo(this.format, this.sampleRate, this.channels,
      {this.bits, this.frameBitrate});
  final String format;
  final int sampleRate, channels;
  final int? bits, frameBitrate;

  String get description => [
        format,
        if (bits != null) '$bits bit',
        '${sampleRate / 1000} kHz',
        '$channels 声道',
        if (frameBitrate != null) '帧码率 ${frameBitrate! ~/ 1000} kbps',
      ].join(' · ');

  // FLAC STREAMINFO, RFC 9639 section 8.2; read the original file bytes.
  static AudioStreamInfo? parse(List<int> bytes) {
    var start = id3Length(bytes);
    if (start >= bytes.length) return null;
    bool magic(int offset, String text) =>
        offset + text.length <= bytes.length &&
        List.generate(text.length, (i) => bytes[offset + i]).join(',') ==
            text.codeUnits.join(',');
    if (magic(start, 'fLaC') &&
        bytes.length >= start + 42 &&
        bytes[start + 4] & 0x7f == 0 &&
        (bytes[start + 5] << 16 | bytes[start + 6] << 8 | bytes[start + 7]) ==
            34) {
      final p = start + 18;
      final rate = bytes[p] << 12 | bytes[p + 1] << 4 | bytes[p + 2] >> 4;
      final channels = ((bytes[p + 2] >> 1) & 7) + 1;
      final bits = ((bytes[p + 2] & 1) << 4 | bytes[p + 3] >> 4) + 1;
      if (rate > 0 && bits >= 4)
        return AudioStreamInfo('FLAC', rate, channels, bits: bits);
    }
    // A valid Layer III header followed by another compatible frame avoids
    // mistaking arbitrary tag/image bytes for MP3 audio.
    for (; start + 4 < bytes.length; start++) {
      AudioStreamInfo? header(int at) {
        if (at + 4 > bytes.length ||
            bytes[at] != 255 ||
            bytes[at + 1] & 224 != 224) return null;
        final version = (bytes[at + 1] >> 3) & 3;
        if (version == 1 || (bytes[at + 1] >> 1) & 3 != 1) return null;
        final index = bytes[at + 2] >> 4;
        final rateIndex = (bytes[at + 2] >> 2) & 3;
        if (index == 0 || index == 15 || rateIndex == 3) return null;
        final rate = [44100, 48000, 32000][rateIndex] ~/
            (version == 3
                ? 1
                : version == 2
                    ? 2
                    : 4);
        final br = (version == 3
                ? [
                    0,
                    32,
                    40,
                    48,
                    56,
                    64,
                    80,
                    96,
                    112,
                    128,
                    160,
                    192,
                    224,
                    256,
                    320
                  ]
                : [
                    0,
                    8,
                    16,
                    24,
                    32,
                    40,
                    48,
                    56,
                    64,
                    80,
                    96,
                    112,
                    128,
                    144,
                    160
                  ])[index] *
            1000;
        return AudioStreamInfo('MP3', rate, bytes[at + 3] >> 6 == 3 ? 1 : 2,
            frameBitrate: br);
      }

      final first = header(start);
      if (first == null) continue;
      final version = (bytes[start + 1] >> 3) & 3;
      final length =
          (version == 3 ? 144 : 72) * first.frameBitrate! ~/ first.sampleRate +
              ((bytes[start + 2] >> 1) & 1);
      final next = header(start + length);
      if (next?.sampleRate == first.sampleRate) return first;
    }
    return null;
  }

  static int id3Length(List<int> bytes) {
    if (bytes.length < 10 || bytes[0] != 73 || bytes[1] != 68 || bytes[2] != 51)
      return 0;
    if (bytes.sublist(6, 10).any((v) => v & 128 != 0)) return 0;
    return 10 +
        (bytes[6] << 21 | bytes[7] << 14 | bytes[8] << 7 | bytes[9]) +
        (bytes[3] == 4 && bytes[5] & 16 != 0 ? 10 : 0);
  }
}

class AudioQualityReport {
  const AudioQualityReport(
      {required this.songId,
      required this.title,
      required this.requested,
      this.returnedLevel,
      this.bitrate,
      this.size,
      this.serverFormat,
      this.stream,
      this.checked = false,
      this.error,
      this.local = false,
      this.trial = false});
  final String songId, title;
  final AudioQuality requested;
  final String? returnedLevel, serverFormat, error;
  final int? bitrate, size;
  final AudioStreamInfo? stream;
  final bool checked, local, trial;

  AudioQualityReport verified(AudioStreamInfo? info, {String? error}) =>
      AudioQualityReport(
          songId: songId,
          title: title,
          requested: requested,
          returnedLevel: returnedLevel,
          bitrate: bitrate,
          size: size,
          serverFormat: serverFormat,
          stream: info,
          checked: true,
          error: error,
          local: local,
          trial: trial);

  String get returnedLabel {
    for (final quality in AudioQuality.values) {
      if (quality.name == returnedLevel) return quality.label;
    }
    return returnedLevel ?? '接口未提供';
  }

  String get description => [
        title,
        if (local)
          '本地 / 缓存文件，保持原文件音质'
        else ...[
          '设置：${requested.label}；接口标记：$returnedLabel',
          if (returnedLevel != null)
            returnedLevel == requested.name ? '接口标记与设置一致' : '接口标记与设置不同，以文件头核验结果为准',
          if (trial) '接口返回试听片段',
          if (bitrate != null && bitrate! > 0) '接口码率：${bitrate! ~/ 1000} kbps',
          if (size != null && size! > 0)
            '文件大小：${(size! / 1048576).toStringAsFixed(2)} MB',
        ],
        if (stream != null)
          '文件头核验：${stream!.description}'
        else if (!checked)
          '正在核验实际播放文件…'
        else
          error ?? '文件头暂无法核验，不能确认实际音频规格',
      ].join('\n');
}

/// Reads at most two small ranges, without saving or downloading a full song.
/// It probes the exact URI successfully loaded by the player, not a fresh lookup.
class AudioStreamProbe {
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  void close() => _client.close(force: true);

  Future<AudioStreamInfo?> inspect(String source) async {
    Future<List<int>> read(int offset) async {
      final uri = Uri.parse(source);
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        final file =
            await File(uri.scheme == 'file' ? uri.toFilePath() : source).open();
        try {
          await file.setPosition(offset);
          return await file.read(65536);
        } finally {
          await file.close();
        }
      }
      final request =
          await _client.getUrl(uri).timeout(const Duration(seconds: 8));
      request.headers
          .set(HttpHeaders.rangeHeader, 'bytes=$offset-${offset + 65535}');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response =
          await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != 206 &&
          !(offset == 0 && response.statusCode == 200)) {
        throw const HttpException('音频片段读取失败');
      }
      if (response.statusCode == 206 &&
          !(response.headers.value(HttpHeaders.contentRangeHeader) ?? '')
              .startsWith('bytes $offset-')) {
        throw const HttpException('音频片段位置不符');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 8))) {
        builder.add(chunk.take(65536 - builder.length).toList());
        if (builder.length >= 65536) break;
      }
      return builder.takeBytes();
    }

    final prefix = await read(0);
    final skip = AudioStreamInfo.id3Length(prefix);
    return AudioStreamInfo.parse(
        skip >= prefix.length && skip < 16777216 ? await read(skip) : prefix);
  }
}
