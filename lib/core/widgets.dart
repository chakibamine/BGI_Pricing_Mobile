import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'api_client.dart';
import 'format.dart';
import 'theme.dart';

void showToast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.red : AppColors.navy,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

/// Runs [action], shows [success] or the API error message.
Future<T?> runAction<T>(
  BuildContext context,
  Future<T> Function() action, {
  String? success,
}) async {
  try {
    final result = await action();
    if (context.mounted && success != null) showToast(context, success);
    return result;
  } catch (e) {
    if (context.mounted) showToast(context, errorMessage(e), error: true);
    return null;
  }
}

Future<bool> confirmDialog(
  BuildContext context,
  String message, {
  String confirmLabel = 'Confirmer',
  bool danger = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: AppColors.red)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Bottom sheet with a title, scrollable content and keyboard padding.
Future<T?> showFormSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext ctx) builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 16),
            builder(ctx),
          ],
        ),
      ),
    ),
  );
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 10),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.accent = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final String? sub;
  final bool accent;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent ? const Color(0xFFFFFBEB) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent ? AppColors.amber : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: valueColor ?? (accent ? AppColors.amber : AppColors.ink),
              ),
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(
              sub!,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Two-column grid of KPI cards.
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth > 700 ? 4 : 2;
        final w = (c.maxWidth - (perRow - 1) * 8) / perRow;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final k in children) SizedBox(width: w, child: k)],
        );
      },
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.muted),
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner(this.message, {super.key, this.color = AppColors.amber});

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(message, style: TextStyle(color: color, fontSize: 13)),
    );
  }
}

/// Loading / error / data for an AsyncValue, with retry on error.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: builder,
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              errorMessage(e),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.red),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Réessayer'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ProductSelector extends StatelessWidget {
  const ProductSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final Product value;
  final ValueChanged<Product> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<Product>(
      showSelectedIcon: false,
      segments: [
        for (final p in Product.values)
          ButtonSegment(value: p, label: Text(p.label)),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

/// Dropdown in a labelled box (compact filters).
class LabeledDropdown<T> extends StatelessWidget {
  const LabeledDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final e in items.entries)
          DropdownMenuItem(value: e.key, child: Text(e.value)),
      ],
      onChanged: (v) {
        if (v != null || null is T) onChanged(v as T);
      },
    );
  }
}

/// Read-only field opening a date picker; value is an ISO date (yyyy-mm-dd) or ''.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.clearable = true,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool clearable;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final initial = value.isEmpty ? DateTime.now() : DateTime.parse(value);
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          locale: const Locale('fr'),
        );
        if (picked != null) onChanged(isoDate(picked));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: clearable && value.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => onChanged(''),
                )
              : const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(value.isEmpty ? '—' : formatDate(value)),
      ),
    );
  }
}

/// Separator row naming the quinzaine of the rows that follow.
class QuinzaineHeaderTile extends StatelessWidget {
  const QuinzaineHeaderTile({
    super.key,
    required this.label,
    required this.window,
    this.meta = const [],
  });

  final String label;
  final String window;
  final List<String> meta;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.steel,
        borderRadius: BorderRadius.circular(8),
        border: const Border(left: BorderSide(color: AppColors.amber, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label  ·  $window',
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy),
          ),
          for (final m in meta)
            Text(m, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
      ),
    );
  }
}

/// "Afficher plus" button for client-side paging.
class LoadMoreButton extends StatelessWidget {
  const LoadMoreButton({
    super.key,
    required this.shown,
    required this.total,
    required this.onPressed,
  });

  final int shown;
  final int total;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Text('$shown sur $total', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          if (shown < total)
            TextButton(onPressed: onPressed, child: const Text('Afficher plus')),
        ],
      ),
    );
  }
}

/// Compact table, horizontally scrollable; columns after the first are right-aligned.
class SimpleTable extends StatelessWidget {
  const SimpleTable({
    super.key,
    required this.headers,
    required this.rows,
    this.highlightLast = false,
  });

  final List<String> headers;
  final List<List<String>> rows;
  final bool highlightLast;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: headers.every((h) => h.isEmpty) ? 0 : 36,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 40,
        horizontalMargin: 8,
        columnSpacing: 18,
        headingTextStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: AppColors.navy,
        ),
        columns: [
          for (var i = 0; i < headers.length; i++)
            DataColumn(label: Text(headers[i]), numeric: i > 0),
        ],
        rows: [
          for (var r = 0; r < rows.length; r++)
            DataRow(
              color: highlightLast && r == rows.length - 1
                  ? const WidgetStatePropertyAll(AppColors.amberSoft)
                  : null,
              cells: [
                for (var c = 0; c < headers.length; c++)
                  DataCell(
                    Text(
                      c < rows[r].length ? rows[r][c] : '',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: c == 0 || (highlightLast && r == rows.length - 1)
                            ? FontWeight.w600
                            : FontWeight.w400,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class KeyValueRow extends StatelessWidget {
  const KeyValueRow(
    this.label,
    this.value, {
    super.key,
    this.unit,
    this.strong = false,
    this.valueColor,
    this.highlight = false,
  });

  final String label;
  final String value;
  final String? unit;
  final bool strong;
  final Color? valueColor;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final weight = strong ? FontWeight.w700 : FontWeight.w400;
    return Container(
      color: highlight ? AppColors.amberSoft : null,
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
      decoration: highlight
          ? null
          : const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontWeight: weight)),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: weight,
              color: valueColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (unit != null)
            SizedBox(
              width: 76,
              child: Text(
                '  $unit',
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}
