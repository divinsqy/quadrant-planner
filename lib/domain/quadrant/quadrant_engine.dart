import 'quadrant.dart';

class QuadrantEngine {
  const QuadrantEngine();

  Quadrant classify({
    required int importance,
    required int urgency,
    required int importanceThreshold,
    required int urgencyThreshold,
  }) {
    _requireScore('importance', importance);
    _requireScore('urgency', urgency);
    _requireScore('importanceThreshold', importanceThreshold);
    _requireScore('urgencyThreshold', urgencyThreshold);

    final highImportance = importance >= importanceThreshold;
    final highUrgency = urgency >= urgencyThreshold;

    if (highImportance && highUrgency) {
      return Quadrant.doNow;
    }
    if (highImportance) {
      return Quadrant.plan;
    }
    if (highUrgency) {
      return Quadrant.expedite;
    }
    return Quadrant.lowPriority;
  }

  static void _requireScore(String name, int value) {
    if (value < 0 || value > 100) {
      throw ArgumentError.value(value, name, 'must be between 0 and 100');
    }
  }
}
