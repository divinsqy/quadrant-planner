import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/migration/legacy_score_normalizer.dart';

void main() {
  test('normalizes the old default importance range into 0 to 100', () {
    expect(normalizeLegacyScore(-10, -10, 10), 0);
    expect(normalizeLegacyScore(0, -10, 10), 50);
    expect(normalizeLegacyScore(10, -10, 10), 100);
  });

  test('normalizes a custom legacy range and clamps historical outliers', () {
    expect(normalizeLegacyScore(-3, -3, 7), 0);
    expect(normalizeLegacyScore(2, -3, 7), 50);
    expect(normalizeLegacyScore(7, -3, 7), 100);
    expect(normalizeLegacyScore(-99, -3, 7), 0);
    expect(normalizeLegacyScore(99, -3, 7), 100);
  });

  test('rejects a zero-width legacy range', () {
    expect(
      () => normalizeLegacyScore(1, 5, 5),
      throwsArgumentError,
    );
  });
}
