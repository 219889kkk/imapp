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

/// Opens paint / crop / doodle editor; returns saved JPEG path or null if cancelled.
class ImageEditHelper {
  ImageEditHelper._();

  static const int _maxEditEdge = 1280;

  static const I18n zhI18n = I18n(
    cancel: '取消',
    undo: '撤销',
    redo: '重做',
    done: '完成',
    remove: '删除',
    doneLoadingMsg: '正在应用更改…',
    importStateHistoryMsg: '正在打开编辑器…',
    various: I18nVarious(
      loadingDialogMsg: '请稍候…',
      closeEditorWarningTitle: '关闭图片编辑？',
      closeEditorWarningMessage: '确定关闭吗？未保存的修改将丢失。',
      closeEditorWarningConfirmBtn: '确定',
      closeEditorWarningCancelBtn: '取消',
    ),
    paintEditor: I18nPaintEditor(
      bottomNavigationBarText: '涂鸦',
      moveAndZoom: '缩放',
      freestyle: '画笔',
      arrow: '箭头',
      line: '直线',
      rectangle: '矩形',
      circle: '圆形',
      dashLine: '虚线',
      eraser: '橡皮',
      lineWidth: '线宽',
      toggleFill: '填充',
      changeOpacity: '透明度',
      undo: '撤销',
      redo: '重做',
      done: '完成',
      back: '返回',
      cancel: '取消',
      smallScreenMoreTooltip: '更多',
      opacity: '透明度',
      color: '颜色',
      strokeWidth: '描边',
      fill: '填充',
      blur: '模糊',
      pixelate: '马赛克',
    ),
    textEditor: I18nTextEditor(
      bottomNavigationBarText: '文字',
      inputHintText: '输入文字',
      back: '返回',
      done: '完成',
      textAlign: '对齐',
      fontScale: '字号',
      backgroundMode: '背景',
      smallScreenMoreTooltip: '更多',
    ),
    cropRotateEditor: I18nCropRotateEditor(
      bottomNavigationBarText: '裁剪',
      rotate: '旋转',
      flip: '翻转',
      ratio: '比例',
      back: '返回',
      done: '完成',
      cancel: '取消',
      undo: '撤销',
      redo: '重做',
      reset: '重置',
      smallScreenMoreTooltip: '更多',
    ),
  );

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
      return openFromFile(context, prepared);
    } catch (e, s) {
      EasyLoading.dismiss();
      Logger.print('ImageEditHelper.openFromMediaSource failed: $e $s');
      IMViews.showToast('$e');
      return null;
    }
  }

  /// Opens editor for a local image path (album / camera). Returns edited path.
  static Future<String?> openFromPath(
    BuildContext context,
    String path,
  ) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        IMViews.showToast(StrRes.saveFailed);
        return null;
      }
      EasyLoading.show(dismissOnTap: true);
      final prepared = await _downscaleFile(file) ?? file;
      EasyLoading.dismiss();
      if (!context.mounted) return null;
      return openFromFile(context, prepared);
    } catch (e, s) {
      EasyLoading.dismiss();
      Logger.print('ImageEditHelper.openFromPath failed: $e $s');
      IMViews.showToast('$e');
      return null;
    }
  }

  static Future<String?> openFromFile(
    BuildContext context,
    File file,
  ) async {
    try {
      final edited = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _ChatImageEditorPage(file: file),
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
      Logger.print('ImageEditHelper.openFromFile failed: $e $s');
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
    return await _downscaleFile(file) ?? file;
  }

  static Future<File?> _downscaleFile(File file) async {
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
    return null;
  }
}

class _ChatImageEditorPage extends StatefulWidget {
  const _ChatImageEditorPage({required this.file});

  final File file;

  @override
  State<_ChatImageEditorPage> createState() => _ChatImageEditorPageState();
}

class _ChatImageEditorPageState extends State<_ChatImageEditorPage> {
  bool _didPop = false;

  void _popOnce([Uint8List? bytes]) {
    if (_didPop || !mounted) return;
    _didPop = true;
    Navigator.of(context).pop(bytes);
  }

  @override
  Widget build(BuildContext context) {
    // pro_image_editor may call onImageEditingComplete then onCloseEditor.
    // Only pop once so we never close the preview/chat underneath.
    return ProImageEditor.file(
      widget.file,
      callbacks: ProImageEditorCallbacks(
        onImageEditingComplete: (Uint8List bytes) async {
          _popOnce(bytes);
        },
        onCloseEditor: (_) {
          _popOnce();
        },
      ),
      configs: const ProImageEditorConfigs(
        designMode: ImageEditorDesignMode.material,
        i18n: ImageEditHelper.zhI18n,
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
