import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/auth.dart';
import '../../core/format.dart';
import '../../core/quinzaine.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../models/models.dart';

const quotationStatusLabels = {
  'published': 'Publié',
  'no_data': 'Pas de données',
  'not_published_yet': 'Pas encore publié',
  'not_fetched': 'Non récupéré',
  'weekend': 'Non ouvré',
};

typedef _QuotesKey = ({String product, String from, String to});

final _quotationsProvider =
    FutureProvider.autoDispose.family<List<Quotation>, _QuotesKey>((ref, k) async {
  final res = await ref.watch(apiClientProvider).get(
    '/quotations',
    query: {'product': k.product, 'dateFrom': k.from, 'dateTo': k.to},
  );
  return (res as List).map((e) => Quotation.fromJson(e as Json)).toList();
});

final _calendarProvider = FutureProvider.autoDispose
    .family<List<CalendarDay>, ({Product product, String from, String to})>((ref, k) async {
  final res = await ref.watch(apiClientProvider).get(
    '/quotations/calendar',
    query: {'product': k.product.code, 'dateFrom': k.from, 'dateTo': k.to},
  );
  return (res as List).map((e) => CalendarDay.fromJson(e as Json)).toList();
});

class CotationsScreen extends ConsumerStatefulWidget {
  const CotationsScreen({super.key});

  @override
  ConsumerState<CotationsScreen> createState() => _CotationsScreenState();
}

class _CotationsScreenState extends ConsumerState<CotationsScreen> {
  static const _pageSize = 25;

  String _product = 'GASOIL';
  String _from = '';
  String _to = '';
  String _status = '';
  String _source = '';
  String _correction = '';
  int _shown = _pageSize;
  bool _busy = false;

  _QuotesKey get _key => (product: _product, from: _from, to: _to);

  bool get _hasFilters =>
      _product != 'GASOIL' ||
      _from.isNotEmpty ||
      _to.isNotEmpty ||
      _status.isNotEmpty ||
      _source.isNotEmpty ||
      _correction.isNotEmpty;

  void _update(VoidCallback change) => setState(() {
        change();
        _shown = _pageSize;
      });

  void _refreshData() {
    ref.invalidate(_quotationsProvider);
    ref.invalidate(_calendarProvider);
    invalidatePricing(ref);
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    final quotes = ref.watch(_quotationsProvider(_key));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cotations CIF NWE'),
        actions: [
          if (isAdmin)
            PopupMenuButton<String>(
              enabled: !_busy,
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.more_vert),
              onSelected: (v) {
                switch (v) {
                  case 'fetch':
                    _fetchToday();
                  case 'backfill':
                    _backfill();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'fetch', child: Text('Récupérer Platts (aujourd’hui)')),
                PopupMenuItem(value: 'backfill', child: Text('Backfill Platts')),
              ],
            ),
        ],
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: _create,
              backgroundColor: AppColors.amber,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          _refreshData();
          await ref.read(_quotationsProvider(_key).future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          children: [
            _filters(quotes.value ?? const []),
            const SizedBox(height: 12),
            _calendar(),
            const SizedBox(height: 12),
            AsyncView(
              value: quotes,
              onRetry: () => ref.invalidate(_quotationsProvider(_key)),
              builder: (data) => _list(data, isAdmin),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filters(List<Quotation> data) {
    final sources = {...data.map((q) => q.source)}.toList()..sort();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: LabeledDropdown<String>(
                  label: 'Produit',
                  value: _product,
                  items: const {'': 'Tous', 'GASOIL': 'Gasoil', 'SSP': 'SSP'},
                  onChanged: (v) => _update(() => _product = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LabeledDropdown<String>(
                  label: 'Statut',
                  value: _status,
                  items: {'': 'Tous', ...quotationStatusLabels},
                  onChanged: (v) => _update(() => _status = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DateField(label: 'Du', value: _from, onChanged: (v) => _update(() => _from = v)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DateField(label: 'Au', value: _to, onChanged: (v) => _update(() => _to = v)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: LabeledDropdown<String>(
                  key: ValueKey('src-${sources.join()}'),
                  label: 'Source',
                  value: sources.contains(_source) ? _source : '',
                  items: {'': 'Toutes', for (final s in sources) s: s},
                  onChanged: (v) => _update(() => _source = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LabeledDropdown<String>(
                  label: 'Correction',
                  value: _correction,
                  items: const {'': 'Toutes', 'yes': 'Corrigées', 'no': 'Non corrigées'},
                  onChanged: (v) => _update(() => _correction = v),
                ),
              ),
            ],
          ),
          if (_hasFilters)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _update(() {
                  _product = 'GASOIL';
                  _from = _to = _status = _source = _correction = '';
                }),
                child: const Text('Réinitialiser'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _calendar() {
    final now = DateTime.now();
    final product = Product.fromCode(_product.isEmpty ? 'GASOIL' : _product);
    final from = _from.isNotEmpty ? _from : isoDate(DateTime(now.year, now.month, 1));
    final to = _to.isNotEmpty ? _to : isoDate(now);
    final cal = ref.watch(_calendarProvider((product: product, from: from, to: to)));
    final days = cal.value ?? const <CalendarDay>[];

    return Panel(
      title: 'Statut par date — ${product.code}${_from.isEmpty && _to.isEmpty ? ' (mois en cours)' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final e in quotationStatusLabels.entries)
                StatusChip(e.value, color: _statusColor(e.key)),
            ],
          ),
          const SizedBox(height: 10),
          if (cal.isLoading && days.isEmpty)
            const Center(child: CircularProgressIndicator())
          else
            LayoutBuilder(builder: (context, c) {
              final w = (c.maxWidth - 6 * 4) / 7;
              return Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final d in days)
                    Tooltip(
                      message: '${formatDate(d.date)} : ${quotationStatusLabels[d.status] ?? d.status}'
                          '${d.cifNweValue != null ? ' — ${formatValue(d.cifNweValue)}' : ''}',
                      triggerMode: TooltipTriggerMode.tap,
                      child: Container(
                        width: w,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: _statusColor(d.status).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _statusColor(d.status).withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              d.date.substring(8, 10),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: _statusColor(d.status),
                              ),
                            ),
                            Text(
                              d.cifNweValue != null ? formatNumber(d.cifNweValue, 0) : '·',
                              style: const TextStyle(fontSize: 9, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            }),
        ],
      ),
    );
  }

  static Color _statusColor(String s) => switch (s) {
        'published' => AppColors.green,
        'no_data' => AppColors.red,
        'not_published_yet' => AppColors.amber,
        'weekend' => const Color(0xFF94A3B8),
        _ => AppColors.muted,
      };

  Widget _list(List<Quotation> data, bool isAdmin) {
    final filtered = data
        .where((q) =>
            (_status.isEmpty || q.status == _status) &&
            (_source.isEmpty || q.source == _source) &&
            (_correction.isEmpty || (_correction == 'yes') == (q.originalValue != null)))
        .toList();
    if (filtered.isEmpty) {
      return EmptyState(data.isEmpty ? 'Aucune cotation' : 'Aucune cotation pour ces filtres');
    }

    final stats = <String, Map<String, ({int count, double sum})>>{};
    for (final q in filtered) {
      if (q.cifNweValue == null) continue;
      final byProduct = stats[quinzaineOf(q.quotationDate).key] ??= {};
      final s = byProduct[q.product] ?? (count: 0, sum: 0.0);
      byProduct[q.product] = (count: s.count + 1, sum: s.sum + q.cifNweValue!);
    }

    final page = filtered.take(_shown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in withQuinzaineHeaders(page, (q) => q.quotationDate))
          switch (item) {
            GroupHeader(:final quinzaine) => QuinzaineHeaderTile(
                label: quinzaine.label,
                window: quinzaine.windowLabel,
                meta: [
                  for (final e in (stats[quinzaine.key]?.entries.toList() ?? [])
                    ..sort((a, b) => a.key.compareTo(b.key)))
                    '${e.key} : moyenne ${formatValue(e.value.sum / e.value.count)} \$/T '
                        '(${e.value.count} cotation${e.value.count > 1 ? 's' : ''})',
                ],
              ),
            GroupItem(:final row) => _tile(row, isAdmin),
          },
        LoadMoreButton(
          shown: page.length,
          total: filtered.length,
          onPressed: () => setState(() => _shown += _pageSize),
        ),
      ],
    );
  }

  Widget _tile(Quotation q, bool isAdmin) {
    final corrected = q.originalValue != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        title: Row(
          children: [
            Text(formatDate(q.quotationDate), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Text(q.product, style: const TextStyle(color: AppColors.muted)),
            const Spacer(),
            Text(
              q.cifNweValue != null ? formatValue(q.cifNweValue) : '—',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusChip(quotationStatusLabels[q.status] ?? q.status, color: _statusColor(q.status)),
              Text(q.source, style: const TextStyle(fontSize: 12)),
              if (corrected)
                StatusChip(
                  'Corrigée (orig. ${formatValue(q.originalValue)})',
                  color: const Color(0xFF7C3AED),
                ),
              if (q.correctionReason?.isNotEmpty ?? false)
                Text('Motif : ${q.correctionReason}', style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        trailing: isAdmin
            ? PopupMenuButton<String>(
                onSelected: (v) => v == 'correct' ? _correct(q) : _delete(q),
                itemBuilder: (_) => [
                  if (q.status == 'published' && q.cifNweValue != null)
                    const PopupMenuItem(value: 'correct', child: Text('Corriger')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Supprimer', style: TextStyle(color: AppColors.red)),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Future<void> _fetchToday() async {
    setState(() => _busy = true);
    final res = await runAction(
      context,
      () async => await ref.read(apiClientProvider).post('/quotations/fetch-today') as Json,
    );
    if (mounted) setState(() => _busy = false);
    if (res == null || !mounted) return;
    final results = (res['results'] as List? ?? const []).cast<Json>();
    final published = results.where((r) => r['status'] == 'published').length;
    final errors = results.where((r) => r['status'] == 'error').toList();
    final other = results.where((r) => r['status'] != 'published' && r['status'] != 'error').toList();
    String describe(List<Json> l) => l.map((r) => '${r['product']}=${r['status']}').join(', ');
    if (errors.isNotEmpty) {
      showToast(context, 'Platts : ${describe(errors)} — voir les logs serveur', error: true);
    } else if (published > 0) {
      showToast(context, 'Platts OK : $published produit(s) importé(s)');
    } else if (other.isNotEmpty) {
      showToast(context, 'Platts : ${describe(other)}');
    } else {
      showToast(context, 'Récupération Platts terminée (aucun résultat)');
    }
    _refreshData();
  }

  Future<void> _backfill() async {
    final body = await showFormSheet<Map<String, dynamic>>(
      context,
      title: 'Backfill Platts',
      builder: (_) => const _BackfillForm(),
    );
    if (body == null || !mounted) return;
    final ok = await runAction(
      context,
      () async {
        await ref.read(apiClientProvider).post('/quotations/backfill', body: body);
        return true;
      },
      success: 'Backfill Platts démarré',
    );
    if (ok != true) return;
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) _refreshData();
    });
  }

  Future<void> _create() async {
    final body = await showFormSheet<Map<String, dynamic>>(
      context,
      title: 'Nouvelle cotation',
      builder: (_) => const _CreateForm(),
    );
    if (body == null || !mounted) return;
    await runAction(
      context,
      () => ref.read(apiClientProvider).post('/quotations', body: body),
      success: 'Cotation créée',
    );
    _refreshData();
  }

  Future<void> _correct(Quotation q) async {
    final body = await showFormSheet<Map<String, dynamic>>(
      context,
      title: 'Corriger la cotation',
      builder: (_) => _CorrectForm(quotation: q),
    );
    if (body == null || !mounted) return;
    await runAction(
      context,
      () => ref.read(apiClientProvider).patch('/quotations/${q.id}/correct', body: body),
      success: 'Cotation corrigée',
    );
    _refreshData();
  }

  Future<void> _delete(Quotation q) async {
    final ok = await confirmDialog(
      context,
      'Supprimer cette cotation ? Les calculs orphelins seront retirés.',
      confirmLabel: 'Supprimer',
      danger: true,
    );
    if (!ok || !mounted) return;
    await runAction(
      context,
      () => ref.read(apiClientProvider).delete('/quotations/${q.id}'),
      success: 'Cotation supprimée',
    );
    _refreshData();
  }
}

class _CreateForm extends StatefulWidget {
  const _CreateForm();

  @override
  State<_CreateForm> createState() => _CreateFormState();
}

class _CreateFormState extends State<_CreateForm> {
  String _date = isoDate(DateTime.now());
  Product _product = Product.gasoil;
  final _value = TextEditingController();
  final _source = TextEditingController(text: 'manual');

  @override
  void dispose() {
    _value.dispose();
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DateField(label: 'Date', value: _date, clearable: false, onChanged: (v) => setState(() => _date = v)),
        const SizedBox(height: 12),
        ProductSelector(value: _product, onChanged: (p) => setState(() => _product = p)),
        const SizedBox(height: 12),
        TextField(
          controller: _value,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: r'Valeur CIF NWE ($/T)'),
        ),
        const SizedBox(height: 12),
        TextField(controller: _source, decoration: const InputDecoration(labelText: 'Source')),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            final v = parseDecimal(_value.text);
            if (v == null || v <= 0 || _source.text.trim().isEmpty) {
              showToast(context, 'Valeur et source requises', error: true);
              return;
            }
            Navigator.pop(context, {
              'quotationDate': _date,
              'product': _product.code,
              'cifNweValue': v,
              'source': _source.text.trim(),
            });
          },
          child: const Text('Créer'),
        ),
      ],
    );
  }
}

class _CorrectForm extends StatefulWidget {
  const _CorrectForm({required this.quotation});

  final Quotation quotation;

  @override
  State<_CorrectForm> createState() => _CorrectFormState();
}

class _CorrectFormState extends State<_CorrectForm> {
  late final _value = TextEditingController(
    text: widget.quotation.cifNweValue?.toString() ?? '',
  );
  final _reason = TextEditingController();

  @override
  void dispose() {
    _value.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.quotation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${q.product} — ${formatDate(q.quotationDate)}'),
        if (q.correctionReason != null)
          Text('Motif précédent : ${q.correctionReason}', style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 12),
        TextField(
          controller: _value,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: r'Nouvelle valeur ($/T)'),
        ),
        const SizedBox(height: 12),
        TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Motif (obligatoire)')),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            final v = parseDecimal(_value.text);
            if (v == null || v <= 0) {
              showToast(context, 'Valeur invalide', error: true);
              return;
            }
            if (_reason.text.trim().isEmpty) {
              showToast(context, 'Le motif de correction est obligatoire', error: true);
              return;
            }
            Navigator.pop(context, {'newValue': v, 'reason': _reason.text.trim()});
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _BackfillForm extends StatefulWidget {
  const _BackfillForm();

  @override
  State<_BackfillForm> createState() => _BackfillFormState();
}

class _BackfillFormState extends State<_BackfillForm> {
  String _from = '';
  String _to = '';
  String _product = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Maximum 100 jours calendaires. Un seul backfill à la fois.',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        DateField(label: 'Du', value: _from, onChanged: (v) => setState(() => _from = v)),
        const SizedBox(height: 12),
        DateField(label: 'Au', value: _to, onChanged: (v) => setState(() => _to = v)),
        const SizedBox(height: 12),
        LabeledDropdown<String>(
          label: 'Produit',
          value: _product,
          items: const {'': 'Tous', 'GASOIL': 'Gasoil', 'SSP': 'SSP'},
          onChanged: (v) => setState(() => _product = v),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _from.isEmpty || _to.isEmpty
              ? null
              : () => Navigator.pop(context, {
                    'dateFrom': _from,
                    'dateTo': _to,
                    if (_product.isNotEmpty) 'product': _product,
                  }),
          child: const Text('Lancer'),
        ),
      ],
    );
  }
}
