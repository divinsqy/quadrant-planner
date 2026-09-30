int normalizeLegacyScore(int value, int min, int max) {
  if (max <= min) {
    throw ArgumentError.value(
      [min, max],
      'range',
      'legacy score range must satisfy min < max',
    );
  }

  final clamped = value.clamp(min, max);
  final normalized = ((clamped - min) * 100 / (max - min)).round();
  return normalized.clamp(0, 100);
}
