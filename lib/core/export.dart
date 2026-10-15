import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'theme.dart';
import 'widgets.dart';

Future<File> _saveExport(Uint8List bytes, String filename) async {
  final dir = Directory(
    '${(await getApplicationDocumentsDirectory()).path}/exports',
  );
  await dir.create(recursive: true);
  final safe = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final file = File('${dir.path}/$safe');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

/// Saves the file in the app documents and lets the user open or share it.
Future<void> saveAndOffer(
  BuildContext context,
  Uint8List bytes,
  String filename,
) async {
  final file = await _saveExport(bytes, filename);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.check_circle, color: AppColors.green),
          title: Text(filename),
          subtitle: const Text('Fichier enregistré'),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.open_in_new),
          title: const Text('Ouvrir'),
          onTap: () async {
            Navigator.pop(ctx);
            final res = await OpenFilex.open(file.path);
            if (res.type != ResultType.done && context.mounted) {
              showToast(
                context,
                'Aucune application pour ouvrir ce fichier (${res.message})',
                error: true,
              );
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.share),
          title: const Text('Partager / Enregistrer sous…'),
          onTap: () async {
            Navigator.pop(ctx);
            final box = context.findRenderObject() as RenderBox?;
            await SharePlus.instance.share(
              ShareParams(
                files: [XFile(file.path)],
                subject: filename,
                sharePositionOrigin: box == null
                    ? null
                    : box.localToGlobal(Offset.zero) & box.size,
              ),
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    ),
  );
}

/// PNG snapshot of a widget wrapped in a RepaintBoundary with [key].
Future<Uint8List?> captureWidget(GlobalKey key, {double pixelRatio = 2.5}) async {
  final boundary =
      key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) return null;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}

String exportStamp() {
  final n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(n.day)}/${two(n.month)}/${n.year} ${two(n.hour)}:${two(n.minute)}';
}
