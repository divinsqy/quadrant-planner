class ReportStyleProfile {
  final String id;
  final String name;
  final String title;
  final String authorLabel;
  final String dateLabel;
  final String workHeading;
  final String reflectionHeading;
  final String nextWeekHeading;
  final String feedbackHeading;
  final bool projectHeadings;
  final bool preserveTechnicalTerms;
  final String numbering;
  final String completionFormat;
  final String reflectionFormat;
  const ReportStyleProfile({
    required this.id,
    required this.name,
    this.title = '工作周报',
    this.authorLabel = '姓名',
    this.dateLabel = '汇报日期',
    this.workHeading = '本周主要工作内容:',
    this.reflectionHeading = '本周工作遇到的困难 / 问题 / 体会 / 感受:',
    this.nextWeekHeading = '下周工作计划:',
    this.feedbackHeading = '主管反馈:',
    this.projectHeadings = false,
    this.preserveTechnicalTerms = true,
    this.numbering = '.',
    this.completionFormat = '[xx%]',
    this.reflectionFormat = 'Q/A',
  });
  factory ReportStyleProfile.standard() =>
      const ReportStyleProfile(id: 'standard', name: '简洁技术周报');
  ReportStyleProfile copyWith({
    String? id,
    String? name,
    String? title,
    String? authorLabel,
    String? dateLabel,
    String? workHeading,
    String? reflectionHeading,
    String? nextWeekHeading,
    String? feedbackHeading,
    bool? projectHeadings,
    String? numbering,
  }) => ReportStyleProfile(
    id: id ?? this.id,
    name: name ?? this.name,
    title: title ?? this.title,
    authorLabel: authorLabel ?? this.authorLabel,
    dateLabel: dateLabel ?? this.dateLabel,
    workHeading: workHeading ?? this.workHeading,
    reflectionHeading: reflectionHeading ?? this.reflectionHeading,
    nextWeekHeading: nextWeekHeading ?? this.nextWeekHeading,
    feedbackHeading: feedbackHeading ?? this.feedbackHeading,
    projectHeadings: projectHeadings ?? this.projectHeadings,
    preserveTechnicalTerms: preserveTechnicalTerms,
    numbering: numbering ?? this.numbering,
    completionFormat: completionFormat,
    reflectionFormat: reflectionFormat,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'title': title,
    'authorLabel': authorLabel,
    'dateLabel': dateLabel,
    'workHeading': workHeading,
    'reflectionHeading': reflectionHeading,
    'nextWeekHeading': nextWeekHeading,
    'feedbackHeading': feedbackHeading,
    'projectHeadings': projectHeadings,
    'preserveTechnicalTerms': preserveTechnicalTerms,
    'numbering': numbering,
    'completionFormat': completionFormat,
    'reflectionFormat': reflectionFormat,
  };
  factory ReportStyleProfile.fromJson(Map<String, dynamic> j) =>
      ReportStyleProfile(
        id: j['id'] as String,
        name: j['name'] as String,
        title: j['title'] as String,
        authorLabel: j['authorLabel'] as String,
        dateLabel: j['dateLabel'] as String,
        workHeading: j['workHeading'] as String,
        reflectionHeading: j['reflectionHeading'] as String,
        nextWeekHeading: j['nextWeekHeading'] as String,
        feedbackHeading: j['feedbackHeading'] as String,
        projectHeadings: j['projectHeadings'] as bool? ?? false,
        preserveTechnicalTerms: j['preserveTechnicalTerms'] as bool? ?? true,
        numbering: j['numbering'] as String? ?? '.',
        completionFormat: j['completionFormat'] as String? ?? '[xx%]',
        reflectionFormat: j['reflectionFormat'] as String? ?? 'Q/A',
      );
}
