import 'package:flutter_test/flutter_test.dart';
import 'package:quadrant_planner/models.dart';

void main() {
  test('generated Flutter smoke test uses Quadrant domain', () {
    expect(const AppSettings().importanceMin, -10);
  });
}
