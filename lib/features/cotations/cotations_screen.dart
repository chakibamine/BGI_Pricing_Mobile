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

typedef _Filters = ({String from, String to, String status, String source, String correction});

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

  int get _filterCount => [_from, _to, _status, _source, _correction].where((v) => v.isNotEmpty).length;

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
    final p = context.palette;

    return PageScaffold(
      title: 'Cotations',
      actions: [
        if (isAdmin)
          ActionMenu<String>(
            busy: _busy,
            onSelected: (v) {
              switch (v) {
                case 'fetch':
                  _fetchToday();
                case 'backfill':
                  _backfill();
              }
            },
            items: [
              menuItem('fetch', Icons.cloud_download_outlined, 'Récupérer Platts (aujourd’hui)'),
              menuItem('backfill', Icons.history_toggle_off_rounded, 'Backfill Platts'),
            ],
          ),
      ],
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Cotation'),
            )
          : null,
      onRefresh: () async {
        _refreshData();
        await ref.read(_quotationsProvider(_key).future);
      },
      filterBar: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final e in const {'GASOIL': 'Gasoil', 'SSP': 'SSP', '': 'Tous'}.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: _product == e.key,
                        showCheckmark: false,
                        onSelected: (_) => _update(() => _product = e.key),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Badge(
            isLabelVisible: _filterCount > 0,
            label: Text('$_filterCount'),
            backgroundColor: p.accent,
            child: OutlinedButton.icon(
              onPressed: () => _openFilters(quotes.value ?? const []),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Filtres'),
            ),
          ),
        ],
      ),
      children: [
        _calendar(),
        AsyncView(
          value: quotes,
          onRetry: () => ref.invalidate(_quotationsProvider(_key)),
          builder: (data) => _list(data, isAdmin),
        ),
      ],
    );
  }

  Future<void> _openFilters(List<Quotation> data) async {
    final sources = {...data.map((q) => q.source)}.toList()..sort();
    final result = await showFormSheet<_Filters>(
      context,
      title: 'Filtres',
      builder: (_) => _FiltersForm(
        initial: (from: _from, to: _to, status: _status, source: _source, correction: _correction),
        sources: sources,
      ),
    );
    if (result == null) return;
    _update(() {
      _from = result.from;
      _to = result.to;
      _status = result.status;
      _source = result.source;
      _correction = result.correction;
    });
  }

  Widget _calendar() {
    final p = context.palette;
    final now = DateTime.now();
    final product = Product.fromCode(_product.isEmpty ? 'GASOIL' : _product);
    final from = _from.isNotEmpty ? _from : isoDate(DateTime(now.year, now.month, 1));
    final to = _to.isNotEmpty ? _to : isoDate(now);
    final cal = ref.watch(_calendarProvider((product: product, from: from, to: to)));
    final days = cal.value ?? const <CalendarDay>[];

    return Panel(
      title: 'Statut par date',
      subtitle: '${product.code}${_from.isEmpty && _to.isEmpty ? ' · mois en cours' : ''}',
      icon: Icons.calendar_month_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cal.isLoading && days.isEmpty)
            const Skeleton(height: 180, radius: 12)
          else
            LayoutBuilder(builder: (context, c) {
              const gap = 5.0;
              final w = (c.maxWidth - 6 * gap) / 7;
              final offset = days.isEmpty ? 0 : DateTime.parse(days.first.date).weekday - 1;
              return Column(
                children: [
                  Row(
                    children: [
                      for (final (i, d) in const ['L', 'M', 'M', 'J', 'V', 'S', 'D'].indexed)
                        Container(
                          width: w,
                          margin: EdgeInsets.only(right: i < 6 ? gap : 0),
                          alignment: Alignment.center,
                          child: Text(
                            d,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.textMuted),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (var i = 0; i < offset; i++) SizedBox(width: w, height: w),
                      for (final d in days) _dayCell(d, w),
                    ],
                  ),
                ],
              );
            }),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in quotationStatusLabels.entries) StatusChip(e.value, color: _statusColor(p, e.key)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dayCell(CalendarDay d, double size) {
    final p = context.palette;
    final color = _statusColor(p, d.status);
    final published = d.status == 'published';
    return Tooltip(
      message: '${formatDate(d.date)} : ${quotationStatusLabels[d.status] ?? d.status}'
          '${d.cifNweValue != null ? ' — ${formatValue(d.cifNweValue)}' : ''}',
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: published ? color.withValues(alpha: p.isDark ? 0.75 : 0.85) : p.tint(color),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${int.parse(d.date.substring(8, 10))}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: published ? Colors.white : color,
              ),
            ),
            if (d.cifNweValue != null && size > 40)
              Text(
                formatNumber(d.cifNweValue, 0),
                style: TextStyle(fontSize: 8.5, color: published ? Colors.white70 : p.textMuted),
              ),
          ],
        ),
      ),
    );
  }

  static Color _statusColor(AppPalette p, String s) => switch (s) {
        'published' => p.success,
        'no_data' => p.danger,
        'not_published_yet' => p.warning,
        _ => p.textMuted,
      };

  Widget _list(List<Quotation> data, bool isAdmin) {
    final filtered = data
        .where((q) =>
            (_status.isEmpty || q.status == _status) &&
            (_source.isEmpty || q.source == _source) &&
            (_correction.isEmpty || (_correction == 'yes') == (q.originalValue != null)))
        .toList();
    if (filtered.isEmpty) {
      return EmptyState(
        data.isEmpty ? 'Aucune cotation' : 'Aucune cotation pour ces filtres',
        icon: Icons.insights_rounded,
      );
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
    final p = context.palette;
    final corrected = q.originalValue != null;
    final date = DateTime.parse(q.quotationDate.substring(0, 10));
    return ListCard(
      leading: Container(
        width: 44,
        height: 46,
        decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: p.textPrimary, height: 1.1),
            ),
            Text(monthShortLabels[date.month - 1], style: TextStyle(fontSize: 10.5, color: p.textMuted)),
          ],
        ),
      ),
      title: Row(
        children: [
          Text(q.product),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              q.source,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: p.textMuted),
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            StatusChip(quotationStatusLabels[q.status] ?? q.status, color: _statusColor(p, q.status)),
            if (corrected) StatusChip('Corrigée (orig. ${formatValue(q.originalValue)})', color: p.violet),
          ],
        ),
      ),
      footer: (q.correctionReason?.isNotEmpty ?? false)
          ? Text('Motif : ${q.correctionReason}', style: TextStyle(fontSize: 12, color: p.textMuted))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                q.cifNweValue != null ? formatValue(q.cifNweValue) : '—',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: p.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(r'$/T', style: TextStyle(fontSize: 11, color: p.textMuted)),
            ],
          ),
          if (isAdmin)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: p.textMuted),
              onSelected: (v) => v == 'correct' ? _correct(q) : _delete(q),
              itemBuilder: (_) => [
                if (q.status == 'published' && q.cifNweValue != null)
                  menuItem('correct', Icons.edit_outlined, 'Corriger'),
                menuItem('delete', Icons.delete_outline_rounded, 'Supprimer', danger: true),
              ],
            )
          else
            const SizedBox(width: 10),
        ],
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
          Text('Motif précédent : ${q.correctionReason}', style: TextStyle(color: context.palette.textMuted)),
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
        const InfoBanner(
          'Maximum 100 jours calendaires. Un seul backfill à la fois.',
          kind: BannerKind.info,
        ),
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

class _FiltersForm extends StatefulWidget {
  const _FiltersForm({required this.initial, required this.sources});

  final _Filters initial;
  final List<String> sources;

  @override
  State<_FiltersForm> createState() => _FiltersFormState();
}

class _FiltersFormState extends State<_FiltersForm> {
  late String _from = widget.initial.from;
  late String _to = widget.initial.to;
  late String _status = widget.initial.status;
  late String _source = widget.sources.contains(widget.initial.source) ? widget.initial.source : '';
  late String _correction = widget.initial.correction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: DateField(label: 'Du', value: _from, onChanged: (v) => setState(() => _from = v))),
            const SizedBox(width: 10),
            Expanded(child: DateField(label: 'Au', value: _to, onChanged: (v) => setState(() => _to = v))),
          ],
        ),
        const SizedBox(height: 12),
        LabeledDropdown<String>(
          label: 'Statut',
          icon: Icons.flag_outlined,
          value: _status,
          items: {'': 'Tous', ...quotationStatusLabels},
          onChanged: (v) => setState(() => _status = v),
        ),
        const SizedBox(height: 12),
        LabeledDropdown<String>(
          label: 'Source',
          icon: Icons.source_outlined,
          value: _source,
          items: {'': 'Toutes', for (final s in widget.sources) s: s},
          onChanged: (v) => setState(() => _source = v),
        ),
        const SizedBox(height: 12),
        LabeledDropdown<String>(
          label: 'Correction',
          icon: Icons.edit_note_rounded,
          value: _correction,
          items: const {'': 'Toutes', 'yes': 'Corrigées', 'no': 'Non corrigées'},
          onChanged: (v) => setState(() => _correction = v),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(
                  context,
                  (from: '', to: '', status: '', source: '', correction: ''),
                ),
                child: const Text('Réinitialiser'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  (from: _from, to: _to, status: _status, source: _source, correction: _correction),
                ),
                child: const Text('Appliquer'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}