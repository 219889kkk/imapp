import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

import 'scan_logic.dart';

class ScanPage extends StatelessWidget {
  final logic = Get.find<ScanLogic>();
  final qrKey = GlobalKey(debugLabel: 'openim_qr_scan');

  ScanPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scanSize = 260.w;
    return Scaffold(
      appBar: TitleBar.back(title: StrRes.scan),
      backgroundColor: Colors.black,
      body: Stack(
        alignment: Alignment.center,
        children: [
          QRView(
            key: qrKey,
            onQRViewCreated: logic.onQRViewCreated,
            overlay: QrScannerOverlayShape(
              borderColor: Styles.c_0089FF,
              borderRadius: 8.r,
              borderLength: 28.w,
              borderWidth: 6.w,
              cutOutSize: scanSize,
            ),
          ),
          Positioned(
            top: 120.h,
            child: StrRes.scanHint.toText
              ..style = Styles.ts_FFFFFF_17sp
              ..textAlign = TextAlign.center,
          ),
        ],
      ),
    );
  }
}
