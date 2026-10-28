import '../../widget/buyu_components.dart';
// Community maintenance and new features: tiancaiProgramer.
import 'package:flutter/material.dart';

enum PlaylistSource {
  all('合并显示'),
  qq('QQ音乐'),
  netease('网易云');

  const PlaylistSource(this.label);
  final String label;
}

class PlaylistSourceFilter extends StatelessWidget {
  const PlaylistSourceFilter(
      {super.key,
      required this.value,
      required this.onChanged,
      this.sources = PlaylistSource.values});
  final PlaylistSource value;
  final List<PlaylistSource> sources;
  final ValueChanged<PlaylistSource> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(spacing: 8, children: [
        for (final source in sources)
          BuYuChoiceChip(
              key: ValueKey('playlist-source:${source.name}'),
              label: Text(source.label),
              selected: source == value,
              onSelected: (_) => onChanged(source))
      ]));
}
