import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'api_client.dart';
import 'format.dart';
import 'settings.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// Feedback

void showToast(BuildContext context, String message, {bool error = false}) {
  final p = context.palette;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: error ? p.danger : (p.isDark ? p.surfaceAlt : AppColors.navy),
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: error ? Colors.white : p.accent,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: error || !p.isDark ? Colors.white : p.textPrimary),
              ),
            ),
          ],
        ),
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
  final p = context.palette;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        danger ? Icons.warning_amber_rounded : Icons.help_outline_rounded,
        color: danger ? p.danger : p.accent,
        size: 32,
      ),
      content: Text(message, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Annuler', style: TextStyle(color: p.textMuted)),
        ),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: p.danger, foregroundColor: Colors.white) : null,
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
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 18),
            builder(ctx),
          ],
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Page structure

/// Tab / page layout: collapsing large title, optional pinned filter bar,
/// pull-to-refresh and a padded content column.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.onRefresh,
    this.filterBar,
    this.filterBarHeight = 60,
    this.floatingActionButton,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final Future<void> Function()? onRefresh;

  /// Stays visible under the collapsed title while scrolling.
  final Widget? filterBar;
  final double filterBarHeight;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scroll = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverAppBar.large(
          pinned: true,
          backgroundColor: p.background,
          surfaceTintColor: Colors.transparent,
          title: Text(title),
          actions: [...actions, const SizedBox(width: 4)],
          bottom: filterBar == null
              ? null
              : PreferredSize(
                  preferredSize: Size.fromHeight(filterBarHeight),
                  child: Container(
                    height: filterBarHeight,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    alignment: Alignment.center,
                    child: filterBar,
                  ),
                ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, floatingActionButton != null ? 96 : 24),
          sliver: SliverList.list(children: children),
        ),
      ],
    );
    return Scaffold(
      floatingActionButton: floatingActionButton,
      body: onRefresh == null
          ? scroll
          : RefreshIndicator(onRefresh: onRefresh!, edgeOffset: 120, child: scroll),
    );
  }
}

/// Busy-aware overflow menu used in page app bars.
class ActionMenu<T> extends StatelessWidget {
  const ActionMenu({
    super.key,
    required this.items,
    required this.onSelected,
    this.busy = false,
    this.enabled = true,
  });

  final List<PopupMenuEntry<T>> items;
  final ValueChanged<T> onSelected;
  final bool busy;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return PopupMenuButton<T>(
      enabled: enabled,
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: onSelected,
      itemBuilder: (_) => items,
    );
  }
}

PopupMenuItem<T> menuItem<T>(T value, IconData icon, String label,
    {bool enabled = true, bool danger = false}) {
  return PopupMenuItem<T>(
    value: value,
    enabled: enabled,
    child: Builder(builder: (context) {
      final p = context.palette;
      final color = danger ? p.danger : p.textPrimary;
      return Row(
        children: [
          Icon(icon, size: 20, color: danger ? p.danger : p.textMuted),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: color)),
        ],
      );
    }),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: context.palette.textMuted,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Surfaces

BoxDecoration cardDecoration(AppPalette p, {Color? color, double radius = 16}) => BoxDecoration(
      color: color ?? p.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: p.border.withValues(alpha: p.isDark ? 1 : 0.7)),
      boxShadow: p.isDark
          ? null
          : [BoxShadow(color: p.shadow, blurRadius: 18, offset: const Offset(0, 6))],
    );

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final String? title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: padding,
      decoration: cardDecoration(p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  IconBubble(icon!, color: p.accent, size: 32),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title!,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                          letterSpacing: -0.2,
                          color: p.textPrimary,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitle!, style: TextStyle(fontSize: 12.5, color: p.textMuted)),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

class IconBubble extends StatelessWidget {
  const IconBubble(this.icon, {super.key, required this.color, this.size = 36});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.palette.tint(color),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: size * 0.55),
    );
  }
}

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.icon,
    this.accent = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final String? sub;
  final IconData? icon;

  /// Main KPI: amber gradient card.
  final bool accent;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = accent ? Colors.white : p.textPrimary;
    final muted = accent ? Colors.white.withValues(alpha: 0.85) : p.textMuted;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: accent
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF59E0B), Color(0xFFD97706), Color(0xFFB45309)],
              ),
              boxShadow: p.isDark
                  ? null
                  : [BoxShadow(color: AppColors.amber.withValues(alpha: 0.30), blurRadius: 18, offset: const Offset(0, 8))],
            )
          : cardDecoration(p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                accent
                    ? Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(icon, size: 16, color: Colors.white),
                      )
                    : IconBubble(icon!, color: p.isDark ? p.primary : p.info, size: 28),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: valueColor ?? fg,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 3),
            Text(sub!, style: TextStyle(fontSize: 11.5, color: muted)),
          ],
        ],
      ),
    );
  }
}

/// Responsive grid of KPI cards (2 columns on phones, 4 on tablets).
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: LayoutBuilder(
        builder: (context, c) {
          final perRow = c.maxWidth > 700 ? 4 : 2;
          final w = (c.maxWidth - (perRow - 1) * 10) / perRow;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [for (final k in children) SizedBox(width: w, child: k)],
          );
        },
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, required this.color, this.dot = true});

  final String label;
  final Color color;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: context.palette.tint(color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

enum BannerKind { info, warning, error, success }

class InfoBanner extends StatelessWidget {
  const InfoBanner(this.message, {super.key, this.kind = BannerKind.warning});

  final String message;
  final BannerKind kind;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (color, icon) = switch (kind) {
      BannerKind.info => (p.info, Icons.info_outline_rounded),
      BannerKind.warning => (p.warning, Icons.lightbulb_outline_rounded),
      BannerKind.error => (p.danger, Icons.error_outline_rounded),
      BannerKind.success => (p.success, Icons.check_circle_outline_rounded),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.tint(color),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: p.textPrimary, fontSize: 13, height: 1.35)),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key, this.icon = Icons.inbox_outlined, this.title});

  final String message;
  final IconData icon;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: p.surfaceAlt, shape: BoxShape.circle),
            child: Icon(icon, color: p.textMuted, size: 28),
          ),
          const SizedBox(height: 12),
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(title!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: p.textMuted, fontSize: 13)),
        ],
      ),
    );
  }
}

/// Pulsing placeholder block.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 16, this.width, this.radius = 10});

  final double height;
  final double? width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: Color.lerp(p.surfaceAlt, p.border, _controller.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

class SkeletonPage extends StatelessWidget {
  const SkeletonPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: const [
            Expanded(child: Skeleton(height: 96, radius: 16)),
            SizedBox(width: 10),
            Expanded(child: Skeleton(height: 96, radius: 16)),
          ],
        ),
        const SizedBox(height: 14),
        const Skeleton(height: 200, radius: 16),
        const SizedBox(height: 14),
        for (var i = 0; i < 3; i++) ...[
          const Skeleton(height: 64, radius: 14),
          const SizedBox(height: 10),
        ],
      ],
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
    final p = context.palette;
    return value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: builder,
      loading: () => const SkeletonPage(),
      error: (e, _) => Container(
        padding: const EdgeInsets.all(20),
        decoration: cardDecoration(p),
        child: Column(
          children: [
            IconBubble(Icons.cloud_off_rounded, color: p.danger, size: 52),
            const SizedBox(height: 12),
            Text(errorMessage(e), textAlign: TextAlign.center, style: TextStyle(color: p.textPrimary)),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inputs

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
          ButtonSegment(
            value: p,
            label: Text(p.label),
            icon: Icon(p == Product.gasoil ? Icons.local_gas_station_rounded : Icons.opacity_rounded, size: 18),
          ),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class LabeledDropdown<T> extends StatelessWidget {
  const LabeledDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.icon,
  });

  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      borderRadius: BorderRadius.circular(12),
      icon: const Icon(Icons.expand_more_rounded),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
      ),
      items: [
        for (final e in items.entries)
          DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
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
      borderRadius: BorderRadius.circular(12),
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
          prefixIcon: const Icon(Icons.event_rounded, size: 20),
          suffixIcon: clearable && value.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => onChanged(''),
                )
              : null,
        ),
        child: Text(value.isEmpty ? '—' : formatDate(value)),
      ),
    );
  }
}

/// Compact year chip fed by saved app years (falls back to current year).
class YearSelector extends StatelessWidget {
  const YearSelector({super.key, required this.value, required this.onChanged, this.years});

  final int value;
  final ValueChanged<int> onChanged;
  final List<int>? years;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final now = DateTime.now().year;
    final options = {
      ...?years,
      now,
      value,
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    return PopupMenuButton<int>(
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [for (final y in options) PopupMenuItem(value: y, child: Text('$y'))],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_rounded, size: 15, color: p.textMuted),
            const SizedBox(width: 6),
            Text('$value', style: TextStyle(fontWeight: FontWeight.w600, color: p.textPrimary)),
            Icon(Icons.expand_more_rounded, size: 18, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Système / Clair / Sombre.
class ThemeModePicker extends ConsumerWidget {
  const ThemeModePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return SegmentedButton<ThemeMode>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded, size: 18), label: Text('Système')),
        ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded, size: 18), label: Text('Clair')),
        ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded, size: 18), label: Text('Sombre')),
      ],
      selected: {mode},
      onSelectionChanged: (s) {
        HapticFeedback.selectionClick();
        ref.read(themeModeProvider.notifier).set(s.first);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Lists and tables

/// Uniform row card for list screens.
class ListCard extends StatelessWidget {
  const ListCard({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.footer,
    this.onTap,
  });

  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final Widget? footer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: cardDecoration(p, radius: 14),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (leading != null) ...[leading!, const SizedBox(width: 12)],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DefaultTextStyle.merge(
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: p.textPrimary),
                            child: title,
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 3),
                            DefaultTextStyle.merge(
                              style: TextStyle(fontSize: 12.5, color: p.textMuted),
                              child: subtitle!,
                            ),
                          ],
                        ],
                      ),
                    ),
                    ?trailing,
                  ],
                ),
                if (footer != null) ...[
                  const SizedBox(height: 8),
                  Padding(padding: const EdgeInsets.only(right: 8), child: footer),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Separator naming the quinzaine of the rows that follow.
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
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: meta.isEmpty ? 34 : 34 + meta.length * 16.0,
            decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: p.textPrimary)),
                Text(window, style: TextStyle(fontSize: 12, color: p.textMuted)),
                for (final m in meta)
                  Text(m, style: TextStyle(fontSize: 12, color: p.textMuted, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Afficher plus" for client-side paging.
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
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Text('$shown sur $total', style: TextStyle(color: p.textMuted, fontSize: 12)),
          if (shown < total) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.expand_more_rounded),
              label: const Text('Afficher plus'),
            ),
          ],
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
    final p = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: headers.every((h) => h.isEmpty) ? 0 : 38,
          dataRowMinHeight: 34,
          dataRowMaxHeight: 42,
          horizontalMargin: 10,
          columnSpacing: 20,
          border: TableBorder(horizontalInside: BorderSide(color: p.border, width: 0.6)),
          columns: [
            for (var i = 0; i < headers.length; i++) DataColumn(label: Text(headers[i]), numeric: i > 0),
          ],
          rows: [
            for (var r = 0; r < rows.length; r++)
              DataRow(
                color: WidgetStatePropertyAll(
                  highlightLast && r == rows.length - 1
                      ? p.accentSoft
                      : (r.isOdd ? p.surfaceAlt.withValues(alpha: 0.6) : Colors.transparent),
                ),
                cells: [
                  for (var c = 0; c < headers.length; c++)
                    DataCell(
                      Text(
                        c < rows[r].length ? rows[r][c] : '',
                        style: TextStyle(
                          fontSize: 13,
                          color: highlightLast && r == rows.length - 1 && c > 0 ? p.accent : p.textPrimary,
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
    final p = context.palette;
    final weight = strong ? FontWeight.w700 : FontWeight.w400;
    return Container(
      padding: EdgeInsets.symmetric(vertical: 9, horizontal: highlight ? 10 : 0),
      margin: highlight ? const EdgeInsets.only(top: 6) : null,
      decoration: highlight
          ? BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(10))
          : BoxDecoration(border: Border(bottom: BorderSide(color: p.border, width: 0.6))),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontWeight: strong ? FontWeight.w600 : FontWeight.w400, color: strong ? p.textPrimary : p.textMuted)),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: weight,
              color: valueColor ?? p.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (unit != null)
            SizedBox(
              width: 76,
              child: Text('  $unit', style: TextStyle(fontSize: 11, color: p.textMuted)),
            ),
        ],
      ),
    );
  }
}

/// Up/down badge for a signed variation (down is good for a purchase price).
class VariationBadge extends StatelessWidget {
  const VariationBadge(this.value, {super.key, this.suffix = ''});

  final double value;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final down = value <= 0;
    final color = down ? p.success : p.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: p.tint(color), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(down ? Icons.trending_down_rounded : Icons.trending_up_rounded, size: 16, color: color),
          const SizedBox(width: 5),
          Text(
            '${formatSigned(value)}$suffix',
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
