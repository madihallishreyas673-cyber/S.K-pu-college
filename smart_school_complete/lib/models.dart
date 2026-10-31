String yearName(int y) => y == 1 ? 'First Year' : 'Second Year';

class AppUser {
  final String id, role, loginId, fullName;
  final int? yearLevel;
  final bool mustChangePin;
  const AppUser({required this.id, required this.role, required this.loginId, required this.fullName, this.yearLevel, this.mustChangePin = false});

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String, role: j['role'] as String, loginId: j['login_id'] as String,
        fullName: j['full_name'] as String, yearLevel: j['year_level'] as int?,
        mustChangePin: (j['must_change_pin'] ?? false) as bool);

  Map<String, dynamic> toJson() => {
        'id': id, 'role': role, 'login_id': loginId, 'full_name': fullName,
        'year_level': yearLevel, 'must_change_pin': mustChangePin};

  AppUser copyWith({bool? mustChangePin}) => AppUser(
      id: id, role: role, loginId: loginId, fullName: fullName, yearLevel: yearLevel,
      mustChangePin: mustChangePin ?? this.mustChangePin);
}

class Subject {
  final String id, name;
  const Subject(this.id, this.name);
}

class SchoolClass {
  final String id, section;
  final int yearLevel;
  final String? classTeacherId;
  const SchoolClass({required this.id, required this.yearLevel, required this.section, this.classTeacherId});
  factory SchoolClass.fromJson(Map<String, dynamic> j) => SchoolClass(
      id: j['id'] as String, yearLevel: j['year_level'] as int, section: (j['section'] ?? '') as String,
      classTeacherId: j['class_teacher_id'] as String?);
  String get label => section.isEmpty ? yearName(yearLevel) : '${yearName(yearLevel)} - $section';
}

class Assignment {
  final String id, subjectId, subjectName;
  final SchoolClass cls;
  const Assignment({required this.id, required this.subjectId, required this.subjectName, required this.cls});
  factory Assignment.fromJson(Map<String, dynamic> j) => Assignment(
      id: j['id'] as String, subjectId: j['subject_id'] as String,
      subjectName: (j['subjects'] as Map)['name'] as String,
      cls: SchoolClass.fromJson({...(j['classes'] as Map<String, dynamic>), 'id': j['class_id']}));
}

class RosterRow {
  final String studentId, name;
  final int rollNo;
  final String? existing; // 'P' | 'A' | null
  final String? sessionId;
  const RosterRow({required this.studentId, required this.name, required this.rollNo, this.existing, this.sessionId});
  factory RosterRow.fromJson(Map<String, dynamic> j) => RosterRow(
      studentId: j['student_id'] as String, name: j['full_name'] as String, rollNo: j['roll_no'] as int,
      existing: j['existing_status'] as String?, sessionId: j['session_id'] as String?);
}

num n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

class AttStat {
  final int conducted, present, absent;
  final double pct;
  const AttStat(this.conducted, this.present, this.absent, this.pct);
  factory AttStat.fromJson(Map<String, dynamic> j) =>
      AttStat(n(j['conducted']).toInt(), n(j['present']).toInt(), n(j['absent']).toInt(), n(j['percentage']).toDouble());
}

class SubjectAtt {
  final String name;
  final AttStat stat;
  const SubjectAtt(this.name, this.stat);
}

class AttSummary {
  final AttStat overall;
  final List<SubjectAtt> subjects;
  final double threshold;
  final bool isLow;
  const AttSummary(this.overall, this.subjects, this.threshold, this.isLow);
  factory AttSummary.fromJson(Map<String, dynamic> j) => AttSummary(
      AttStat.fromJson(Map<String, dynamic>.from(j['overall'] as Map)),
      (j['subjects'] as List).map((s) => SubjectAtt(s['subject_name'] as String, AttStat.fromJson(Map<String, dynamic>.from(s as Map)))).toList(),
      n(j['threshold']).toDouble(), j['is_low'] as bool);
}

/// Same rule as the database: overall = total present / total conducted.
/// Used for offline display checks and unit tests; the database remains the source of truth.
double attendancePercent(int present, int conducted) =>
    conducted == 0 ? 0 : double.parse((100.0 * present / conducted).toStringAsFixed(2));
