// Community maintenance and new features: tiancaiProgramer.
import '../music/playlist_source_filter.dart';

/// Only homepage entries are hidden; local collections and login stay available.
class HomeAccountVisibility {
  const HomeAccountVisibility(
      {required this.hideUnlogged,
      required this.neteaseLoggedIn,
      required this.qqLoggedIn});
  final bool hideUnlogged, neteaseLoggedIn, qqLoggedIn;
  bool get showNetease => !hideUnlogged || neteaseLoggedIn;
  bool get showQq => !hideUnlogged || qqLoggedIn;
  bool get showDiscovery => !hideUnlogged || neteaseLoggedIn || qqLoggedIn;
  List<PlaylistSource> get sources => [
        PlaylistSource.all,
        if (showQq) PlaylistSource.qq,
        if (showNetease) PlaylistSource.netease,
      ];
  PlaylistSource effectiveSource(PlaylistSource selected) =>
      sources.contains(selected) ? selected : PlaylistSource.all;
}
