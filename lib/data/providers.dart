import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../models/models.dart';

typedef QuinzaineKey = ({Product product, int year, int month, int period});

Map<String, dynamic> quinzaineQuery(QuinzaineKey k) => {
      'product': k.product.code,
      'year': k.year,
      'month': k.month,
      'period': k.period,
    };

/// Period shown on the Quinzaines tab (the dashboard can jump to one).
class QuinzaineSelection extends Notifier<QuinzaineKey> {
  @override
  QuinzaineKey build() {
    final now = DateTime.now();
    return (product: Product.gasoil, year: now.year, month: now.month, period: 1);
  }

  void set(QuinzaineKey key) => state = key;
}

final quinzaineSelectionProvider =
    NotifierProvider<QuinzaineSelection, QuinzaineKey>(QuinzaineSelection.new);

/// Quinzaine years that have both cotations and taux de change.
final availableYearsProvider = FutureProvider.autoDispose<List<int>>((ref) async {
  final res = await ref.watch(apiClientProvider).get('/pricing/years');
  final years = (res as List).map((e) => (e as num).toInt()).toList();
  if (years.isEmpty) years.add(DateTime.now().year);
  years.sort((a, b) => b.compareTo(a));
  return years;
});

final dashboardProvider = FutureProvider.autoDispose
    .family<DashboardData, ({Product product, int year})>((ref, k) async {
  final res = await ref.watch(apiClientProvider).get(
    '/dashboard',
    query: {'product': k.product.code, 'year': k.year},
  );
  return DashboardData.fromJson(res as Json);
});

final quinzaineDetailProvider = FutureProvider.autoDispose
    .family<QuinzaineDetail, QuinzaineKey>((ref, k) async {
  final res = await ref
      .watch(apiClientProvider)
      .get('/pricing/quinzaine', query: quinzaineQuery(k));
  return QuinzaineDetail.fromJson(res as Json);
});

final quinzaineAttachmentsProvider = FutureProvider.autoDispose
    .family<List<QuinzaineAttachment>, QuinzaineKey>((ref, k) async {
  final res = await ref
      .watch(apiClientProvider)
      .get('/pricing/quinzaine/configs', query: quinzaineQuery(k));
  return (res as List).map((e) => QuinzaineAttachment.fromJson(e as Json)).toList();
});

final productConfigsProvider = FutureProvider.autoDispose
    .family<List<ProductConfig>, Product?>((ref, product) async {
  final res = await ref
      .watch(apiClientProvider)
      .get('/product-configs', query: {'product': product?.code});
  return (res as List).map((e) => ProductConfig.fromJson(e as Json)).toList();
});

/// Published, positive Platts values in a quotation window, sorted by date.
final windowQuotesProvider = FutureProvider.autoDispose
    .family<List<DatedValue>, ({Product product, String from, String to})>(
        (ref, k) async {
  final res = await ref.watch(apiClientProvider).get(
    '/quotations',
    query: {'product': k.product.code, 'dateFrom': k.from, 'dateTo': k.to},
  );
  final rows = (res as List)
      .map((e) => Quotation.fromJson(e as Json))
      .where((q) => q.status == 'published' && (q.cifNweValue ?? 0) > 0)
      .map((q) => DatedValue(q.quotationDate, q.cifNweValue!))
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  return rows;
});

/// Invalidate everything derived from calculations (after recalcs, imports…).
void invalidatePricing(WidgetRef ref) {
  ref.invalidate(dashboardProvider);
  ref.invalidate(quinzaineDetailProvider);
  ref.invalidate(quinzaineAttachmentsProvider);
  ref.invalidate(windowQuotesProvider);
  ref.invalidate(availableYearsProvider);
}

String isoToday() => isoDate(DateTime.now());
