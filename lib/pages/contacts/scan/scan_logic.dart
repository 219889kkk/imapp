import 'package:get/get.dart';
import 'package:openim/pages/contacts/group_profile_panel/group_profile_panel_logic.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

class ScanLogic extends GetxController {
  QRViewController? controller;
  bool _handled = false;

  @override
  void onClose() {
    controller = null;
    super.onClose();
  }

  void onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((barcode) {
      final code = barcode.code;
      if (code == null || _handled) return;
      _handleQRCode(code);
    });
  }

  void _handleQRCode(String code) async {
    if (code.startsWith(Config.friendScheme)) {
      _handled = true;
      await controller?.pauseCamera();
      final userID = code.substring(Config.friendScheme.length);
      final bridge = PackageBridge.scanBridge;
      if (bridge != null) {
        bridge.scanOutUserID(userID);
      } else {
        AppNavigator.startUserProfilePane(userID: userID, offAndToNamed: true);
      }
    } else if (code.startsWith(Config.groupScheme)) {
      _handled = true;
      await controller?.pauseCamera();
      final groupID = code.substring(Config.groupScheme.length);
      final bridge = PackageBridge.scanBridge;
      if (bridge != null) {
        bridge.scanOutGroupID(groupID);
      } else {
        AppNavigator.startGroupProfilePanel(
          groupID: groupID,
          joinGroupMethod: JoinGroupMethod.qrcode,
          offAndToNamed: true,
        );
      }
    } else {
      _handled = true;
      IMViews.showToast(StrRes.scanHint);
      Future.delayed(const Duration(milliseconds: 1200), () {
        _handled = false;
      });
    }
  }
}
