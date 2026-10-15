/// Display precision: HT/TTC prices use [priceDigits], every other value [valueDigits].
const priceDigits = 2;
const valueDigits = 4;

const _nbsp = '\u00a0';

/// French style with a (non-breaking) space for thousands: 1002.5 -> "1 002,50".
String formatNumber(num? value, [int digits = 2]) {
  if (value == null || value.isNaN) return '—';
  final fixed = value.abs().toStringAsFixed(digits);
  final parts = fixed.split('.');
  final grouped = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => _nbsp,
  );
  final sign = value < 0 && double.parse(fixed) != 0 ? '-' : '';
  return '$sign$grouped${parts.length > 1 ? ',${parts[1]}' : ''}';
}

String formatPrice(num? value) => formatNumber(value, priceDigits);

String formatValue(num? value) => formatNumber(value, valueDigits);

String formatSigned(num? value, [int digits = priceDigits]) {
  if (value == null) return '—';
  return '${value > 0 ? '+' : ''}${formatNumber(value, digits)}';
}

/// "2026-10-14..." -> "14/10/2026".
String formatDate(String? iso) {
  if (iso == null || iso.length < 10) return '—';
  final p = iso.substring(0, 10).split('-');
  return '${p[2]}/${p[1]}/${p[0]}';
}

/// Date-only ISO string for a local calendar date.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The API returns Prisma decimals as strings; numbers otherwise.
double? toDouble(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

double toDoubleOr0(Object? v) => toDouble(v) ?? 0;

/// User input: accepts "1 234,5" as well as "1234.5".
double? parseDecimal(String input) => double.tryParse(
      input.trim().replaceAll(RegExp(r'[\s\u00a0]'), '').replaceAll(',', '.'),
    );

String? isoDay(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  return s.length >= 10 ? s.substring(0, 10) : s;
}
