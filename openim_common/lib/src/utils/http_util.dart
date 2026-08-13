import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart' hide FormData, MultipartFile, Response;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:openim_common/openim_common.dart';
import 'package:talker_dio_logger/talker_dio_logger.dart';

var dio = Dio();

class HttpUtil {
  HttpUtil._();

  static void init() {
    if (kDebugMode) {
      dio.interceptors.add(
        TalkerDioLogger(
          settings: const TalkerDioLoggerSettings(
            printRequestHeaders: true,
            printRequestData: true,
            printResponseMessage: true,
            printResponseData: true,
            printResponseHeaders: true,
          ),
        ),
      );
    }
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      return handler.next(options); //continue
    }, onResponse: (response, handler) {
      return handler.next(response); // continue
    }, onError: (DioError e, handler) {
      return handler.next(e); //continue
    }));

    dio.options.baseUrl = Config.imApiUrl;
    // Fail fast for chat APIs; long uploads override timeouts per-request.
    dio.options.connectTimeout = const Duration(seconds: 10);
    dio.options.receiveTimeout = const Duration(seconds: 15);
  }

  static void updateBaseUrl() {
    dio.options.baseUrl = Config.imApiUrl;
  }

  static String get operationID =>
      DateTime.now().millisecondsSinceEpoch.toString();

  static int _lastNetworkToastMs = 0;

  /// Successful-but-slow responses trigger a background line switch.
  static const _slowSuccessThreshold = Duration(seconds: 8);

  static String _resolveErrorMessage(ApiResp resp) {
    final key = '${resp.errCode}';
    final localized = key.tr;
    if (localized != key) return localized;
    if (resp.errMsg.isNotEmpty) return resp.errMsg;
    return resp.errDlt;
  }

  static bool _isTransportFailure(Object error) {
    if (error is! DioException) return false;
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.unknown:
        // Often DNS / socket reset wrapped as unknown.
        return error.error is SocketException ||
            (error.message?.toLowerCase().contains('socket') ?? false);
      default:
        return false;
    }
  }

  static void _toastNetworkOnce() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastNetworkToastMs < 3000) return;
    _lastNetworkToastMs = now;
    IMViews.showToast(StrRes.networkError);
  }

  static Future<bool> _failoverAndRefresh() async {
    final current = Config.serverIp;
    final switched = await ServerEndpointSelector.failoverFrom(current);
    if (!switched) return false;
    updateBaseUrl();
    final hook = PackageBridge.onEndpointSwitched;
    if (hook != null) {
      unawaited(hook().catchError((e, s) {
        Logger.print('onEndpointSwitched failed: $e $s');
      }));
    }
    return true;
  }

  static void _maybeSwitchAfterSlowSuccess(Duration elapsed) {
    if (elapsed < _slowSuccessThreshold) return;
    unawaited(() async {
      try {
        final current = Config.serverIp;
        Logger.print(
          'HttpUtil: slow success ${elapsed.inMilliseconds}ms on $current — probe backup',
        );
        final switched =
            await ServerEndpointSelector.switchIfAlternateFaster(current);
        if (!switched) return;
        updateBaseUrl();
        final hook = PackageBridge.onEndpointSwitched;
        if (hook != null) await hook();
      } catch (e, s) {
        Logger.print('HttpUtil slow-success failover failed: $e $s');
      }
    }());
  }

  static Future<dynamic> _parseApiResponse(
    Response<Map<String, dynamic>> result, {
    required bool showErrorToast,
  }) {
    final resp = ApiResp.fromJson(result.data!);
    if (resp.errCode == 0) return Future.value(resp.data);
    Logger.print(
        'API error: errCode=${resp.errCode}, errMsg=${resp.errMsg}, errDlt=${resp.errDlt}');
    // Never toast under a blocking EasyLoading — dismiss() would eat the toast.
    if (showErrorToast && !EasyLoading.isShow) {
      IMViews.showToast(_resolveErrorMessage(resp));
    }
    return Future.error((resp.errCode, resp.errMsg));
  }

  /// Run [send]; on timeout/connection error switch host and retry once.
  /// Toast only when both lines fail (or backup unreachable).
  static Future<dynamic> _withEndpointFailover(
    String path, {
    required bool showErrorToast,
    required Future<Response<Map<String, dynamic>>> Function(String url) send,
  }) async {
    Future<dynamic> attempt(String url) async {
      final sw = Stopwatch()..start();
      final result = await send(url);
      sw.stop();
      _maybeSwitchAfterSlowSuccess(sw.elapsed);
      return _parseApiResponse(result, showErrorToast: showErrorToast);
    }

    try {
      return await attempt(path);
    } catch (error) {
      // Business (errCode, errMsg) — do not failover.
      if (error is (int, String?)) rethrow;
      if (!_isTransportFailure(error)) {
        final errorMsg = '接口：$path  信息：${error is DioException ? error.message : error}';
        if (showErrorToast) _toastNetworkOnce();
        return Future.error(errorMsg);
      }

      Logger.print(
        'HttpUtil transport fail on ${Config.serverIp} path=$path — failover: $error',
      );
      final switched = await _failoverAndRefresh();
      if (!switched) {
        if (showErrorToast) _toastNetworkOnce();
        return Future.error(
          '接口：$path  信息：${error is DioException ? error.message : error}',
        );
      }

      final retryUrl = ServerEndpointSelector.remapUrlToSelectedHost(path);
      try {
        Logger.print('HttpUtil retry on ${Config.serverIp} url=$retryUrl');
        return await attempt(retryUrl);
      } catch (retryError) {
        if (retryError is (int, String?)) rethrow;
        if (showErrorToast) _toastNetworkOnce();
        return Future.error(
          '接口：$retryUrl  信息：${retryError is DioException ? retryError.message : retryError}',
        );
      }
    }
  }

  static Future post(
    String path, {
    dynamic data,
    bool showErrorToast = true,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    data ??= {};
    options ??= Options();
    options.headers ??= {};
    options.headers!['operationID'] = operationID;
    final frozenOptions = options;
    final frozenData = data;

    return _withEndpointFailover(
      path,
      showErrorToast: showErrorToast,
      send: (url) => dio.post<Map<String, dynamic>>(
        url,
        data: frozenData,
        queryParameters: queryParameters,
        options: frozenOptions,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      ),
    );
  }

  static Future get(
    String path, {
    bool showErrorToast = true,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    options ??= Options();
    options.headers ??= {};
    options.headers!['operationID'] = operationID;
    final frozenOptions = options;

    return _withEndpointFailover(
      path,
      showErrorToast: showErrorToast,
      send: (url) => dio.get<Map<String, dynamic>>(
        url,
        queryParameters: queryParameters,
        options: frozenOptions,
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      ),
    );
  }

  static Future delete(
    String path, {
    dynamic data,
    bool showErrorToast = true,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    options ??= Options();
    options.headers ??= {};
    options.headers!['operationID'] = operationID;
    final frozenOptions = options;

    return _withEndpointFailover(
      path,
      showErrorToast: showErrorToast,
      send: (url) => dio.delete<Map<String, dynamic>>(
        url,
        data: data,
        queryParameters: queryParameters,
        options: frozenOptions,
        cancelToken: cancelToken,
      ),
    );
  }

  static Future put(
    String path, {
    dynamic data,
    bool showErrorToast = true,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    data ??= {};
    options ??= Options();
    options.headers ??= {};
    options.headers!['operationID'] = operationID;
    final frozenOptions = options;
    final frozenData = data;

    return _withEndpointFailover(
      path,
      showErrorToast: showErrorToast,
      send: (url) => dio.put<Map<String, dynamic>>(
        url,
        data: frozenData,
        queryParameters: queryParameters,
        options: frozenOptions,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      ),
    );
  }

  static Future<String> uploadImageForMinio({
    required String path,
    bool compress = true,
  }) async {
    String fileName = path.substring(path.lastIndexOf("/") + 1);

    String? compressPath;
    if (compress) {
      File? compressFile = await IMUtils.compressImageAndGetFile(File(path));
      compressPath = compressFile?.path;
      Logger.print('compressPath: $compressPath');
    }
    return uploadFileForMinio(
      path: compressPath ?? path,
      fileName: fileName,
    );
  }

  static String normalizeObjectUrl(String url) {
    final apiUri = Uri.tryParse(Config.imApiUrl);
    final objectUri = Uri.tryParse(url);
    if (apiUri == null || objectUri == null || !objectUri.hasAuthority) {
      return url;
    }
    if (!objectUri.path.startsWith('/object/')) {
      return url;
    }

    final apiPort = apiUri.hasPort ? apiUri.port : null;
    if (objectUri.scheme != apiUri.scheme ||
        objectUri.host != apiUri.host ||
        objectUri.hasPort != apiUri.hasPort ||
        (apiUri.hasPort && objectUri.port != apiUri.port)) {
      return objectUri
          .replace(
            scheme: apiUri.scheme,
            host: apiUri.host,
            port: apiPort,
          )
          .toString();
    }
    return url;
  }

  static Future<String> uploadFileForMinio({
    required String path,
    String? fileName,
    int fileType = 1,
  }) async {
    final token = DataSp.imToken;
    if (token == null || token.isEmpty) {
      return Future.error('minio_upload failed: im token is empty');
    }

    final file = File(path);
    if (!await file.exists() || await file.length() == 0) {
      return Future.error('upload file does not exist or is empty: $path');
    }

    final resolvedFileName =
        fileName ?? path.substring(path.lastIndexOf("/") + 1);
    final mf = await MultipartFile.fromFile(path, filename: resolvedFileName);
    final currentOperationID = operationID;

    var formData = FormData.fromMap(
        {'operationID': currentOperationID, 'fileType': fileType, 'file': mf});

    try {
      final longTimeout = fileType == 2 || fileType == 4;
      var resp = await dio.post<Map<String, dynamic>>(
        '/third/minio_upload',
        data: formData,
        options: Options(
          headers: {
            'token': token,
            'operationID': currentOperationID,
            'X-Request-Api': Config.imApiUrl,
          },
          sendTimeout:
              longTimeout ? const Duration(minutes: 5) : dio.options.sendTimeout,
          receiveTimeout: longTimeout
              ? const Duration(minutes: 5)
              : dio.options.receiveTimeout,
        ),
      );
      final body = resp.data;
      final errCode = body?['errCode'];
      if (errCode is int && errCode != 0) {
        final errorMsg =
            'minio_upload failed: errCode=$errCode, response=$body';
        Logger.print(errorMsg);
        return Future.error(errorMsg);
      }
      final data = body?['data'];
      final url = data is Map ? data['URL'] : null;
      if (url is String && url.isNotEmpty) {
        return normalizeObjectUrl(url);
      }
      return Future.error('minio_upload response missing URL: $body');
    } on DioException catch (e) {
      final errorMsg = 'minio_upload failed: status=${e.response?.statusCode}, '
          'message=${e.message}, response=${e.response?.data}';
      Logger.print(errorMsg);
      return Future.error(errorMsg);
    } catch (e, s) {
      final errorMsg = 'minio_upload failed: $e';
      Logger.print('$errorMsg $s');
      return Future.error(errorMsg);
    }
  }

  static Future download(
    String url, {
    required String cachePath,
    CancelToken? cancelToken,
    Function(int count, int total)? onProgress,
  }) {
    return dio.download(
      url,
      cachePath,
      options: Options(
        receiveTimeout: const Duration(minutes: 10),
      ),
      cancelToken: cancelToken,
      onReceiveProgress: onProgress,
    );
  }

  static Future saveUrlPicture(
    String url, {
    CancelToken? cancelToken,
    Function(int count, int total)? onProgress,
    VoidCallback? onCompletion,
  }) async {
    final name = url.substring(url.lastIndexOf('/') + 1);
    final cachePath = await IMUtils.createTempFile(dir: 'picture', name: name);
    var intervalDo = IntervalDo();

    return download(
      url,
      cachePath: cachePath,
      cancelToken: cancelToken,
      onProgress: (int count, int total) async {
        onProgress?.call(count, total);
        if (total == -1) {
          onCompletion?.call();
          intervalDo.drop(
              fun: () async {
                saveFileToGallerySaver(File(cachePath),
                    showTaost: EasyLoading.isShow);
              },
              milliseconds: 1500);
        }
        if (count == total) {
          saveFileToGallerySaver(File(cachePath),
              showTaost: EasyLoading.isShow);
        }
      },
    );
  }

  static Future saveImage(Image image) async {
    var byteData = await image.toByteData(format: ImageByteFormat.png);
    if (byteData != null) {
      Uint8List uint8list = byteData.buffer.asUint8List();
      var result =
          await ImageGallerySaverPlus.saveImage(Uint8List.fromList(uint8list));
      if (result != null) {
        var tips = StrRes.saveSuccessfully;
        if (Platform.isAndroid) {
          final filePath = result['filePath'].split('//').last;
          tips = '${StrRes.saveSuccessfully}:$filePath';
        }
        IMViews.showToast(tips);
      }
    }
  }

  static Future saveUrlVideo(
    String url, {
    CancelToken? cancelToken,
    Function(int count, int total)? onProgress,
    VoidCallback? onCompletion,
  }) async {
    final name = url.substring(url.lastIndexOf('/') + 1);
    final cachePath = await IMUtils.createTempFile(dir: 'video', name: name);

    if (File(cachePath).existsSync()) {
      onCompletion?.call();
      return;
    }

    return download(
      url,
      cachePath: cachePath,
      cancelToken: cancelToken,
      onProgress: (int count, int total) async {
        onProgress?.call(count, total);
        if (count == total) {
          onCompletion?.call();
          final result = await ImageGallerySaverPlus.saveFile(cachePath);
          if (result != null) {
            var tips = StrRes.saveSuccessfully;
            if (Platform.isAndroid) {
              final filePath = result['filePath'].split('//').last;
              tips = '${StrRes.saveSuccessfully}:$filePath';
            }
            IMViews.showToast(tips);
          }
        }
      },
    );
  }

  static Future saveFileToGallerySaver(File file,
      {String? name, bool showTaost = true}) async {
    Permissions.storage(() async {
      var tips = StrRes.saveSuccessfully;
      Logger.print('saveFileToGallerySaver: ${file.path}');
      final imageBytes = await file.readAsBytes();

      final result =
          await ImageGallerySaverPlus.saveImage(imageBytes, name: name);
      if (result != null && showTaost) {
        if (Platform.isAndroid) {
          final filePath = result['filePath'].split('//').last;
          tips = '${StrRes.saveSuccessfully}:$filePath';
        }
        IMViews.showToast(tips);
      }
    });
  }
}
