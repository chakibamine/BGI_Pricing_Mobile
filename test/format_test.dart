import 'package:bgi_pricing_mobile/core/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatNumber', () {
    test('groups thousands with a non-breaking space and uses a comma', () {
      expect(formatNumber(1002.5), '1\u00a0002,50');
      expect(formatNumber(1234567.891, 4), '1\u00a0234\u00a0567,8910');
    });

    test('handles negatives, zero and null', () {
      expect(formatNumber(-12.345), '-12,35');
      expect(formatNumber(-0.001), '0,00');
      expect(formatNumber(null), '—');
    });

    test('price and value precision', () {
      expect(formatPrice(10.456), '10,46');
      expect(formatValue(10.45678), '10,4568');
      expect(formatSigned(3), '+3,00');
    });
  });

  test('formatDate and isoDate', () {
    expect(formatDate('2026-10-14T00:00:00.000Z'), '14/10/2026');
    expect(isoDate(DateTime(2026, 1, 5)), '2026-01-05');
  });

  test('toDouble parses Prisma decimal strings', () {
    expect(toDouble('10.5'), 10.5);
    expect(toDouble(3), 3.0);
    expect(toDouble(null), isNull);
    expect(toDoubleOr0('x'), 0);
  });
}
