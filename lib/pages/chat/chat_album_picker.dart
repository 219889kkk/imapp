import 'dart:io';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:provider/provider.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

/// Album confirm button shows「发送」instead of「确认」.
class SendAssetPickerTextDelegate extends AssetPickerTextDelegate {
  const SendAssetPickerTextDelegate();

  @override
  String get confirm => '发送';
}

/// Holds album-preview edits until the picker closes.
class AlbumEditStore {
  AlbumEditStore._();

  static final Map<String, String> editedPaths = <String, String>{};
  static List<String>? previewSendPaths;

  static void clear() {
    editedPaths.clear();
    previewSendPaths = null;
  }
}

/// Grid「发送」returns assets; tapping an image opens enlarge preview with edit.
class ChatAlbumPickerBuilder extends DefaultAssetPickerBuilderDelegate {
  ChatAlbumPickerBuilder({
    required super.provider,
    required super.initialPermission,
    super.gridCount,
    super.pickerTheme,
    super.specialItemPosition,
    super.specialItemBuilder,
    super.loadingIndicatorBuilder,
    super.selectPredicate,
    super.shouldRevertGrid,
    super.limitedPermissionOverlayPredicate,
    super.pathNameBuilder,
    super.assetsChangeCallback,
    super.assetsChangeRefreshPredicate,
    super.themeColor,
    super.textDelegate,
    super.locale,
    super.gridThumbnailSize,
    super.previewThumbnailSize,
    super.specialPickerType,
    super.keepScrollOffset,
    super.shouldAutoplayPreview,
    super.dragToSelect,
  });

  @override
  Future<void> viewAsset(
    BuildContext context,
    int? index,
    AssetEntity currentAsset,
  ) async {
    if (currentAsset.type != AssetType.image) {
      return super.viewAsset(context, index, currentAsset);
    }

    final p = context.read<DefaultAssetPickerProvider>();
    if (!p.selectedAssets.contains(currentAsset) && p.selectedMaximumAssets) {
      return;
    }

    final revert = effectiveShouldRevertGrid(context);
    final List<AssetEntity> previewList;
    if (index == null) {
      previewList = revert
          ? p.selectedAssets.reversed.toList(growable: false)
          : List<AssetEntity>.of(p.selectedAssets);
    } else {
      previewList = p.currentAssets
          .where((e) => e.type == AssetType.image)
          .toList(growable: false);
    }
    if (previewList.isEmpty) {
      return super.viewAsset(context, index, currentAsset);
    }

    final images = <AssetEntity>[];
    final paths = <String>[];
    for (final asset in previewList) {
      if (asset.type != AssetType.image) continue;
      final edited = AlbumEditStore.editedPaths[asset.id];
      if (edited != null && edited.isNotEmpty) {
        images.add(asset);
        paths.add(edited);
        continue;
      }
      final file = await asset.file;
      if (file == null) continue;
      images.add(asset);
      paths.add(file.path);
    }
    if (images.isEmpty || paths.isEmpty) {
      return super.viewAsset(context, index, currentAsset);
    }

    var initialIndex = images.indexWhere((e) => e.id == currentAsset.id);
    if (initialIndex < 0) initialIndex = 0;

    final sendPaths = await _openImagePreview(
      context,
      assets: images,
      paths: paths,
      initialIndex: initialIndex,
      selected: p.selectedAssets,
    );
    if (sendPaths == null || sendPaths.isEmpty) return;

    AlbumEditStore.previewSendPaths = sendPaths;
    Navigator.maybeOf(context)?.maybePop(const <AssetEntity>[]);
  }

  Future<List<String>?> _openImagePreview(
    BuildContext context, {
    required List<AssetEntity> assets,
    required List<String> paths,
    required int initialIndex,
    required List<AssetEntity> selected,
  }) {
    final working = List<String>.from(paths);
    final sources = working
        .map(
          (p) => MediaSource(
            thumbnail: '',
            file: File(p),
            tag: p,
          ),
        )
        .toList();

    return Navigator.of(context).push<List<String>>(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (ctx, animation, secondaryAnimation) {
          return MediaBrowser(
            sources: sources,
            initialIndex: initialIndex,
            allowEdit: true,
            allowSend: true,
            onEdit: (i) async {
              if (i < 0 || i >= working.length) return;
              final asset = assets[i];
              if (working[i].toLowerCase().endsWith('.gif')) return;
              final edited =
                  await ImageEditHelper.openFromPath(ctx, working[i]);
              if (edited == null || edited.isEmpty) return;
              working[i] = edited;
              AlbumEditStore.editedPaths[asset.id] = edited;
              sources[i].file = File(edited);
              sources[i].tag = edited;
            },
            onSend: (current) {
              final targets = selected.isNotEmpty
                  ? selected.where((e) => e.type == AssetType.image).toList()
                  : <AssetEntity>[assets[current.clamp(0, assets.length - 1)]];
              final result = <String>[];
              for (final asset in targets) {
                final idx = assets.indexWhere((e) => e.id == asset.id);
                if (idx >= 0) {
                  result.add(working[idx]);
                  continue;
                }
                final edited = AlbumEditStore.editedPaths[asset.id];
                if (edited != null) result.add(edited);
              }
              if (result.isEmpty && working.isNotEmpty) {
                result.add(working[current.clamp(0, working.length - 1)]);
              }
              Navigator.of(ctx).pop(result);
            },
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }
}

class ChatAlbumPicker {
  ChatAlbumPicker._();

  static Future<List<AssetEntity>?> pick(
    BuildContext context, {
    AssetSelectPredicate<AssetEntity>? selectPredicate,
  }) async {
    AlbumEditStore.clear();
    const textDelegate = SendAssetPickerTextDelegate();
    final permissionRequestOption = PermissionRequestOption(
      androidPermission: AndroidPermission(
        type: RequestType.common,
        mediaLocation: false,
      ),
    );
    final ps = await AssetPicker.permissionCheck(
      requestOption: permissionRequestOption,
    );
    final provider = DefaultAssetPickerProvider(
      maxAssets: defaultMaxAssetsCount,
      pageSize: defaultAssetsPerPage,
      pathThumbnailSize: defaultPathThumbnailSize,
      requestType: RequestType.common,
      sortPathDelegate: SortPathDelegate.common,
      sortPathsByModifiedDate: true,
      filterOptions: PMFilter.defaultValue(containsPathModified: true),
    );

    final picker = AssetPicker<AssetEntity, AssetPathEntity>(
      permissionRequestOption: permissionRequestOption,
      builder: ChatAlbumPickerBuilder(
        provider: provider,
        initialPermission: ps,
        selectPredicate: selectPredicate,
        textDelegate: textDelegate,
        locale: Localizations.maybeLocaleOf(context),
      ),
    );

    return Navigator.of(context).push<List<AssetEntity>>(
      AssetPickerPageRoute<List<AssetEntity>>(builder: (_) => picker),
    );
  }
}
