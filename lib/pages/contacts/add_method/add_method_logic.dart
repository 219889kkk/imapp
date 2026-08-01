import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/add_by_search/add_by_search_logic.dart';
import 'package:openim/routes/app_navigator.dart';

class AddContactsMethodLogic extends GetxController {
  void scan() => AppNavigator.startScan();

  void addFriend() =>
      AppNavigator.startAddContactsBySearch(searchType: SearchType.user);

  void createGroup() => AppNavigator.startCreateGroup(
      defaultCheckedList: [OpenIM.iMManager.userInfo]);

  void addGroup() =>
      AppNavigator.startAddContactsBySearch(searchType: SearchType.group);
}
