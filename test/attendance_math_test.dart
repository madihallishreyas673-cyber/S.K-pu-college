import 'package:flutter_test/flutter_test.dart';
import 'package:smart_school/models.dart';

void main() {
  test('overall attendance is present / conducted, not an average of subjects', () {
    expect(attendancePercent(16, 20), 80.0);
    expect(attendancePercent(0, 0), 0.0);
    expect(attendancePercent(2, 3), 66.67);
  });

  test('AttSummary parses the database JSON', () {
    final s = AttSummary.fromJson({
      'overall': {'conducted': 20, 'present': 16, 'absent': 4, 'percentage': 80},
      'subjects': [
        {'subject_id': 'x', 'subject_name': 'Physics', 'conducted': 10, 'present': 10, 'absent': 0, 'percentage': 100.00},
      ],
      'threshold': 75, 'is_low': false,
    });
    expect(s.overall.pct, 80.0);
    expect(s.subjects.single.name, 'Physics');
    expect(s.isLow, false);
  });

  test('class label shows section only when present', () {
    expect(const SchoolClass(id: '1', yearLevel: 1, section: '').label, 'First Year');
    expect(const SchoolClass(id: '2', yearLevel: 2, section: 'A').label, 'Second Year - A');
  });
}
