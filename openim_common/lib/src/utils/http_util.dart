import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart' hide FormData, MultipartFile;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:openim_common/openim_common.dart';
import 'package:talker_dio_logger/talker_dio_logger.dart';

var dio = Dio();

class HttpUtil {
  HttpUtil._();

  static void init() {
    dio
      ..interceptors.add(
        TalkerDioLogger(
          settings: const TalkerDioLoggerSettings(
            printRequestHeaders: kDebugMode,
            printRequestData: kDebugMode,
            printResponseMessage: kDebugMode,
            printResponseData: kDebugMode,
            printResponseHeaders: kDebugMode,
          ),
        ),
      )
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        return handler.next(options); //continue
      }, onResponse: (response, handler) {
        return handler.next(response); // continue
      }, onError: (DioError e, handler) {
        return handler.next(e); //continue
      }));

    dio.options.baseUrl = Config.imApiUrl;
    dio.options.connectTimeout = const Duration(seconds: 30); //30s
    dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  static String get operationID =>
      DateTime.now().millisecondsSinceEpoch.toString();

  static String _resolveErrorMessage(ApiResp resp) {
    final key = '${resp.errCode}';
    final localized = key.tr;
    if (localized != key) return localized;
    if (resp.errMsg.isNotEmpty) return resp.errMsg;
    return resp.errDlt;
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
    try {
      data ??= {};
      options ??= Options();
      options.headers ??= {};
      options.headers!['operationID'] = operationID;

      var result = await dio.post<Map<String, dynamic>>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      );
      var resp = ApiResp.fromJson(result.data!);
      if (resp.errCode == 0) {
        return resp.data;
      } else {
        Logger.print(
            'API error: errCode=${resp.errCode}, errMsg=${resp.errMsg}, errDlt=${resp.errDlt}');
        if (showErrorToast) {
          IMViews.showToast(_resolveErrorMessage(resp));
        }

        return Future.error((resp.errCode, resp.errMsg));
      }
    } catch (error) {
      if (error is DioException) {
        final errorMsg = '接口：$path  信息：${error.message}';
        if (showErrorToast) IMViews.showToast(errorMsg);
        return Future.error(errorMsg);
      }
      final errorMsg = '接口：$path  信息：${error.toString()}';
      if (showErrorToast) IMViews.showToast(errorMsg);
      return Future.error(error);
    }
  }

  static Future get(
    String path, {
    bool showErrorToast = true,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    try {
      options ??= Options();
      options.headers ??= {};
      options.headers!['operationID'] = operationID;

      var result = await dio.get<Map<String, dynamic>>(
        path,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      );
      var resp = ApiResp.fromJson(result.data!);
      if (resp.errCode == 0) {
        return resp.data;
      } else {
        Logger.print(
            'API error: errCode=${resp.errCode}, errMsg=${resp.errMsg}, errDlt=${resp.errDlt}');
        if (showErrorToast) {
          IMViews.showToast(_resolveErrorMessage(resp));
        }

        return Future.error((resp.errCode, resp.errMsg));
      }
    } catch (error) {
      if (error is DioException) {
        final errorMsg = '接口：$path  信息：${error.message}';
        if (showErrorToast) IMViews.showToast(errorMsg);
        return Future.error(errorMsg);
      }
      final errorMsg = '接口：$path  信息：${error.toString()}';
      if (showErrorToast) IMViews.showToast(errorMsg);
      return Future.error(error);
    }
  }

  static Future delete(
    String path, {
    dynamic data,
    bool showErrorToast = true,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      options ??= Options();
      options.headers ??= {};
      options.headers!['operationID'] = operationID;

      var result = await dio.delete<Map<String, dynamic>>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
      var resp = ApiResp.fromJson(result.data!);
      if (resp.errCode == 0) {
        return resp.data;
      } else {
        Logger.print(
            'API error: errCode=${resp.errCode}, errMsg=${resp.errMsg}, errDlt=${resp.errDlt}');
        if (showErrorToast) {
          IMViews.showToast(_resolveErrorMessage(resp));
        }

        return Future.error((resp.errCode, resp.errMsg));
      }
    } catch (error) {
      if (error is DioException) {
        final errorMsg = '接口：$path  信息：${error.message}';
        if (showErrorToast) IMViews.showToast(errorMsg);
        return Future.error(errorMsg);
      }
      final errorMsg = '接口：$path  信息：${error.toString()}';
      if (showErrorToast) IMViews.showToast(errorMsg);
      return Future.error(error);
    }
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
    try {
      data ??= {};
      options ??= Options();
      options.headers ??= {};
      options.headers!['operationID'] = operationID;

      var result = await dio.put<Map<String, dynamic>>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      );
      var resp = ApiResp.fromJson(result.data!);
      if (resp.errCode == 0) {
        return resp.data;
      } else {
        Logger.print(
            'API error: errCode=${resp.errCode}, errMsg=${resp.errMsg}, errDlt=${resp.errDlt}');
        if (showErrorToast) {
          IMViews.showToast(_resolveErrorMessage(resp));
        }

        return Future.error((resp.errCode, resp.errMsg));
      }
    } catch (error) {
      if (error is DioException) {
        final errorMsg = '接口：$path  信息：${error.message}';
        if (showErrorToast) IMViews.showToast(errorMsg);
        return Future.error(errorMsg);
      }
      final errorMsg = '接口：$path  信息：${error.toString()}';
      if (showErrorToast) IMViews.showToast(errorMsg);
      return Future.error(error);
    }
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
      var resp = await dio.post<Map<String, dynamic>>(
        '/third/minio_upload',
        data: formData,
        options: Options(headers: {
          'token': token,
          'operationID': currentOperationID,
          'X-Request-Api': Config.imApiUrl,
        }),
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
