import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'constants/key.dart';

enum ArtworkKind { wallpaper, splash }

class AppearanceStore {
  AppearanceStore(this.box, {Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationSupportDirectory;

  final Box box;
  final Future<Directory> Function() _directory;

  String key(ArtworkKind kind, bool wide) => kind == ArtworkKind.wallpaper
      ? (wide ? backgroundLandscapeSp : backgroundSp)
      : (wide ? splashBackgroundLandscapeSp : splashBackgroundSp);

  String path(ArtworkKind kind, {bool wide = false}) =>
      (box.get(key(kind, wide), defaultValue: '') as String).trim();

  String resolve(ArtworkKind kind, {required bool wide}) {
    final horizontal = wide ? path(kind, wide: true) : '';
    return horizontal.isNotEmpty ? horizontal : path(kind);
  }

  double blur({bool wide = false}) =>
      (box.get(wide ? backgroundLandscapeBlurSp : backgroundBlurSp,
              defaultValue: 0) as num)
          .toDouble()
          .clamp(0, 10);

  Future<Directory> _managed() async =>
      Directory('${(await _directory()).path}/appearance');

  Future<void> importImage(ArtworkKind kind, String source,
      {bool wide = false, double blur = 0}) async {
    final directory = await _managed();
    await directory.create(recursive: true);
    final old = path(kind, wide: wide);
    final target =
        File('${directory.path}/${kind.name}-${wide ? 'wide' : 'base'}-'
            '${DateTime.now().microsecondsSinceEpoch}.image');
    await File(source).copy(target.path);
    try {
      await box.putAll({
        key(kind, wide): target.path,
        if (kind == ArtworkKind.wallpaper)
          wide ? backgroundLandscapeBlurSp : backgroundBlurSp:
              blur.clamp(0, 10),
      });
    } catch (_) {
      await target.delete();
      rethrow;
    }
    await _removeUnused(old);
  }

  Future<void> clear(ArtworkKind kind, {bool? wide}) async {
    final directions = wide == null ? [false, true] : [wide];
    final old = [
      for (final direction in directions) path(kind, wide: direction)
    ];
    await box.putAll({
      for (final direction in directions) key(kind, direction): '',
      if (kind == ArtworkKind.wallpaper)
        for (final direction in directions)
          direction ? backgroundLandscapeBlurSp : backgroundBlurSp: 0.0,
    });
    for (final file in old) {
      await _removeUnused(file);
    }
  }

  Future<void> _removeUnused(String old) async {
    if (old.isEmpty) return;
    for (final kind in ArtworkKind.values) {
      if (path(kind) == old || path(kind, wide: true) == old) return;
    }
    // Never delete a gallery original or a legacy file outside our own folder.
    final file = File(old);
    if (file.parent.absolute.path != (await _managed()).absolute.path) return;
    if (await file.exists()) await file.delete();
  }

  Future<void> migrate() async {
    final directory = await _managed();
    for (final kind in ArtworkKind.values) {
      for (final wide in [false, true]) {
        final old = path(kind, wide: wide);
        if (old.isEmpty ||
            File(old).parent.absolute.path == directory.absolute.path) {
          continue;
        }
        try {
          if (await File(old).exists()) {
            await importImage(kind, old, wide: wide, blur: blur(wide: wide));
          }
        } on FileSystemException {
          // An inaccessible legacy gallery file must not prevent app startup.
        }
      }
    }
  }
}
