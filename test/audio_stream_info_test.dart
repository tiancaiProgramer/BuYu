import 'dart:io';
import 'dart:typed_data';
import 'package:bujuan/common/audio_quality.dart';
import 'package:bujuan/common/audio_stream_info.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List flacHeader({int rate = 96000, int bits = 24}) {
  final bytes = Uint8List(42);
  bytes.setAll(0, 'fLaC'.codeUnits);
  bytes[4] = 128;
  bytes[7] = 34;
  final value = (BigInt.from(rate) << 44) | (BigInt.one << 41) |
      (BigInt.from(bits - 1) << 36) | BigInt.from(rate * 180);
  for (var i = 0; i < 8; i++) {
    bytes[18 + i] = ((value >> (56 - i * 8)) & BigInt.from(255)).toInt();
  }
  return bytes;
}

void main() {
  test('FLAC STREAMINFO identifies 24 bit / 96 kHz and CD format independently', () {
    final hires = AudioStreamInfo.parse(flacHeader())!;
    expect((hires.format, hires.sampleRate, hires.bits, hires.channels), ('FLAC', 96000, 24, 2));
    final cd = AudioStreamInfo.parse(flacHeader(rate: 44100, bits: 16))!;
    expect((cd.sampleRate, cd.bits), (44100, 16));
    expect(AudioStreamInfo.parse('not an audio file'.codeUnits), isNull);
    expect(AudioStreamInfo.parse(flacHeader().sublist(0, 30)), isNull);
  });

  test('MP3 requires consecutive frames and does not invent PCM bit depth', () {
    final bytes = Uint8List(2100);
    for (final at in [0, 1044]) bytes.setAll(at, [255, 251, 224, 0]);
    final stream = AudioStreamInfo.parse(bytes)!;
    expect((stream.format, stream.sampleRate, stream.frameBitrate, stream.bits), ('MP3', 44100, 320000, null));
    bytes[1044] = 0;
    expect(AudioStreamInfo.parse(bytes), isNull);
  });

  test('actual returned level is never inferred from the requested level or suffix', () {
    final report = AudioQualityReport(songId: '1', title: '测试', requested: AudioQuality.hires,
        returnedLevel: 'exhigh', bitrate: 320000).verified(AudioStreamInfo('MP3', 44100, 2, frameBitrate: 320000));
    expect(report.description, contains('设置：Hi-Res；接口标记：极高'));
    expect(report.description, contains('接口标记与设置不同'));
    expect(report.description, contains('文件头核验：MP3'));
    expect(report.description, isNot(contains('24 bit')));
    const unknown = AudioQualityReport(songId: '1', title: '测试', requested: AudioQuality.lossless);
    expect(unknown.returnedLabel, '接口未提供');
    expect(unknown.verified(null).description, contains('不能确认'));
  });

  test('range probe reads the played URI and skips a large ID3 tag', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <String>[];
    final prefix = Uint8List(65536)..setAll(0, [73,68,51,4,0,0,0,4,0,0]);
    server.listen((request) async {
      requests.add('${request.uri} ${request.headers.value('range')}');
      final offset = requests.length == 1 ? 0 : 65546;
      request.response.statusCode = 206;
      final bytes = offset == 0 ? prefix : flacHeader();
      request.response.headers.set('content-range', 'bytes $offset-${offset + bytes.length - 1}/1000000');
      request.response.add(bytes);
      await request.response.close();
    });
    final probe = AudioStreamProbe();
    try {
      final result = await probe.inspect('http://127.0.0.1:${server.port}/same-played-file?token=preserved');
      expect(result!.bits, 24);
      expect(requests, ['/same-played-file?token=preserved bytes=0-65535', '/same-played-file?token=preserved bytes=65546-131081']);
    } finally { probe.close(); await server.close(force: true); }
  });
}
