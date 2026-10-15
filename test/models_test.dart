import 'package:bgi_pricing_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DashboardData parses decimals sent as strings', () {
    final d = DashboardData.fromJson({
      'kpis': {
        'activeQuinzaine': {'label': 'Q1 Nov 2026', 'year': 2026, 'month': 11, 'period': 1},
        'displayQuinzaine': null,
        'usingFallback': false,
        'cifNweAverage': {'value': '712.5', 'quotationsCount': 4},
        'todayPriceTtc': {'value': 10234.56, 'calculationDate': '2026-10-14T00:00:00.000Z'},
        'quotationWindow': {'start': '2026-10-13T00:00:00.000Z', 'end': '2026-10-27T00:00:00.000Z'},
      },
      'yearComparisonChart': {
        'currentYear': [
          {'label': 'Q1 Jan', 'value': 10000},
          {'label': 'Q2 Jan', 'value': null},
        ],
        'previousYear': [
          {'label': 'Q1 Jan', 'value': 9500.5},
        ],
      },
      'quinzaineGrid': [
        {'year': 2026, 'month': 1, 'period': 1, 'label': 'Q1 Jan', 'status': 'cloturee', 'lastPriceTtc': '9999.99'},
      ],
      'selectedQuinzaineEvolution': [
        {'date': '2026-10-14', 'priceTtc': '10234.56', 'cifNweAverage': '712.5'},
      ],
      'rawQuotations': [
        {'date': '2026-10-13', 'value': 710},
      ],
    });
    expect(d.activeQuinzaine?.label, 'Q1 Nov 2026');
    expect(d.cifNweAverage, 712.5);
    expect(d.todayPriceDate, '2026-10-14');
    expect(d.windowEnd, '2026-10-27');
    expect(d.currentYear[1].value, isNull);
    expect(d.grid.single.lastPriceTtc, 9999.99);
    expect(d.evolution.single.value, 10234.56);
  });

  test('BkamPreviewRow.kind', () {
    BkamPreviewRow row(String status, double? rate, double? existing) =>
        BkamPreviewRow.fromJson({'date': '2026-10-14', 'rate': rate, 'status': status, 'existingRate': existing});
    expect(row('ok', 10.1, null).kind, 'new');
    expect(row('ok', 10.1, 10.0).kind, 'changed');
    expect(row('ok', 10.1, 10.1).kind, 'same');
    expect(row('no_data', null, null).kind, 'no_data');
    expect(row('error', null, null).kind, 'error');
    expect(row('ok', 10.1, null).selectable, isTrue);
  });

  test('AuditLog falls back to Système when no user', () {
    final log = AuditLog({'id': 1, 'action': 'BKAM_FETCH', 'tableName': 'exchange_rates', 'createdAt': '2026-10-14T09:00:00Z'});
    expect(log.username, 'Système');
    expect(log.id, '1');
  });
}
