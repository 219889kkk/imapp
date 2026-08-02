import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

class LoadingView {
  static final LoadingView singleton = LoadingView._();

  factory LoadingView() => singleton;

  LoadingView._();

  OverlayEntry? _overlayEntry;
  OverlayEntry? _progressOverlayEntry;
  bool _isVisible = false;
  bool isProgressVisible = false;
  int _showToken = 0;

  Future<T> wrap<T>({
    required Future<T> Function() asyncFunction,
    bool showing = true,
  }) async {
    await Future.delayed(const Duration(milliseconds: 1));
    if (showing) show();
    try {
      return await asyncFunction();
    } finally {
      dismiss();
    }
  }

  void show() {
    if (_isVisible) return;
    final ctx = Get.overlayContext;
    if (ctx == null) return;
    final overlay = Overlay.maybeOf(ctx);
    if (overlay == null) return;

    final token = ++_showToken;
    _overlayEntry = OverlayEntry(
      builder: (BuildContext context) => Positioned.fill(
        child: ColoredBox(
          color: Colors.black26,
          child: Center(
            child: CircularProgressIndicator(color: Styles.c_0089FF),
          ),
        ),
      ),
    );
    _isVisible = true;
    try {
      overlay.insert(_overlayEntry!);
    } catch (e, s) {
      Logger.print('LoadingView.show insert failed: $e $s');
      _overlayEntry = null;
      _isVisible = false;
      return;
    }
    if (token != _showToken || !_isVisible) {
      dismiss();
    }
  }

  void dismiss() {
    _showToken++;
    try {
      _overlayEntry?.remove();
    } catch (_) {}
    try {
      _progressOverlayEntry?.remove();
    } catch (_) {}
    _overlayEntry = null;
    _progressOverlayEntry = null;
    _isVisible = false;
    isProgressVisible = false;
  }

  void progress(Stream<double> stream) {
    dismiss();
    final ctx = Get.overlayContext;
    if (ctx == null) return;
    final overlay = Overlay.maybeOf(ctx);
    if (overlay == null) return;

    _progressOverlayEntry = OverlayEntry(
      builder: (BuildContext context) => GestureDetector(
        onTap: dismiss,
        child: ColoredBox(
          color: const Color.fromARGB(80, 37, 33, 33),
          child: Center(
            child: Container(
              alignment: Alignment.center,
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Styles.c_0C1C33,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CupertinoActivityIndicator(
                    color: Colors.white,
                    radius: 20,
                  ),
                  StreamBuilder(
                    stream: stream,
                    builder:
                        (BuildContext context, AsyncSnapshot<double> snapshot) {
                      if (!snapshot.hasData) return const SizedBox.shrink();
                      final progress = snapshot.data ?? 0.0;
                      return Text(
                        '${(progress * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(color: Colors.white),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    isProgressVisible = true;
    try {
      overlay.insert(_progressOverlayEntry!);
    } catch (e, s) {
      Logger.print('LoadingView.progress insert failed: $e $s');
      _progressOverlayEntry = null;
      isProgressVisible = false;
    }
  }
}
