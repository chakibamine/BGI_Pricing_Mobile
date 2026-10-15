import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';

const _pageSize = 25;

const _actionLabels = {
  'CREATE': 'Création',
  'UPDATE': 'Modification',
  'DELETE': 'Suppression',
  'BKAM_FETCH': 'Fetch BKAM',
  'PLATTS_FETCH': 'Fetch Platts',
};

const _tableLabels = {
  'quotations': 'Cotations',
  'exchange_rates': 'Taux de change',
  'product_configs': 'Configuration',
  'users': 'Utilisateurs',
};

Color _actionColor(AppPalette p, String action) => switch (action) {
      'CREATE' => p.success,
      'UPDATE' => p.warning,
      'DELETE' => p.danger,
      'BKAM_FETCH' || 'PLATTS_FETCH' => p.info,
      _ => p.textMuted,
    };

IconData _actionIcon(String action) => switch (action) {
      'CREATE' => Icons.add_circle_outline_rounded,
      'UPDATE' => Icons.edit_outlined,
      'DELETE' => Icons.delete_outline_rounded,
      'BKAM_FETCH' || 'PLATTS_FETCH' => Icons.cloud_download_outlined,
      _ => Icons.history_rounded,
    };

typedef _Filters = ({String action, String table, String from, String to});

typedef _AuditKey = ({String action, String table, String from, String to});

final _auditProvider = FutureProvider.autoDispose.family<List<AuditLog>, _AuditKey>((ref, k) async {
  final res = await ref.watch(apiClientProvider).get('/audit', query: {
    'action': k.action,
    'table': k.table,
    'dateFrom': k.from,
    'dateTo': k.to,
  });
  return (res as List).map((e) => AuditLog(e as Json)).toList();
});

String _dateTime(String iso) {
  final time = iso.length >= 19 ? iso.substring(11, 19) : '';
  return '${formatDate(iso)} $time'.trim();
}

String _prettyJson(Object? raw) {
  if (raw == null || raw == '') return '—';
  Object? value = raw;
  if (raw is String) {
    try {
      value = jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }
  if (value is String) return value;
  return const JsonEncoder.withIndent('  ').convert(value);
}

class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  String _action = '';
  String _table = '';
  String _from = '';
  String _to = '';
  int _page = 1;

  _AuditKey get _key => (action: _action, table: _table, from: _from, to: _to);
  bool get _hasFilters => _action.isNotEmpty || _table.isNotEmpty || _from.isNotEmpty || _to.isNotEmpty;

  void _update(VoidCallback change) => setState(() {
        change();
        _page = 1;
      });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final logs = ref.watch(_auditProvider(_key));
    final count = [_action, _table, _from, _to].where((v) => v.isNotEmpty).length;
    return PageScaffold(
      title: 'Journal d’audit',
      onRefresh: () => ref.refresh(_auditProvider(_key).future),
      filterBar: Row(
        children: [
          Expanded(
            child: Text(
              logs.hasValue
                  ? '${logs.value!.length} ${logs.value!.length <= 1 ? 'entrée' : 'entrées'}${_hasFilters ? ' (filtrées)' : ''}'
                  : '',
              style: TextStyle(color: p.textMuted, fontWeight: FontWeight.w500),
            ),
          ),
          Badge(
            isLabelVisible: count > 0,
            label: Text('$count'),
            backgroundColor: p.accent,
            child: OutlinedButton.icon(
              onPressed: _openFilters,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Filtres'),
            ),
          ),
        ],
      ),
      children: [
        AsyncView(
          value: logs,
          onRetry: () => ref.invalidate(_auditProvider(_key)),
          builder: _list,
        ),
      ],
    );
  }

  Future<void> _openFilters() async {
    final result = await showFormSheet<_Filters>(
      context,
      title: 'Filtres',
      builder: (_) => _FiltersForm(initial: (action: _action, table: _table, from: _from, to: _to)),
    );
    if (result == null) return;
    _update(() {
      _action = result.action;
      _table = result.table;
      _from = result.from;
      _to = result.to;
    });
  }

  Widget _list(List<AuditLog> data) {
    final p = context.palette;
    if (data.isEmpty) {
      return EmptyState(
        _hasFilters
            ? 'Aucune entrée pour ces filtres. Essayez d’élargir la période ou de réinitialiser.'
            : 'Aucune entrée d’audit pour le moment.',
        icon: Icons.history_rounded,
      );
    }
    final totalPages = (data.length / _pageSize).ceil().clamp(1, 1 << 30);
    final page = _page.clamp(1, totalPages);
    final start = (page - 1) * _pageSize;
    final rows = data.sublist(start, (start + _pageSize).clamp(0, data.length));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows)
          ListCard(
            onTap: () => _detail(row),
            leading: IconBubble(_actionIcon(row.action), color: _actionColor(p, row.action), size: 40),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_tableLabels[row.tableName] ?? row.tableName} #${row.recordId ?? '—'}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                StatusChip(
                  _actionLabels[row.action] ?? row.action,
                  color: _actionColor(p, row.action),
                  dot: false,
                ),
              ],
            ),
            subtitle: Text(
              '${_dateTime(row.createdAt)} · ${row.username}'
              '${(row.description?.trim().isNotEmpty ?? false) ? '\n${row.description!.trim()}' : ''}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Text(
                '${start + 1}–${start + rows.length} sur ${data.length}',
                style: TextStyle(fontSize: 12, color: p.textMuted),
              ),
              const Spacer(),
              IconButton(
                onPressed: page <= 1 ? null : () => setState(() => _page = page - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              Text('Page $page / $totalPages'),
              IconButton(
                onPressed: page >= totalPages ? null : () => setState(() => _page = page + 1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _detail(AuditLog row) {
    final p = context.palette;
    Widget meta(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(label, style: TextStyle(color: p.textMuted, fontSize: 12.5)),
              ),
              Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
            ],
          ),
        );

    Widget jsonBlock(String title, Object? raw) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: p.textPrimary)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.border),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  _prettyJson(raw),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
                ),
              ),
            ),
          ],
        );

    showFormSheet<void>(
      context,
      title: 'Détail de l’entrée d’audit',
      builder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          meta('Date', _dateTime(row.createdAt)),
          meta('Action', _actionLabels[row.action] ?? row.action),
          meta('Entité', _tableLabels[row.tableName] ?? row.tableName),
          meta('Enregistrement', row.recordId ?? '—'),
          meta('Utilisateur', row.username),
          meta('Description', row.description?.trim().isNotEmpty ?? false ? row.description!.trim() : '—'),
          jsonBlock('Avant', row.dataBefore),
          jsonBlock('Après', row.dataAfter),
        ],
      ),
    );
  }
}

class _FiltersForm extends StatefulWidget {
  const _FiltersForm({required this.initial});

  final _Filters initial;

  @override
  State<_FiltersForm> createState() => _FiltersFormState();
}

class _FiltersFormState extends State<_FiltersForm> {
  late String _action = widget.initial.action;
  late String _table = widget.initial.table;
  late String _from = widget.initial.from;
  late String _to = widget.initial.to;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LabeledDropdown<String>(
          label: 'Action',
          icon: Icons.bolt_rounded,
          value: _action,
          items: {'': 'Toutes', ..._actionLabels},
          onChanged: (v) => setState(() => _action = v),
        ),
        const SizedBox(height: 12),
        LabeledDropdown<String>(
          label: 'Entité',
          icon: Icons.category_outlined,
          value: _table,
          items: {'': 'Toutes', ..._tableLabels},
          onChanged: (v) => setState(() => _table = v),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: DateField(label: 'Du', value: _from, onChanged: (v) => setState(() => _from = v))),
            const SizedBox(width: 10),
            Expanded(child: DateField(label: 'Au', value: _to, onChanged: (v) => setState(() => _to = v))),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, (action: '', table: '', from: '', to: '')),
                child: const Text('Réinitialiser'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context, (action: _action, table: _table, from: _from, to: _to)),
                child: const Text('Appliquer'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}