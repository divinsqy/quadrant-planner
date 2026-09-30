class UrgencyResult {
  final int value;
  final double ageComponent;
  final double? deadlineComponent;
  final bool calendarEstimated;

  const UrgencyResult({
    required this.value,
    required this.ageComponent,
    required this.deadlineComponent,
    required this.calendarEstimated,
  });
}
