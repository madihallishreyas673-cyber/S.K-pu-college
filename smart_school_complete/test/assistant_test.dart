import 'package:flutter_test/flutter_test.dart';
import 'package:smart_school/services/assistant.dart';

Map<String, dynamic> row(String exam, String created, String subject, num pct, num? avg) =>
    {'exam_id': exam, 'exam_name': exam, 'exam_created': created, 'subject_name': subject, 'percentage': pct, 'class_avg': avg};

void main() {
  test('flags weak subjects first and detects a drop', () {
    final r = buildAdvice([
      row('e1', '2026-08-01', 'Physics', 80, 70), row('e1', '2026-08-01', 'Maths', 60, 60),
      row('e2', '2026-09-01', 'Physics', 40, 65), row('e2', '2026-09-01', 'Maths', 75, 60),
    ], null);
    expect(r.subjects.first.subject, 'Physics');
    expect(r.subjects.first.status, 'practice');
    expect(r.subjects.firstWhere((s) => s.subject == 'Maths').status, 'improving');
    expect(r.overallChange, -2.5);
  });

  test('single exam gives advice but no trend', () {
    final r = buildAdvice([row('e1', '2026-08-01', 'English', 90, 70)], null);
    expect(r.subjects.single.status, 'strong');
    expect(r.overallChange, isNull);
  });
}
