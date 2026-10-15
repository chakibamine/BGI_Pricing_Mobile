import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
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
          leading: IconBubble(Icons.check_rounded, color: ctx.palette.success, size: 40),
          title: Text(filename, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Fichier enregistré'),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.open_in_new_rounded),
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
          leading: const Icon(Icons.ios_share_rounded),
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

String exportStamp() {
  final n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(n.day)}/${two(n.month)}/${n.year} ${two(n.hour)}:${two(n.minute)}';
}
