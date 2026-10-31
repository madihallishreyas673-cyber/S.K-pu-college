import '../models.dart';

/// Rule-based study assistant. It only READS verified marks and attendance and produces advice text.
/// It cannot create, change or publish marks.
class SubjectInsight {
  final String subject;
  final double latest;
  final double? previous, classAvg;
  final String status; // 'practice' | 'declining' | 'improving' | 'strong' | 'steady'
  final String advice;
  const SubjectInsight(this.subject, this.latest, this.previous, this.classAvg, this.status, this.advice);
  double? get change => previous == null ? null : double.parse((latest - previous!).toStringAsFixed(2));
}

class AssistantReport {
  final List<SubjectInsight> subjects;
  final double? overallChange; // latest exam % minus previous exam %
  final List<String> attendanceNotes;
  const AssistantReport(this.subjects, this.overallChange, this.attendanceNotes);
}

/// [progress] = rows of `my_progress()`: exam_id, exam_name, exam_created, subject_name, percentage, class_avg.
AssistantReport buildAdvice(List<Map<String, dynamic>> progress, AttSummary? att) {
  final bySubject = <String, List<Map<String, dynamic>>>{};
  for (final r in progress) {
    bySubject.putIfAbsent(r['subject_name'] as String, () => []).add(r);
  }
  final out = <SubjectInsight>[];
  for (final e in bySubject.entries) {
    final rows = [...e.value]..sort((a, b) => (a['exam_created'] as String).compareTo(b['exam_created'] as String));
    final latest = n(rows.last['percentage']).toDouble();
    final prev = rows.length > 1 ? n(rows[rows.length - 2]['percentage']).toDouble() : null;
    final avg = rows.last['class_avg'] == null ? null : n(rows.last['class_avg']).toDouble();
    final delta = prev == null ? null : latest - prev;
    String status, advice;
    if (latest < 50 || (avg != null && latest < avg - 10)) {
      status = 'practice';
      advice = 'Needs more practice. Revise the weakest chapters first, solve a few questions every day, and ask your ${e.key} teacher to go through your mistakes.';
    } else if (delta != null && delta <= -8) {
      status = 'declining';
      advice = 'Your score dropped by ${(-delta).toStringAsFixed(1)} points since the previous exam. Check which topics cost you marks and revise them before the next test.';
    } else if (delta != null && delta >= 5) {
      status = 'improving';
      advice = 'Good progress: up ${delta.toStringAsFixed(1)} points. Keep the same routine going.';
    } else if (latest >= 85) {
      status = 'strong';
      advice = 'Strong performance. Try harder or mixed questions to stay sharp.';
    } else {
      status = 'steady';
      advice = 'Steady. A little extra practice each week can lift this further.';
    }
    if (avg != null && status != 'practice') {
      advice += latest >= avg ? ' You are above the class average (${avg.toStringAsFixed(1)}%).' : ' The class average is ${avg.toStringAsFixed(1)}%.';
    }
    out.add(SubjectInsight(e.key, latest, prev, avg, status, advice));
  }
  const order = {'practice': 0, 'declining': 1, 'steady': 2, 'improving': 3, 'strong': 4};
  out.sort((a, b) => order[a.status]!.compareTo(order[b.status]!));

  // Overall trend between the two most recent exams.
  double? overall;
  final exams = <String, List<double>>{};
  final created = <String, String>{};
  for (final r in progress) {
    final id = r['exam_id'] as String;
    exams.putIfAbsent(id, () => []).add(n(r['percentage']).toDouble());
    created[id] = r['exam_created'] as String;
  }
  if (exams.length >= 2) {
    final ids = exams.keys.toList()..sort((a, b) => created[a]!.compareTo(created[b]!));
    double avg(String id) => exams[id]!.reduce((a, b) => a + b) / exams[id]!.length;
    overall = double.parse((avg(ids.last) - avg(ids[ids.length - 2])).toStringAsFixed(2));
  }

  final notes = <String>[];
  if (att != null) {
    for (final s in att.subjects) {
      if (s.stat.conducted > 0 && s.stat.pct < att.threshold) {
        notes.add('${s.name}: attendance is ${s.stat.pct.toStringAsFixed(1)}% (required ${att.threshold.toStringAsFixed(0)}%). Attending every ${s.name} class will help you keep up.');
      }
    }
    if (att.isLow) notes.insert(0, 'Overall attendance is ${att.overall.pct.toStringAsFixed(1)}%, below the required ${att.threshold.toStringAsFixed(0)}%.');
  }
  return AssistantReport(out, overall, notes);
}
