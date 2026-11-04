import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/models.dart';

class ImportationsYear extends Notifier<int> {
  @override
  int build() => DateTime.now().year;

  void set(int year) => state = year;
}

final importationsYearProvider =
    NotifierProvider<ImportationsYear, int>(ImportationsYear.new);

final importationsListProvider =
    FutureProvider.autoDispose.family<List<ImportationListItem>, int>((ref, year) async {
  final res = await ref.watch(apiClientProvider).get(
    '/importations',
    query: {'year': year},
  );
  return (res as List).map((e) => ImportationListItem.fromJson(e as Json)).toList();
});

final importationDetailProvider =
    FutureProvider.autoDispose.family<ImportationDetail, int>((ref, id) async {
  final res = await ref.watch(apiClientProvider).get('/importations/$id');
  return ImportationDetail.fromJson(res as Json);
});

void invalidateImportations(WidgetRef ref) {
  ref.invalidate(importationsListProvider);
  ref.invalidate(importationDetailProvider);
}
