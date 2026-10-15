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

Color _actionColor(String action) => switch (action) {
      'CREATE' => AppColors.green,
      'UPDATE' => AppColors.amber,
      'DELETE' => AppColors.red,
      'BKAM_FETCH' || 'PLATTS_FETCH' => const Color(0xFF2563EB),
      _ => AppColors.muted,
    };

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
    final logs = ref.watch(_auditProvider(_key));
    return Scaffold(
      appBar: AppBar(title: const Text('Journal d’audit')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(_auditProvider(_key).future),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: LabeledDropdown<String>(
                          label: 'Action',
                          value: _action,
                          items: {'': 'Toutes', ..._actionLabels},
                          onChanged: (v) => _update(() => _action = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: LabeledDropdown<String>(
                          label: 'Entité',
                          value: _table,
                          items: {'': 'Toutes', ..._tableLabels},
                          onChanged: (v) => _update(() => _table = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: DateField(label: 'Du', value: _from, onChanged: (v) => _update(() => _from = v))),
                      const SizedBox(width: 8),
                      Expanded(child: DateField(label: 'Au', value: _to, onChanged: (v) => _update(() => _to = v))),
                    ],
                  ),
                  if (_hasFilters)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => _update(() => _action = _table = _from = _to = ''),
                        child: const Text('Réinitialiser'),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AsyncView(
              value: logs,
              onRetry: () => ref.invalidate(_auditProvider(_key)),
              builder: _list,
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(List<AuditLog> data) {
    if (data.isEmpty) {
      return EmptyState(_hasFilters
          ? 'Aucune entrée pour ces filtres. Essayez d’élargir la période ou de réinitialiser.'
          : 'Aucune entrée d’audit pour le moment.');
    }
    final totalPages = (data.length / _pageSize).ceil().clamp(1, 1 << 30);
    final page = _page.clamp(1, totalPages);
    final start = (page - 1) * _pageSize;
    final rows = data.sublist(start, (start + _pageSize).clamp(0, data.length));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${data.length} ${data.length <= 1 ? 'entrée' : 'entrées'}${_hasFilters ? ' (filtrées)' : ''}',
          style: const TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 6),
        for (final row in rows)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              onTap: () => _detail(row),
              title: Row(
                children: [
                  StatusChip(_actionLabels[row.action] ?? row.action, color: _actionColor(row.action)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_tableLabels[row.tableName] ?? row.tableName} #${row.recordId ?? '—'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${_dateTime(row.createdAt)} · ${row.username}'
                  '${(row.description?.trim().isNotEmpty ?? false) ? '\n${row.description!.trim()}' : ''}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Text(
                '${start + 1}–${start + rows.length} sur ${data.length}',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
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
    Widget meta(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ),
              Expanded(child: Text(value)),
            ],
          ),
        );

    Widget jsonBlock(String title, Object? raw) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.steel,
                borderRadius: BorderRadius.circular(8),
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
