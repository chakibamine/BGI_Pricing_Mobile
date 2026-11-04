import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../models/models.dart';

const _kindLabels = {
  'new': 'Nouveau',
  'changed': 'Modifié',
  'same': 'Identique',
  'no_data': 'Indisponible',
  'error': 'Erreur',
};

Color _kindColor(AppPalette p, String kind) => switch (kind) {
      'new' => p.success,
      'changed' => p.warning,
      'error' => p.danger,
      _ => p.textMuted,
    };

Future<PlatformFile?> _pickSpreadsheet(BuildContext context) async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['xlsx', 'xls', 'csv'],
  );
  if (file == null) return null;
  if (!RegExp(r'\.(xlsx|xls|csv)$', caseSensitive: false).hasMatch(file.name) ||
      file.path == null) {
    if (context.mounted) showToast(context, 'Formats acceptés : Excel ou CSV', error: true);
    return null;
  }
  return file;
}

class ImportScreen extends StatelessWidget {
  const ImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageScaffold(
      title: 'Import',
      children: [
        _QuotationsImport(),
        _RatesImport(),
        _BkamPanel(),
      ],
    );
  }
}

class _ReportBlock extends StatelessWidget {
  const _ReportBlock(this.report);

  final ImportReport report;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget stat(String label, int value, Color color) => Expanded(
          child: Column(
            children: [
              Text('$value', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
              Text(label, style: TextStyle(fontSize: 11.5, color: p.textMuted)),
            ],
          ),
        );
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              stat('Insérés', report.inserted, p.success),
              stat('Mis à jour', report.updated, p.info),
              stat('Ignorés', report.skipped, p.textMuted),
            ],
          ),
          if (report.errors.isNotEmpty) const SizedBox(height: 8),
          for (final e in report.errors)
            Text('• $e', style: TextStyle(fontSize: 12, color: p.danger)),
        ],
      ),
    );
  }
}

class _QuotationsImport extends ConsumerStatefulWidget {
  const _QuotationsImport();

  @override
  ConsumerState<_QuotationsImport> createState() => _QuotationsImportState();
}

class _QuotationsImportState extends ConsumerState<_QuotationsImport> {
  Product _product = Product.gasoil;
  bool _recalculate = true;
  PlatformFile? _file;
  bool _busy = false;
  ImportReport? _report;

  Future<void> _submit() async {
    final f = _file;
    if (f == null) {
      showToast(context, 'Fichier requis', error: true);
      return;
    }
    setState(() => _busy = true);
    final res = await runAction(
      context,
      () async => ImportReport.fromJson(await ref.read(apiClientProvider).upload(
            '/import/quotations',
            filePath: f.path!,
            fileName: f.name,
            query: {'product': _product.code, 'recalculate': '$_recalculate'},
          ) as Json),
      success: 'Import cotations terminé',
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res != null) _report = res;
    });
    if (res != null) invalidatePricing(ref);
  }

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Cotations CIF NWE',
      subtitle: 'Colonnes : Date | Valeur CIF NWE',
      icon: Icons.insights_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProductSelector(value: _product, onChanged: (p) => setState(() => _product = p)),
          const SizedBox(height: 10),
          _FileRow(
            file: _file,
            onPick: () async {
              final f = await _pickSpreadsheet(context);
              if (f != null) setState(() => _file = f);
            },
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _recalculate,
            title: const Text('Recalculer les quinzaines impactées'),
            onChanged: (v) => setState(() => _recalculate = v ?? true),
          ),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'Import…' : 'Importer'),
          ),
          if (_report != null) _ReportBlock(_report!),
        ],
      ),
    );
  }
}

class _RatesImport extends ConsumerStatefulWidget {
  const _RatesImport();

  @override
  ConsumerState<_RatesImport> createState() => _RatesImportState();
}

class _RatesImportState extends ConsumerState<_RatesImport> {
  PlatformFile? _file;
  bool _busy = false;
  ImportReport? _report;

  Future<void> _submit() async {
    final f = _file;
    if (f == null) {
      showToast(context, 'Fichier requis', error: true);
      return;
    }
    setState(() => _busy = true);
    final res = await runAction(
      context,
      () async => ImportReport.fromJson(await ref
          .read(apiClientProvider)
          .upload('/import/exchange-rates', filePath: f.path!, fileName: f.name) as Json),
      success: 'Import taux terminé',
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res != null) _report = res;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Taux de change',
      subtitle: '2 colonnes (Date, Taux) ou 3 colonnes (Date, Devise, Taux)',
      icon: Icons.currency_exchange_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FileRow(
            file: _file,
            onPick: () async {
              final f = await _pickSpreadsheet(context);
              if (f != null) setState(() => _file = f);
            },
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: Text(_busy ? 'Import…' : 'Importer'),
          ),
          if (_report != null) _ReportBlock(_report!),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.onPick});

  final PlatformFile? file;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final picked = file != null;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: picked ? p.tint(p.success) : p.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: picked ? p.success.withValues(alpha: 0.5) : p.border),
        ),
        child: Row(
          children: [
            Icon(
              picked ? Icons.description_rounded : Icons.upload_file_rounded,
              color: picked ? p.success : p.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                file?.name ?? 'Choisir un fichier (.xlsx / .csv)',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: picked ? FontWeight.w600 : FontWeight.w400,
                  color: picked ? p.textPrimary : p.textMuted,
                ),
              ),
            ),
            if (picked) Icon(Icons.swap_horiz_rounded, size: 18, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}

class _BkamPanel extends ConsumerStatefulWidget {
  const _BkamPanel();

  @override
  ConsumerState<_BkamPanel> createState() => _BkamPanelState();
}

class _BkamPanelState extends ConsumerState<_BkamPanel> {
  String _from = '';
  String _to = '';
  String _source = 'api';
  String? _previewSource;
  List<BkamPreviewRow>? _rows;
  Set<String> _selected = {};
  bool _busy = false;
  bool _fetching = false;
  ImportReport? _report;
  ({int done, int total, String? currentDate})? _progress;
  Timer? _progressTimer;

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  void _startProgressPolling() {
    _progressTimer?.cancel();
    _progress = null;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      try {
        final res = await ref.read(apiClientProvider).get(
              '/import/exchange-rates/fetch-preview/progress',
            ) as Json;
        if (!mounted) return;
        setState(() {
          _progress = (
            done: (res['done'] as num?)?.toInt() ?? 0,
            total: (res['total'] as num?)?.toInt() ?? 0,
            currentDate: res['currentDate'] as String?,
          );
        });
      } catch (_) {
        // Progress is best-effort while the long fetch runs.
      }
    });
  }

  void _stopProgressPolling() {
    _progressTimer?.cancel();
    _progressTimer = null;
    if (mounted) setState(() => _progress = null);
  }

  Future<void> _fetch({List<String>? onlyDates}) async {
    if (_from.isEmpty || _to.isEmpty) {
      showToast(context, 'Période requise', error: true);
      return;
    }
    if (_from.compareTo(_to) > 0) {
      showToast(context, 'La date de début doit précéder la date de fin', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _fetching = true;
      _report = null;
    });
    _startProgressPolling();
    final res = await runAction(
      context,
      () async => await ref.read(apiClientProvider).post(
            '/import/exchange-rates/fetch-preview',
            body: {
              'dateFrom': _from,
              'dateTo': _to,
              'source': _source,
              'dates': ?onlyDates,
            },
          ) as Json,
    );
    _stopProgressPolling();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _fetching = false;
    });
    if (res == null) return;
    final fetched =
        (res['rows'] as List).map((e) => BkamPreviewRow.fromJson(e as Json)).toList();
    setState(() {
      if (onlyDates != null && _rows != null) {
        final updated = {for (final r in fetched) r.date: r};
        _rows = [for (final r in _rows!) updated[r.date] ?? r];
        _selected = {
          ..._selected,
          for (final r in fetched)
            if (r.kind == 'new' || r.kind == 'changed') r.date,
        };
      } else {
        _rows = fetched;
        _previewSource = _source;
        _selected = {
          for (final r in fetched)
            if (r.kind == 'new' || r.kind == 'changed') r.date,
        };
      }
    });
    if (onlyDates == null && fetched.isEmpty) {
      showToast(context, 'Aucun jour ouvré dans cette période', error: true);
    } else if (onlyDates != null) {
      final recovered = fetched.where((r) => r.status == 'ok').length;
      final stillMissing =
          fetched.where((r) => r.status == 'no_data' || r.rate == null).length;
      if (recovered > 0) {
        showToast(
          context,
          '$recovered taux récupéré(s)${stillMissing > 0 ? ', $stillMissing encore indisponible(s)' : ''}',
        );
      } else if (stillMissing > 0) {
        showToast(context, 'Toujours indisponibles', error: true);
      } else {
        showToast(context, 'Nouvelle tentative terminée');
      }
    }
  }

  Future<void> _retryUnavailable() async {
    final dates = [
      for (final r in _rows ?? const <BkamPreviewRow>[])
        if (r.kind == 'no_data') r.date,
    ];
    if (dates.isEmpty) {
      showToast(context, 'Aucun jour indisponible à réessayer', error: true);
      return;
    }
    await _fetch(onlyDates: dates);
  }

  Future<void> _save() async {
    final rows = [
      for (final r in _rows ?? const <BkamPreviewRow>[])
        if (r.rate != null && _selected.contains(r.date)) {'date': r.date, 'rate': r.rate},
    ];
    if (rows.isEmpty) {
      showToast(context, 'Aucun taux sélectionné', error: true);
      return;
    }
    final savedRates = {
      for (final r in rows) r['date'] as String: r['rate'] as double,
    };
    setState(() => _busy = true);
    final res = await runAction(
      context,
      () async => ImportReport.fromJson(await ref.read(apiClientProvider).post(
            '/import/exchange-rates/confirm',
            body: {'source': _previewSource, 'rows': rows},
          ) as Json),
      success: 'Taux enregistrés. Vous pouvez réessayer les indisponibles.',
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res != null) {
        _report = res;
        // Keep Indisponible / erreurs so they can be retried after saving.
        _rows = [
          for (final r in _rows ?? const <BkamPreviewRow>[])
            if (savedRates.containsKey(r.date))
              BkamPreviewRow(
                r.date,
                savedRates[r.date],
                'ok',
                null,
                savedRates[r.date],
              )
            else
              r,
        ];
        _selected = {};
      }
    });
    if (res != null) invalidatePricing(ref);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final selectable = rows?.where((r) => r.selectable).toList() ?? const [];
    final counts = <String, int>{for (final k in _kindLabels.keys) k: 0};
    for (final r in rows ?? const <BkamPreviewRow>[]) {
      counts[r.kind] = counts[r.kind]! + 1;
    }

    return Panel(
      title: 'Bank Al-Maghrib',
      subtitle: 'Récupération des taux USD/MAD',
      icon: Icons.account_balance_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const InfoBanner(
            'Maximum 365 jours calendaires. Les week-ends sont ignorés. '
            'Rien n’est enregistré avant validation de l’aperçu. '
            'Une année entière peut prendre plusieurs minutes.',
            kind: BannerKind.info,
          ),
          Row(
            children: [
              Expanded(child: DateField(label: 'Du', value: _from, onChanged: (v) => setState(() => _from = v))),
              const SizedBox(width: 8),
              Expanded(child: DateField(label: 'Au', value: _to, onChanged: (v) => setState(() => _to = v))),
            ],
          ),
          RadioGroup<String>(
            groupValue: _source,
            onChanged: (v) {
              if (!_busy && v != null) setState(() => _source = v);
            },
            child: const Column(
              children: [
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'web',
                  title: Text('Site web BKAM (scraping)'),
                ),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'api',
                  title: Text('API officielle (BDT)'),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: _busy ? null : _fetch,
            child: Text(
              _fetching
                  ? (_progress != null && _progress!.total > 0
                      ? 'Récupération… ${_progress!.done}/${_progress!.total}'
                      : 'Récupération…')
                  : 'Récupérer',
            ),
          ),
          if (_fetching) ...[
            const SizedBox(height: 8),
            Text(
              _progress != null && _progress!.total > 0
                  ? 'Jour ${_progress!.done} sur ${_progress!.total}'
                      '${_progress!.currentDate != null ? ' (${formatDate(_progress!.currentDate)})' : ''}'
                  : 'Récupération en cours…',
              style: TextStyle(fontSize: 12.5, color: context.palette.textMuted),
            ),
            if (_progress != null && _progress!.total > 0) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: _progress!.done / _progress!.total,
              ),
            ],
          ],
          if (rows != null && rows.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '${rows.length} jour(s) — Nouveaux : ${counts['new']} — Modifiés : ${counts['changed']} — '
              'Identiques : ${counts['same']} — Indisponibles : ${counts['no_data']} — Erreurs : ${counts['error']}',
              style: const TextStyle(fontSize: 12.5),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Tout sélectionner'),
              value: selectable.isNotEmpty && _selected.length == selectable.length,
              onChanged: selectable.isEmpty || _busy
                  ? null
                  : (_) => setState(() {
                        _selected = _selected.length == selectable.length
                            ? {}
                            : {for (final r in selectable) r.date};
                      }),
            ),
            const Divider(height: 1),
            for (final r in rows)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                value: _selected.contains(r.date),
                enabled: r.selectable && !_busy,
                onChanged: r.selectable
                    ? (v) => setState(() {
                          if (v ?? false) {
                            _selected.add(r.date);
                          } else {
                            _selected.remove(r.date);
                          }
                        })
                    : null,
                title: Row(
                  children: [
                    Text(formatDate(r.date), style: const TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    StatusChip(_kindLabels[r.kind]!, color: _kindColor(context.palette, r.kind)),
                  ],
                ),
                subtitle: Text(
                  'Récupéré : ${formatValue(r.rate)} · Actuel : ${formatValue(r.existingRate)}'
                  '${r.message != null ? '\n${r.message}' : ''}',
                ),
              ),
            const SizedBox(height: 8),
            if ((counts['no_data'] ?? 0) > 0) ...[
              OutlinedButton(
                onPressed: _busy ? null : _retryUnavailable,
                child: Text('Réessayer les indisponibles (${counts['no_data']})'),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _rows = null;
                              _selected = {};
                            }),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy || _selected.isEmpty ? null : _save,
                    child: Text(_busy ? 'Enregistrement…' : 'Enregistrer (${_selected.length})'),
                  ),
                ),
              ],
            ),
          ],
          if (_report != null) _ReportBlock(_report!),
        ],
      ),
    );
  }
}
