import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:openim_common/openim_common.dart';

class CacheController extends GetxController {
  final callRecordList = <CallRecords>[].obs;
  Box? callRecordBox;
  bool _isInitCallRecords = false;

  String get userID => DataSp.getLoginCertificate()!.userID;

  initCallRecords() {
    if (!_isInitCallRecords) {
      _isInitCallRecords = true;
      var list = callRecordBox?.get(userID, defaultValue: <CallRecords>[]);
      if (list != null) {
        callRecordList.assignAll((list as List).cast());
      }
    }
  }

  void resetCache() {
    if (_isInitCallRecords) {
      callRecordList.value = [];
      final list = callRecordBox?.get(userID, defaultValue: <CallRecords>[]);

      if (list != null) {
        callRecordList.assignAll((list as List).cast());
      }
    }
  }

  addCallRecords(CallRecords records) {
    callRecordList.insert(0, records);
    callRecordBox?.put(userID, callRecordList.value);
  }

  deleteCallRecords(CallRecords records) async {
    callRecordList.removeWhere((element) => element.userID == records.userID && element.date == records.date);
    await callRecordBox?.put(userID, callRecordList.value);
  }

  @override
  void onClose() {
    _isInitCallRecords = false;
    Hive.close();
    super.onClose();
  }

  @override
  void onInit() async {
    Hive.registerAdapter(CallRecordsAdapter());

    callRecordBox = await Hive.openBox<List>('callRecords');
    super.onInit();
  }
}
