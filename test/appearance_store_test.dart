import 'dart:io';
import 'package:bujuan/common/appearance_store.dart';
import 'package:bujuan/common/constants/key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  late Directory directory;
  late Box box;
  late AppearanceStore store;
  late File original;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bujuan-appearance');
    Hive.init(directory.path);
    box = await Hive.openBox('images');
    store = AppearanceStore(box,
        directory: () async => Directory('${directory.path}/support'));
    original = await File('${directory.path}/gallery-original.png')
        .writeAsBytes([1, 2, 3, 4, 5]);
  });
  tearDown(() async {
    await box.close();
    await directory.delete(recursive: true);
  });

  test('one image adapts to both orientations; horizontal image is independent',
      () async {
    await store.importImage(ArtworkKind.wallpaper, original.path, blur: 4);
    final base = store.path(ArtworkKind.wallpaper);
    expect(base, isNot(original.path));
    expect(await File(base).readAsBytes(), await original.readAsBytes());
    expect(store.resolve(ArtworkKind.wallpaper, wide: true), base);
    expect(store.blur(), 4);
    await store.importImage(ArtworkKind.wallpaper, original.path,
        wide: true, blur: 2);
    final horizontal = store.path(ArtworkKind.wallpaper, wide: true);
    expect(store.resolve(ArtworkKind.wallpaper, wide: true), horizontal);
    expect(store.resolve(ArtworkKind.wallpaper, wide: false), base);
    expect(store.blur(wide: true), 2);
    await store.clear(ArtworkKind.wallpaper, wide: true);
    expect(store.resolve(ArtworkKind.wallpaper, wide: true), base);
    expect(await File(horizontal).exists(), isFalse);
    expect(await File(base).exists(), isTrue);
    expect(await original.exists(), isTrue);
  });

  test('startup images and wallpaper do not overwrite or clear each other',
      () async {
    for (final kind in ArtworkKind.values) {
      for (final wide in [false, true]) {
        await store.importImage(kind, original.path, wide: wide);
      }
    }
    final splash = store.path(ArtworkKind.splash);
    final splashWide = store.path(ArtworkKind.splash, wide: true);
    final wall = store.path(ArtworkKind.wallpaper);
    final wallWide = store.path(ArtworkKind.wallpaper, wide: true);
    await store.clear(ArtworkKind.wallpaper);
    expect(await File(wall).exists(), isFalse);
    expect(await File(wallWide).exists(), isFalse);
    expect(store.path(ArtworkKind.splash), splash);
    expect(store.path(ArtworkKind.splash, wide: true), splashWide);
    expect(await File(splash).exists(), isTrue);
    expect(await File(splashWide).exists(), isTrue);
  });

  test('legacy gallery images migrate without deleting originals', () async {
    await box.put(backgroundSp, original.path);
    await box.put(splashBackgroundSp, original.path);
    await store.migrate();
    final saved = store.path(ArtworkKind.wallpaper);
    expect(saved, isNot(original.path));
    expect(await File(saved).readAsBytes(), await original.readAsBytes());
    await store.migrate();
    expect(store.path(ArtworkKind.wallpaper), saved);
    await store.clear(ArtworkKind.wallpaper);
    await store.clear(ArtworkKind.splash);
    expect(await original.exists(), isTrue);
  });

  test('failed import preserves the previous image', () async {
    await store.importImage(ArtworkKind.splash, original.path);
    final saved = store.path(ArtworkKind.splash);
    await expectLater(
        store.importImage(ArtworkKind.splash, '${directory.path}/missing.png'),
        throwsA(isA<FileSystemException>()));
    expect(store.path(ArtworkKind.splash), saved);
    expect(await File(saved).exists(), isTrue);
  });

  test('a file referenced by another image slot is kept until unused',
      () async {
    await store.importImage(ArtworkKind.wallpaper, original.path);
    final shared = store.path(ArtworkKind.wallpaper);
    await box.put(splashBackgroundSp, shared);
    await store.clear(ArtworkKind.wallpaper);
    expect(await File(shared).exists(), isTrue);
    await store.clear(ArtworkKind.splash);
    expect(await File(shared).exists(), isFalse);
  });
}
