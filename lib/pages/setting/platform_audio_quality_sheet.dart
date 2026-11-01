// Community maintenance and new features: tiancaiProgramer.
import 'package:flutter/material.dart';
import '../../common/audio_quality.dart';
import '../../common/audio_quality_preferences.dart';
import '../../common/music/music_source.dart';
import '../../widget/adaptive_option_sheet.dart';

class PlatformAudioQualitySheet extends StatefulWidget {
  const PlatformAudioQualitySheet(
      {super.key,
      required this.use,
      required this.preferences,
      required this.onSelected,
      this.initialSource = MusicSource.netease,
      this.footer});
  final AudioQualityUse use;
  final AudioQualityPreferences preferences;
  final void Function(MusicSource, AudioQuality) onSelected;
  final MusicSource initialSource;
  final Widget? footer;
  @override
  State<PlatformAudioQualitySheet> createState() =>
      _PlatformAudioQualitySheetState();
}

class _PlatformAudioQualitySheetState extends State<PlatformAudioQualitySheet> {
  late MusicSource source = widget.initialSource;
  @override
  Widget build(BuildContext context) => AdaptiveOptionSheet(
      title: widget.use == AudioQualityUse.playback ? '播放音质' : '默认下载音质',
      children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, children: [
              for (final option in MusicSource.values)
                ChoiceChip(
                    key: ValueKey('quality-source:${option.name}'),
                    label: Text(option.label),
                    selected: source == option,
                    onSelected: (_) => setState(() => source = option))
            ])),
        for (final quality in AudioQualityOptions.supported(source, widget.use))
          RadioListTile<AudioQuality>(
              key: ValueKey('audio-quality:${quality.name}'),
              title: Text(quality.label),
              value: quality,
              groupValue: widget.preferences.get(source, widget.use),
              onChanged: (_) => widget.onSelected(source, quality)),
      ],
      footer: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            widget.use == AudioQualityUse.download
                ? '两平台分别保存。只下载所选档位，不自动降低音质。'
                : widget.preferences.playbackFallbackEnabled
                    ? '两平台分别保存。播放失败时自动尝试较低音质。'
                    : '两平台分别保存。只请求所选档位，不自动降低音质。',
            style: TextStyle(fontSize: 12)),
        if (widget.footer != null) ...[
          const SizedBox(height: 8),
          widget.footer!
        ],
      ]));
}
