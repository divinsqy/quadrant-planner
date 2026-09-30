class AppPreferences {
  final String nickname;
  final int importanceThreshold;
  final int urgencyThreshold;

  const AppPreferences({
    required this.nickname,
    required this.importanceThreshold,
    required this.urgencyThreshold,
  });

  factory AppPreferences.defaults() {
    return const AppPreferences(
      nickname: '',
      importanceThreshold: 50,
      urgencyThreshold: 50,
    );
  }
}
