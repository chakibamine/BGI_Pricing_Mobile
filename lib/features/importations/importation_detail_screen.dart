import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/auth.dart';
import '../../core/export.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import 'importations_providers.dart';

class ImportationDetailScreen extends ConsumerStatefulWidget {
  const ImportationDetailScreen({super.key, required this.id});

  final int id;

  @override
  ConsumerState<ImportationDetailScreen> createState() => _ImportationDetailScreenState();
}

class _ImportationDetailScreenState extends ConsumerState<ImportationDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  bool _busy = false;
  DealRecapPayload? _payload;
  int? _payloadRecapId;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _saveNego(ImportationDetail d) async {
    final body = await showFormSheet<Map<String, dynamic>>(
      context,
      title: 'Modifier la négociation',
      builder: (_) => _EditNegoForm(detail: d),
    );
    if (body == null || !mounted) return;
    setState(() => _busy = true);
    await runAction(
      context,
      () => ref.read(apiClientProvider).patch('/importations/${widget.id}', body: body),
      success: 'Négociation enregistrée',
    );
    invalidateImportations(ref);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _saveRecap() async {
    if (_payload == null) return;
    setState(() => _busy = true);
    await runAction(
      context,
      () => ref.read(apiClientProvider).post(
            '/importations/${widget.id}/recaps',
            body: _payload!.toJson(),
          ),
      success: 'Deal recap enregistré',
    );
    invalidateImportations(ref);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _export(DealRecapVersion recap, String format) async {
    setState(() => _busy = true);
    await runAction(context, () async {
      final file = await ref.read(apiClientProvider).download(
            '/importations/${widget.id}/recaps/${recap.id}/export',
            query: {'format': format},
            fallbackName: 'deal-recap-v${recap.version}.$format',
          );
      if (mounted) await saveAndOffer(context, file.bytes, file.filename);
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _sealProper(DealRecapVersion recap) async {
    final ok = await confirmDialog(
      context,
      'Sceller ce deal recap et confirmer le dossier ?',
      confirmLabel: 'Sceller',
    );
    if (!ok || !mounted) return;
    final noteCtrl = TextEditingController();
    String? filePath;
    String? fileName;
    final confirmed = await showFormSheet<bool>(
      context,
      title: 'Preuve de scellement',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'Note / référence mail'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final f = await FilePicker.pickFile();
                if (f?.path == null) return;
                setSheet(() {
                  filePath = f!.path;
                  fileName = f.name;
                });
              },
              icon: const Icon(Icons.attach_file_rounded),
              label: Text(fileName ?? 'Joindre un fichier'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sceller'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    await runAction(context, () async {
      final map = <String, dynamic>{
        if (noteCtrl.text.trim().isNotEmpty) 'sealProofNote': noteCtrl.text.trim(),
        if (filePath != null && fileName != null)
          'file': await MultipartFile.fromFile(filePath!, filename: fileName),
      };
      await ref.read(apiClientProvider).post(
            '/importations/${widget.id}/recaps/${recap.id}/seal',
            body: FormData.fromMap(map),
          );
    }, success: 'Deal recap scellé');
    invalidateImportations(ref);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(importationDetailProvider(widget.id));
    final isAdmin = ref.watch(isAdminProvider);
    final p = context.palette;

    return detail.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Importation')),
        body: Center(child: Text(errorMessage(e))),
      ),
      data: (d) {
        final list = d.list;
        final recap = d.latestRecap;
        if (recap != null && _payloadRecapId != recap.id) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _payload = DealRecapPayload(Map<String, dynamic>.from(recap.payload.data));
              _payloadRecapId = recap.id;
            });
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(list.reference),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.pop(),
            ),
            actions: [
              if (isAdmin && recap != null && !recap.sealed)
                IconButton(
                  tooltip: 'Enregistrer recap',
                  onPressed: _busy ? null : _saveRecap,
                  icon: const Icon(Icons.save_outlined),
                ),
            ],
            bottom: TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Négociation'),
                Tab(text: 'Deal recap'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabs,
            children: [
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Panel(
                    title: list.statusLabel,
                    subtitle: '${list.supplierName ?? list.prospectName ?? '—'} · ${list.productLabel ?? list.productCode ?? '—'}',
                    icon: Icons.handshake_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Quantité : ${list.quantityMt != null ? '${formatNumber(list.quantityMt, 0)} MT' : '—'}'),
                        Text('Destination : ${list.destination ?? '—'}'),
                        Text('ETA : ${list.eta != null ? formatDate(list.eta) : '—'}'),
                        if (d.negotiationNotes != null && d.negotiationNotes!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(d.negotiationNotes!),
                        ],
                        if (isAdmin) ...[
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _busy ? null : () => _saveNego(d),
                            child: const Text('Modifier'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (recap == null)
                    const EmptyState('Aucun deal recap')
                  else ...[
                    Panel(
                      title: 'Deal recap v${recap.version}',
                      subtitle: recap.sealed ? 'Scellé' : 'Brouillon',
                      icon: Icons.description_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: _busy ? null : () => _export(recap, 'xlsx'),
                                child: const Text('Excel'),
                              ),
                              OutlinedButton(
                                onPressed: _busy ? null : () => _export(recap, 'pdf'),
                                child: const Text('PDF'),
                              ),
                            ],
                          ),
                          if (isAdmin && !recap.sealed && _payload != null) ...[
                            const SizedBox(height: 12),
                            for (final key in const [
                              'title',
                              'seller',
                              'buyer',
                              'productLabel',
                              'specAdditional',
                              'quantity',
                              'incoterm',
                              'destination',
                              'premium',
                              'plattsCode',
                              'currency',
                              'other',
                              'hierarchy',
                            ])
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: TextFormField(
                                  initialValue: _payload!.getStr(key),
                                  decoration: InputDecoration(labelText: key),
                                  onChanged: (v) => _payload!.setStr(key, v),
                                  maxLines: key == 'other' ? 3 : 1,
                                ),
                              ),
                            FilledButton(
                              onPressed: _busy ? null : _saveRecap,
                              child: const Text('Enregistrer le recap'),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.tonal(
                              onPressed: _busy ? null : () => _sealProper(recap),
                              child: const Text('Sceller'),
                            ),
                          ],
                          if (recap.sealed) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Scellé${recap.sealedAt != null ? ' le ${formatDate(recap.sealedAt)}' : ''}'
                              '${recap.sealProofNote != null ? ' — ${recap.sealProofNote}' : ''}',
                              style: TextStyle(color: p.textMuted),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EditNegoForm extends StatefulWidget {
  const _EditNegoForm({required this.detail});
  final ImportationDetail detail;

  @override
  State<_EditNegoForm> createState() => _EditNegoFormState();
}

class _EditNegoFormState extends State<_EditNegoForm> {
  late final _prospect = TextEditingController(text: widget.detail.list.prospectName ?? '');
  late final _supplier = TextEditingController(text: widget.detail.list.supplierName ?? '');
  late final _label = TextEditingController(text: widget.detail.list.productLabel ?? '');
  late final _qty = TextEditingController(
    text: widget.detail.list.quantityMt?.toString() ?? '',
  );
  late final _dest = TextEditingController(text: widget.detail.list.destination ?? '');
  late final _notes = TextEditingController(text: widget.detail.negotiationNotes ?? '');
  late String _product = widget.detail.list.productCode ?? '';
  late String _eta = widget.detail.list.eta ?? '';

  @override
  void dispose() {
    _prospect.dispose();
    _supplier.dispose();
    _label.dispose();
    _qty.dispose();
    _dest.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(controller: _prospect, decoration: const InputDecoration(labelText: 'Prospect')),
        const SizedBox(height: 8),
        TextField(controller: _supplier, decoration: const InputDecoration(labelText: 'Fournisseur')),
        const SizedBox(height: 8),
        LabeledDropdown<String>(
          label: 'Produit',
          value: _product,
          items: const {'': '—', 'GASOIL': 'Gasoil', 'SSP': 'SSP'},
          onChanged: (v) => setState(() => _product = v),
        ),
        const SizedBox(height: 8),
        TextField(controller: _label, decoration: const InputDecoration(labelText: 'Libellé')),
        const SizedBox(height: 8),
        TextField(controller: _qty, decoration: const InputDecoration(labelText: 'Quantité MT')),
        const SizedBox(height: 8),
        TextField(controller: _dest, decoration: const InputDecoration(labelText: 'Destination')),
        const SizedBox(height: 8),
        DateField(label: 'ETA', value: _eta, onChanged: (v) => setState(() => _eta = v)),
        const SizedBox(height: 8),
        TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes')),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            'prospectName': _prospect.text.trim(),
            'supplierName': _supplier.text.trim(),
            'productCode': _product.isEmpty ? null : _product,
            'productLabel': _label.text.trim(),
            'quantityMt': _qty.text.trim().isEmpty ? null : _qty.text.trim(),
            'destination': _dest.text.trim(),
            'eta': _eta.isEmpty ? null : _eta,
            'negotiationNotes': _notes.text.trim(),
          }),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
