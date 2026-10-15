import 'package:bgi_pricing_mobile/core/quinzaine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('quinzaineOf', () {
    test('day 13..27 belongs to Q1 of the next month', () {
      final q = quinzaineOf('2026-10-14');
      expect(q.key, '2026-11-Q1');
      expect(q.start, '2026-10-13');
      expect(q.end, '2026-10-27');
    });

    test('day 28+ belongs to Q2 of the next month', () {
      final q = quinzaineOf('2026-10-28');
      expect(q.key, '2026-11-Q2');
      expect(q.start, '2026-10-28');
      expect(q.end, '2026-11-12');
    });

    test('day 1..12 belongs to Q2 of the same month', () {
      final q = quinzaineOf('2026-11-12');
      expect(q.key, '2026-11-Q2');
    });

    test('year rollover', () {
      expect(quinzaineOf('2026-12-20').key, '2027-01-Q1');
      final q = quinzaineOf('2027-01-05');
      expect(q.key, '2027-01-Q2');
      expect(q.start, '2026-12-28');
    });
  });

  test('withQuinzaineHeaders inserts a header at each change', () {
    final rows = ['2026-10-10', '2026-10-12', '2026-10-13', '2026-10-28'];
    final out = withQuinzaineHeaders<String>(rows, (r) => r);
    expect(out.whereType<GroupHeader<String>>().length, 3);
    expect(out.length, 7);
  });
}
