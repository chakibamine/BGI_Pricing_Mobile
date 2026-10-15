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
    return PageScaffold(
      title: 'Configurations',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvelle config'),
      ),
      onRefresh: () async {
        ref.invalidate(productConfigsProvider);
        await ref.read(productConfigsProvider(_product).future);
      },
      filterBar: Row(
        children: [
          for (final e in const {null: 'Tous', Product.gasoil: 'Gasoil', Product.ssp: 'SSP'}.entries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(e.value),
                selected: _product == e.key,
                showCheckmark: false,
                onSelected: (_) => setState(() => _product = e.key),
              ),
            ),
        ],
      ),
      children: [
        AsyncView(
          value: configs,
          onRetry: () => ref.invalidate(productConfigsProvider(_product)),
          builder: _content,
        ),
      ],
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
          subtitle: 'Configuration par défaut de chaque produit',
          icon: Icons.star_rounded,
          child: defaults.isEmpty
              ? const EmptyState('Aucune configuration par défaut', icon: Icons.tune_rounded)
              : Column(children: [for (final c in defaults) _card(c)]),
        ),
        Panel(
          title: 'Autres configurations',
          subtitle: 'Appliquées sur une période',
          icon: Icons.layers_outlined,
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
              const SizedBox(height: 12),
              if (shown.isEmpty)
                EmptyState(
                  _history ? 'Aucune configuration dans l’historique' : 'Aucune configuration en cours',
                  icon: _history ? Icons.history_rounded : Icons.layers_clear_outlined,
                )
              else
                for (final c in shown) _card(c),
            ],
          ),
        ),
      ],
    );
  }

  Widget _card(ProductConfig c) {
    final p = context.palette;
    Widget param(String label, String value) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 10.5, color: p.textMuted)),
              const SizedBox(height: 1),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 12),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: c.isDefault ? Border.all(color: p.accent.withValues(alpha: 0.5)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBubble(
                c.isDefault ? Icons.star_rounded : Icons.layers_outlined,
                color: c.isDefault ? p.accent : p.info,
                size: 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: TextStyle(fontWeight: FontWeight.w700, color: p.textPrimary)),
                    Text(
                      c.isDefault
                          ? '${c.product.code} · par défaut'
                          : '${c.product.code} · ${c.validFrom != null && c.validUntil != null ? '${formatDate(c.validFrom)} → ${formatDate(c.validUntil)}' : '—'}',
                      style: TextStyle(fontSize: 12, color: p.textMuted),
                    ),
                  ],
                ),
              ),
              if (!c.isDefault)
                StatusChip(c.isActive ? 'Actif' : 'Inactif', color: c.isActive ? p.success : p.textMuted),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: p.textMuted),
                onSelected: (v) => _action(v, c),
                itemBuilder: (_) => [
                  menuItem('edit', Icons.edit_outlined, 'Modifier'),
                  if (!c.isDefault && c.isActive) menuItem('default', Icons.star_outline_rounded, 'Définir par défaut'),
                  if (!c.isDefault)
                    menuItem(
                      c.isActive ? 'deactivate' : 'reactivate',
                      c.isActive ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded,
                      c.isActive ? 'Désactiver' : 'Réactiver',
                    ),
                  if (!c.isDefault) menuItem('delete', Icons.delete_outline_rounded, 'Supprimer', danger: true),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
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
            Text(c.note!, style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: p.textMuted)),
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
            kind: BannerKind.info,
          ),
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
