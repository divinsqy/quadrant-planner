import 'report_evidence.dart';
import 'report_style_profile.dart';

String reportDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

class DateRange {
  final DateTime start;
  final DateTime end;
  DateRange(DateTime start, DateTime end)
    : start = DateTime(
        start.toLocal().year,
        start.toLocal().month,
        start.toLocal().day,
      ),
      end = DateTime(
        end.toLocal().year,
        end.toLocal().month,
        end.toLocal().day,
      ) {
    if (this.end.isBefore(this.start)) throw ArgumentError('结束日期不能早于开始日期');
  }
  factory DateRange.weekOf(DateTime date) {
    final local = date.toLocal();
    final monday = DateTime(
      local.year,
      local.month,
      local.day - local.weekday + 1,
    );
    return DateRange(
      monday,
      DateTime(monday.year, monday.month, monday.day + 6),
    );
  }
  DateTime get endExclusive => DateTime(end.year, end.month, end.day + 1);
  bool contains(DateTime? time) =>
      time != null && !time.isBefore(start) && time.isBefore(endExclusive);
  DateRange get nextWeek => DateRange(
    DateTime(end.year, end.month, end.day + 1),
    DateTime(end.year, end.month, end.day + 7),
  );
  Map<String, dynamic> toJson() => {
    'start': reportDate(start),
    'end': reportDate(end),
  };
  factory DateRange.fromJson(Map<String, dynamic> j) => DateRange(
    DateTime.parse(j['start'] as String),
    DateTime.parse(j['end'] as String),
  );
}

class ReportItem {
  final String id;
  final String text;
  final int progress;
  final String? projectId;
  final String? projectName;
  final List<ReportEvidenceRef> evidence;
  ReportItem({
    required this.id,
    required this.text,
    this.progress = 0,
    this.projectId,
    this.projectName,
    required List<ReportEvidenceRef> evidence,
  }) : evidence = List.unmodifiable(evidence) {
    if (progress < 0 || progress > 100) throw ArgumentError('完成度必须为0–100');
  }
  ReportItem copyWith({String? text, int? progress}) => ReportItem(
    id: id,
    text: text ?? this.text,
    progress: progress ?? this.progress,
    projectId: projectId,
    projectName: projectName,
    evidence: evidence,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'progress': progress,
    'projectId': projectId,
    'projectName': projectName,
    'evidence': evidence.map((e) => e.toJson()).toList(),
  };
  factory ReportItem.fromJson(Map<String, dynamic> j) => ReportItem(
    id: j['id'] as String,
    text: j['text'] as String,
    progress: j['progress'] as int,
    projectId: j['projectId'] as String?,
    projectName: j['projectName'] as String?,
    evidence: (j['evidence'] as List)
        .map(
          (e) =>
              ReportEvidenceRef.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
  );
}

class ReportReflection {
  final String id;
  final String question;
  final String answer;
  final List<ReportEvidenceRef> evidence;
  ReportReflection({
    required this.id,
    required this.question,
    required this.answer,
    required List<ReportEvidenceRef> evidence,
  }) : evidence = List.unmodifiable(evidence);
  ReportReflection copyWith({String? question, String? answer}) =>
      ReportReflection(
        id: id,
        question: question ?? this.question,
        answer: answer ?? this.answer,
        evidence: evidence,
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'question': question,
    'answer': answer,
    'evidence': evidence.map((e) => e.toJson()).toList(),
  };
  factory ReportReflection.fromJson(Map<String, dynamic> j) => ReportReflection(
    id: j['id'] as String,
    question: j['question'] as String,
    answer: j['answer'] as String,
    evidence: (j['evidence'] as List)
        .map(
          (e) =>
              ReportEvidenceRef.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
  );
}

enum ReportStatus { draft, finalized }

typedef WeeklyReportDraft = WeeklyReport;

class WeeklyReport {
  final String id;
  final DateRange week;
  final String author;
  final DateTime reportDate;
  final ReportStyleProfile style;
  final List<ReportItem> workItems;
  final List<ReportReflection> reflections;
  final List<ReportItem> nextWeekItems;
  final String supervisorFeedback;
  final ReportStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  WeeklyReport({
    required this.id,
    required this.week,
    required this.author,
    required this.reportDate,
    required this.style,
    required List<ReportItem> workItems,
    required List<ReportReflection> reflections,
    required List<ReportItem> nextWeekItems,
    this.supervisorFeedback = '',
    this.status = ReportStatus.draft,
    required this.createdAt,
    required this.updatedAt,
  }) : workItems = List.unmodifiable(workItems),
       reflections = List.unmodifiable(reflections),
       nextWeekItems = List.unmodifiable(nextWeekItems);
  WeeklyReport copyWith({
    String? author,
    DateTime? reportDate,
    ReportStyleProfile? style,
    List<ReportItem>? workItems,
    List<ReportReflection>? reflections,
    List<ReportItem>? nextWeekItems,
    String? supervisorFeedback,
    ReportStatus? status,
    DateTime? updatedAt,
  }) => WeeklyReport(
    id: id,
    week: week,
    author: author ?? this.author,
    reportDate: reportDate ?? this.reportDate,
    style: style ?? this.style,
    workItems: workItems ?? this.workItems,
    reflections: reflections ?? this.reflections,
    nextWeekItems: nextWeekItems ?? this.nextWeekItems,
    supervisorFeedback: supervisorFeedback ?? this.supervisorFeedback,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Map<String, dynamic> toJson() => {
    'version': 1,
    'id': id,
    'week': week.toJson(),
    'author': author,
    'reportDate': reportDate.toIso8601String(),
    'style': style.toJson(),
    'workItems': workItems.map((e) => e.toJson()).toList(),
    'reflections': reflections.map((e) => e.toJson()).toList(),
    'nextWeekItems': nextWeekItems.map((e) => e.toJson()).toList(),
    'supervisorFeedback': supervisorFeedback,
    'status': status.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
  factory WeeklyReport.fromJson(Map<String, dynamic> j) => WeeklyReport(
    id: j['id'] as String,
    week: DateRange.fromJson(Map<String, dynamic>.from(j['week'] as Map)),
    author: j['author'] as String,
    reportDate: DateTime.parse(j['reportDate'] as String),
    style: ReportStyleProfile.fromJson(
      Map<String, dynamic>.from(j['style'] as Map),
    ),
    workItems: (j['workItems'] as List)
        .map((e) => ReportItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    reflections: (j['reflections'] as List)
        .map(
          (e) => ReportReflection.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
    nextWeekItems: (j['nextWeekItems'] as List)
        .map((e) => ReportItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    supervisorFeedback: j['supervisorFeedback'] as String,
    status: ReportStatus.values.byName(j['status'] as String),
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
  );
}
