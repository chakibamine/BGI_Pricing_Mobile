import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../models/models.dart';

const _creditOn = 0.0041;

class ConfigScreen extends ConsumerStatefulWidget {
  const ConfigScreen({super.key});

  @override
  ConsumerState<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends ConsumerState<ConfigScreen> {
  Product? _product;
  bool _history = false;

  void _refresh() {
    ref.invalidate(productConfigsProvider);
    invalidatePricing(ref);
  }

  @override
  Widget build(BuildContext context) {
    final configs = ref.watch(productConfigsProvider(_product));
    return Scaffold(
      appBar: AppBar(title: const Text('Configurations')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: AppColors.amber,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle config'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(productConfigsProvider);
          await ref.read(productConfigsProvider(_product).future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          children: [
            LabeledDropdown<Product?>(
              label: 'Produit',
              value: _product,
              items: const {null: 'Tous', Product.gasoil: 'Gasoil', Product.ssp: 'SSP'},
              onChanged: (p) => setState(() => _product = p),
            ),
            const SizedBox(height: 12),
            AsyncView(
              value: configs,
              onRetry: () => ref.invalidate(productConfigsProvider(_product)),
              builder: _content,
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(List<ProductConfig> data) {
    final today = isoDate(DateTime.now());
    final defaults = data.where((c) => c.isDefault).toList();
    final others = data.where((c) => !c.isDefault).toList();
    bool isPast(ProductConfig c) => c.validUntil != null && c.validUntil!.compareTo(today) < 0;
    final current = others.where((c) => !isPast(c)).toList();
    final history = others.where(isPast).toList();
    final shown = _history ? history : current;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          title: 'Tendance Platts',
          child: defaults.isEmpty
              ? const EmptyState('Aucune configuration par défaut')
              : Column(children: [for (final c in defaults) _card(c)]),
        ),
        const SizedBox(height: 12),
        Panel(
          title: 'Autres configurations',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: false, label: Text('En cours (${current.length})')),
                  ButtonSegment(value: true, label: Text('Historique (${history.length})')),
                ],
                selected: {_history},
                onSelectionChanged: (s) => setState(() => _history = s.first),
              ),
              const SizedBox(height: 8),
              if (shown.isEmpty)
                EmptyState(_history
                    ? 'Aucune configuration dans l’historique'
                    : 'Aucune configuration en cours')
              else
                for (final c in shown) _card(c),
            ],
          ),
        ),
      ],
    );
  }

  Widget _card(ProductConfig c) {
    Widget param(String label, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              Text(c.product.code, style: const TextStyle(color: AppColors.muted)),
              const SizedBox(width: 6),
              if (!c.isDefault)
                StatusChip(c.isActive ? 'Actif' : 'Inactif',
                    color: c.isActive ? AppColors.green : AppColors.muted),
              PopupMenuButton<String>(
                onSelected: (v) => _action(v, c),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Modifier')),
                  if (!c.isDefault && c.isActive)
                    const PopupMenuItem(value: 'default', child: Text('Définir par défaut')),
                  if (!c.isDefault)
                    PopupMenuItem(
                      value: c.isActive ? 'deactivate' : 'reactivate',
                      child: Text(c.isActive ? 'Désactiver' : 'Réactiver'),
                    ),
                  if (!c.isDefault)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Supprimer', style: TextStyle(color: AppColors.red)),
                    ),
                ],
              ),
            ],
          ),
          if (!c.isDefault)
            Text(
              c.validFrom != null && c.validUntil != null
                  ? '${formatDate(c.validFrom)} → ${formatDate(c.validUntil)}'
                  : '—',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              param(r'Premium ($/T)', formatValue(c.premium)),
              param('TIC (MAD/M³)', formatValue(c.tic)),
              param('Densité', formatValue(c.densityFactor)),
              param('Divers frais', formatValue(c.diversFrais)),
              param('Crédit droit', c.creditDroitRate > 0 ? formatValue(c.creditDroitRate) : 'Désactivé'),
            ],
          ),
          if (c.note?.isNotEmpty ?? false) ...[
            const SizedBox(height: 6),
            Text(c.note!, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }

  Future<void> _action(String action, ProductConfig c) async {
    final api = ref.read(apiClientProvider);
    switch (action) {
      case 'edit':
        final body = await showFormSheet<Map<String, dynamic>>(
          context,
          title: 'Modifier « ${c.name} » (${c.product.code})',
          builder: (_) => _ConfigForm(initial: c, defaults: const {}),
        );
        if (body == null || !mounted) return;
        await runAction(context, () => api.patch('/product-configs/${c.id}', body: body),
            success: 'Configuration mise à jour');
      case 'default':
        if (!await confirmDialog(
              context,
              'Définir « ${c.name} » comme config par défaut ${c.product.code} ? '
              'Toutes les quinzaines ${c.product.code} seront recalculées.',
            ) ||
            !mounted) {
          return;
        }
        await runAction(context, () => api.patch('/product-configs/${c.id}/default'),
            success: 'Configuration par défaut modifiée — quinzaines recalculées');
      case 'deactivate':
        await runAction(context, () => api.patch('/product-configs/${c.id}/deactivate'),
            success: 'Configuration désactivée');
      case 'reactivate':
        await runAction(context, () => api.patch('/product-configs/${c.id}/reactivate'),
            success: 'Configuration réactivée');
      case 'delete':
        if (!await confirmDialog(
              context,
              'Supprimer « ${c.name} » ? Ses résultats dans les quinzaines seront aussi supprimés.',
              confirmLabel: 'Supprimer',
              danger: true,
            ) ||
            !mounted) {
          return;
        }
        await runAction(context, () => api.delete('/product-configs/${c.id}'),
            success: 'Configuration supprimée');
    }
    _refresh();
  }

  Future<void> _create() async {
    final all = await runAction(context, () => ref.read(productConfigsProvider(null).future));
    if (all == null || !mounted) return;
    final defaults = {
      for (final p in Product.values) p: all.where((c) => c.product == p && c.isDefault).firstOrNull,
    };
    final body = await showFormSheet<Map<String, dynamic>>(
      context,
      title: 'Nouvelle configuration',
      builder: (_) => _ConfigForm(
        initial: null,
        defaults: defaults,
        initialProduct: _product ?? Product.gasoil,
      ),
    );
    if (body == null || !mounted) return;
    await runAction(context, () => ref.read(apiClientProvider).post('/product-configs', body: body),
        success: 'Configuration créée');
    _refresh();
  }
}

class _ConfigForm extends StatefulWidget {
  const _ConfigForm({
    required this.initial,
    required this.defaults,
    this.initialProduct = Product.gasoil,
  });

  /// Config being edited, or null for a creation.
  final ProductConfig? initial;

  /// Default config per product, used to prefill a creation.
  final Map<Product, ProductConfig?> defaults;
  final Product initialProduct;

  @override
  State<_ConfigForm> createState() => _ConfigFormState();
}

class _ConfigFormState extends State<_ConfigForm> {
  final _name = TextEditingController();
  final _premium = TextEditingController();
  final _tic = TextEditingController();
  final _density = TextEditingController();
  final _divers = TextEditingController();
  final _note = TextEditingController();
  late Product _product;
  String _from = '';
  String _until = '';
  bool _credit = false;

  bool get _editing => widget.initial != null;
  ProductConfig? get _source => _editing ? widget.initial : widget.defaults[_product];
  bool get _showRange => _editing ? !widget.initial!.isDefault : _source != null;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _product = i?.product ?? widget.initialProduct;
    if (i != null) {
      _name.text = i.name;
      _note.text = i.note ?? '';
      _from = i.validFrom ?? '';
      _until = i.validUntil ?? '';
    }
    _fillParams();
  }

  void _fillParams() {
    final s = _source;
    String v(double? x) => x == null ? '' : x.toString();
    _premium.text = v(s?.premium);
    _tic.text = v(s?.tic);
    _density.text = v(s?.densityFactor);
    _divers.text = s == null ? '0' : v(s.diversFrais);
    _credit = (s?.creditDroitRate ?? 0) > 0;
  }

  @override
  void dispose() {
    for (final c in [_name, _premium, _tic, _density, _divers, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final premium = parseDecimal(_premium.text);
    final tic = parseDecimal(_tic.text);
    final density = parseDecimal(_density.text);
    final divers = _divers.text.trim().isEmpty ? 0.0 : parseDecimal(_divers.text);
    if (_name.text.trim().isEmpty || premium == null || tic == null || density == null || divers == null) {
      showToast(context, 'Intitulé, premium, TIC et densité sont requis', error: true);
      return;
    }
    if (_showRange && (_from.isEmpty || _until.isEmpty)) {
      showToast(context, 'La période d’application est requise', error: true);
      return;
    }
    Navigator.pop(context, {
      'name': _name.text.trim(),
      if (!_editing) 'product': _product.code,
      'premium': premium,
      'tic': tic,
      'densityFactor': density,
      'diversFrais': divers,
      'creditDroitRate': _credit ? _creditOn : 0,
      if (_showRange) ...{'validFrom': _from, 'validUntil': _until},
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget numField(TextEditingController c, String label, {String? unit}) => TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: InputDecoration(labelText: label, suffixText: unit),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_editing) ...[
          InfoBanner(
            _source != null
                ? 'Paramètres pré-remplis depuis la config par défaut « ${_source!.name} ». '
                    'Les quinzaines de la période choisie seront calculées avec cette config '
                    'en plus de la config par défaut.'
                : 'Aucune config par défaut pour ce produit — celle-ci le deviendra.',
            color: AppColors.navy,
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _name,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Intitulé', hintText: 'Ex. Gasoil promo été'),
        ),
        const SizedBox(height: 4),
        IgnorePointer(
          ignoring: _editing,
          child: Opacity(
            opacity: _editing ? 0.6 : 1,
            child: ProductSelector(
              value: _product,
              onChanged: (p) => setState(() {
                _product = p;
                _fillParams();
              }),
            ),
          ),
        ),
        if (_showRange) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DateField(label: 'Du', value: _from, onChanged: (v) => setState(() => _from = v)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DateField(label: 'Au', value: _until, onChanged: (v) => setState(() => _until = v)),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: numField(_premium, 'Premium', unit: r'$/T')),
            const SizedBox(width: 8),
            Expanded(child: numField(_tic, 'TIC', unit: 'MAD/M³')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: numField(_density, 'Facteur densité')),
            const SizedBox(width: 8),
            Expanded(child: numField(_divers, 'Divers frais', unit: 'Dh TTC')),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Crédit de droit'),
          subtitle: const Text('Applique un taux de $_creditOn au calcul'),
          value: _credit,
          onChanged: (v) => setState(() => _credit = v),
        ),
        TextField(
          controller: _note,
          maxLength: 500,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Note', hintText: 'Commentaire facultatif'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _submit,
          child: Text(_editing ? 'Enregistrer' : 'Créer'),
        ),
      ],
    );
  }
}
