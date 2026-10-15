enum AudioQuality {
  standard('标准'),
  higher('较高'),
  exhigh('极高'),
  lossless('无损'),
  hires('Hi-Res');

  const AudioQuality(this.label);
  final String label;

  static AudioQuality parse(Object? stored) =>
      AudioQuality.values.firstWhere((quality) => quality.name == stored,
          orElse: () => AudioQuality.exhigh);

  Iterable<AudioQuality> get fallbacks =>
      AudioQuality.values.take(index + 1).toList().reversed;
}
