import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

import '../photo_browser.dart';
import '../views.dart';
import '../../res/strings.dart';
import '../../utils/logger.dart';
import '../../utils/utils.dart';

/// Opens paint / crop / doodle editor for a chat picture, returns saved file path.
class ImageEditHelper {
  ImageEditHelper._();

  static const int _maxEditEdge = 1280;

  static Future<String?> openFromMediaSource(
    BuildContext context,
    MediaSource source,
  ) async {
    try {
      EasyLoading.show(dismissOnTap: true);
      final prepared = await _resolveAndDownscale(source);
      EasyLoading.dismiss();
      if (prepared == null) {
        IMViews.showToast(StrRes.saveFailed);
        return null;
      }
      if (!context.mounted) return null;

      final edited = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _ChatImageEditorPage(file: prepared),
        ),
      );
      if (edited == null || edited.isEmpty) return null;

      final dir = await getTemporaryDirectory();
      final out = File(
        '${dir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await out.writeAsBytes(edited, flush: true);
      return out.path;
    } catch (e, s) {
      EasyLoading.dismiss();
      Logger.print('ImageEditHelper.open failed: $e $s');
      IMViews.showToast('$e');
      return null;
    }
  }

  static Future<File?> _resolveAndDownscale(MediaSource source) async {
    File? file = source.file;
    if (file != null) {
      try {
        if (!await file.exists()) file = null;
      } catch (_) {
        file = null;
      }
    }

    if (file == null && IMUtils.isNotNullEmptyStr(source.url)) {
      try {
        file = await DefaultCacheManager().getSingleFile(source.url!);
      } catch (e, s) {
        Logger.print('download picture for edit failed: $e $s');
      }
    }

    if (file == null && source.thumbnail.isNotEmpty) {
      try {
        if (source.thumbnail.startsWith('http')) {
          file = await DefaultCacheManager().getSingleFile(source.thumbnail);
        }
      } catch (e, s) {
        Logger.print('download thumbnail for edit failed: $e $s');
      }
    }

    if (file == null) return null;

    try {
      final tmp = await getTemporaryDirectory();
      final outPath =
          '${tmp.path}/edit_src_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        outPath,
        quality: 90,
        minWidth: _maxEditEdge,
        minHeight: _maxEditEdge,
        format: CompressFormat.jpeg,
      );
      if (result != null) return File(result.path);
    } catch (e, s) {
      Logger.print('downscale for edit failed: $e $s');
    }
    return file;
  }
}

class _ChatImageEditorPage extends StatelessWidget {
  const _ChatImageEditorPage({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    return ProImageEditor.file(
      file,
      callbacks: ProImageEditorCallbacks(
        onImageEditingComplete: (Uint8List bytes) async {
          if (context.mounted) Navigator.of(context).pop(bytes);
        },
        onCloseEditor: (_) {
          if (context.mounted) Navigator.of(context).pop();
        },
      ),
      configs: const ProImageEditorConfigs(
        designMode: ImageEditorDesignMode.material,
        mainEditor: MainEditorConfigs(
          tools: [
            SubEditorMode.paint,
            SubEditorMode.text,
            SubEditorMode.cropRotate,
          ],
        ),
      ),
    );
  }
}
