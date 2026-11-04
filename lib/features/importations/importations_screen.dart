import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/auth.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import 'importations_providers.dart';

class ImportationsScreen extends ConsumerStatefulWidget {
  const ImportationsScreen({super.key});

  @override
  ConsumerState<ImportationsScreen> createState() => _ImportationsScreenState();
}

class _ImportationsScreenState extends ConsumerState<ImportationsScreen> {
  bool _busy = false;

  Future<void> _create() async {
    final body = await showFormSheet<Map<String, dynamic>>(
      context,
      title: 'Nouvelle négociation',
      builder: (_) => const _CreateImportationForm(),
    );
    if (body == null || !mounted) return;
    setState(() => _busy = true);
    final res = await runAction(
      context,
      () async => await ref.read(apiClientProvider).post('/importations', body: body) as Json,
      success: 'Négociation créée',
    );
    if (mounted) setState(() => _busy = false);
    if (res == null || !mounted) return;
    invalidateImportations(ref);
    context.push('/more/importations/${res['id']}');
  }

  @override
  Widget build(BuildContext context) {
    final year = ref.watch(importationsYearProvider);
    final list = ref.watch(importationsListProvider(year));
    final isAdmin = ref.watch(isAdminProvider);
    final now = DateTime.now().year;

    return PageScaffold(
      title: 'Importations',
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Négociation'),
            )
          : null,
      onRefresh: () async {
        ref.invalidate(importationsListProvider(year));
        await ref.read(importationsListProvider(year).future);
      },
      filterBar: Row(
        children: [
          for (final y in [now + 1, now, now - 1, now - 2])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('$y'),
                selected: year == y,
                showCheckmark: false,
                onSelected: (_) => ref.read(importationsYearProvider.notifier).set(y),
              ),
            ),
        ],
      ),
      children: [
        AsyncView(
          value: list,
          onRetry: () => ref.invalidate(importationsListProvider(year)),
          builder: (rows) {
            if (rows.isEmpty) {
              return const EmptyState('Aucune importation', icon: Icons.local_shipping_outlined);
            }
            return Column(
              children: [
                for (final row in rows)
                  ListCard(
                    onTap: () => context.push('/more/importations/${row.id}'),
                    leading: IconBubble(
                      Icons.local_shipping_outlined,
                      color: row.status == 'confirmed'
                          ? context.palette.success
                          : context.palette.textMuted,
                      size: 40,
                    ),
                    title: Text(row.reference),
                    subtitle: Text(
                      '${row.supplierName ?? row.prospectName ?? 'Prospect'} · '
                      '${row.productLabel ?? row.productCode ?? 'Produit'}'
                      '${row.quantityMt != null ? ' · ${formatNumber(row.quantityMt, 0)} MT' : ''}',
                    ),
                    trailing: StatusChip(
                      row.statusLabel,
                      color: row.status == 'confirmed'
                          ? context.palette.success
                          : context.palette.textMuted,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CreateImportationForm extends StatefulWidget {
  const _CreateImportationForm();

  @override
  State<_CreateImportationForm> createState() => _CreateImportationFormState();
}

class _CreateImportationFormState extends State<_CreateImportationForm> {
  final _prospect = TextEditingController();
  final _supplier = TextEditingController();
  final _label = TextEditingController();
  final _qty = TextEditingController();
  final _dest = TextEditingController();
  String _product = '';
  String _eta = '';

  @override
  void dispose() {
    _prospect.dispose();
    _supplier.dispose();
    _label.dispose();
    _qty.dispose();
    _dest.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(controller: _prospect, decoration: const InputDecoration(labelText: 'Prospect')),
        const SizedBox(height: 10),
        TextField(controller: _supplier, decoration: const InputDecoration(labelText: 'Fournisseur')),
        const SizedBox(height: 10),
        LabeledDropdown<String>(
          label: 'Produit pricing',
          value: _product,
          items: const {'': '—', 'GASOIL': 'Gasoil', 'SSP': 'SSP'},
          onChanged: (v) => setState(() => _product = v),
        ),
        const SizedBox(height: 10),
        TextField(controller: _label, decoration: const InputDecoration(labelText: 'Libellé produit')),
        const SizedBox(height: 10),
        TextField(
          controller: _qty,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Quantité MT'),
        ),
        const SizedBox(height: 10),
        TextField(controller: _dest, decoration: const InputDecoration(labelText: 'Destination')),
        const SizedBox(height: 10),
        DateField(label: 'ETA', value: _eta, onChanged: (v) => setState(() => _eta = v)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            if (_prospect.text.trim().isNotEmpty) 'prospectName': _prospect.text.trim(),
            if (_supplier.text.trim().isNotEmpty) 'supplierName': _supplier.text.trim(),
            if (_product.isNotEmpty) 'productCode': _product,
            if (_label.text.trim().isNotEmpty) 'productLabel': _label.text.trim(),
            if (_qty.text.trim().isNotEmpty) 'quantityMt': _qty.text.trim(),
            if (_dest.text.trim().isNotEmpty) 'destination': _dest.text.trim(),
            if (_eta.isNotEmpty) 'eta': _eta,
          }),
          child: const Text('Créer'),
        ),
      ],
    );
  }
}
