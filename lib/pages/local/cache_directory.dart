// Community maintenance and new features: tiancaiProgramer.

/// Resolve shared storage for both stable and coexist app-specific directories.
String? cacheStorageRoot(String appDirectory) {
  final match =
      RegExp(r'^(.+)/Android/data/[^/]+/files/?$').firstMatch(appDirectory);
  return match?.group(1);
}
