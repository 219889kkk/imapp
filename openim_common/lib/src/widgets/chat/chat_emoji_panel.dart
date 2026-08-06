import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

import 'chat_emoji_data.dart';

class ChatEmojiPanel extends StatefulWidget {
  const ChatEmojiPanel({
    super.key,
    required this.controller,
  });

  final TextEditingController controller;

  @override
  State<ChatEmojiPanel> createState() => _ChatEmojiPanelState();
}

class _ChatEmojiPanelState extends State<ChatEmojiPanel>
    with AutomaticKeepAliveClientMixin {
  int _categoryIndex = 0;
  final _precachedCategoryIndexes = <int>{};

  ChatEmojiCategory get _category => chatEmojiCategories[_categoryIndex];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _schedulePrecacheAround(_categoryIndex);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      height: 250.h,
      color: Styles.c_F0F2F6,
      child: Column(
        children: [
          _buildCategoryBar(),
          Container(height: 1, color: Styles.c_E8EAEF),
          Expanded(child: _buildEmojiGrid()),
          _buildActionBar(),
        ],
      ),
    );
  }

  Widget _buildCategoryBar() => SizedBox(
        height: 48.h,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          itemCount: chatEmojiCategories.length,
          separatorBuilder: (_, __) => 10.horizontalSpace,
          itemBuilder: (_, index) {
            final category = chatEmojiCategories[index];
            final selected = index == _categoryIndex;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (index == _categoryIndex) return;
                setState(() => _categoryIndex = index);
                _schedulePrecacheAround(index);
              },
              child: SizedBox(
                width: 40.w,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      category.icon,
                      size: 26.r,
                      color: selected ? Styles.c_0089FF : Styles.c_8E9AB0,
                    ),
                    6.verticalSpace,
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: 3.h,
                      width: selected ? 24.w : 0,
                      decoration: BoxDecoration(
                        color: Styles.c_0089FF,
                        borderRadius: BorderRadius.circular(2.r),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

  Widget _buildEmojiGrid() => GridView.builder(
        key: PageStorageKey('chat_emoji_${_category.label}'),
        cacheExtent: 160.h,
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
        itemCount: _category.items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          childAspectRatio: 1,
          crossAxisSpacing: 8.w,
          mainAxisSpacing: 8.h,
        ),
        itemBuilder: (_, index) {
          final item = _category.items[index];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _insertEmoji(item.emoji),
            child: RepaintBoundary(
              child: Padding(
                padding: EdgeInsets.all(2.r),
                child: Image.asset(
                  item.asset,
                  package: 'openim_common',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                  cacheWidth: 64,
                  errorBuilder: (_, __, ___) => Center(
                    child: Text(
                      item.emoji,
                      style: TextStyle(
                        fontSize: 24.sp,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );

  void _schedulePrecacheAround(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _precacheCategory(index);
      _precacheCategory((index + 1) % chatEmojiCategories.length);
    });
  }

  void _precacheCategory(int index) {
    if (!_precachedCategoryIndexes.add(index)) return;
    // Precache a small first screen only — full category decode jammed the UI.
    final items = chatEmojiCategories[index].items;
    final limit = items.length < 24 ? items.length : 24;
    for (var i = 0; i < limit; i++) {
      precacheImage(
        ResizeImage(
          AssetImage(items[i].asset, package: 'openim_common'),
          width: 64,
        ),
        context,
      );
    }
  }

  Widget _buildActionBar() => SizedBox(
        height: 50.h,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Row(
            children: [
              Container(
                width: 40.r,
                height: 40.r,
                decoration: BoxDecoration(
                  color: Styles.c_0089FF,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.search,
                  color: Colors.white,
                  size: 24.r,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _backspace,
                icon: Icon(
                  Icons.backspace,
                  color: Styles.c_0C1C33,
                  size: 28.r,
                ),
              ),
            ],
          ),
        ),
      );

  void _insertEmoji(String emoji) {
    final controller = widget.controller;
    final text = controller.text;
    final selection = controller.selection;
    final start = _clampOffset(selection.start, text);
    final end = _clampOffset(selection.end, text);
    final newText = text.replaceRange(start, end, emoji);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  void _backspace() {
    final controller = widget.controller;
    final text = controller.text;
    if (text.isEmpty) return;
    final selection = controller.selection;
    final start = _clampOffset(selection.start, text);
    final end = _clampOffset(selection.end, text);

    if (start != end) {
      controller.value = TextEditingValue(
        text: text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      );
      return;
    }
    if (start == 0) return;

    final deleteStart = _previousCharacterStart(text, start);
    controller.value = TextEditingValue(
      text: text.replaceRange(deleteStart, start, ''),
      selection: TextSelection.collapsed(offset: deleteStart),
    );
  }

  int _clampOffset(int offset, String text) {
    if (offset < 0) return text.length;
    if (offset > text.length) return text.length;
    return offset;
  }

  int _previousCharacterStart(String text, int offset) {
    var start = offset - 1;
    if (start > 0 && text.codeUnitAt(start) == 0xfe0f) {
      start--;
    }
    if (start > 0 &&
        _isLowSurrogate(text.codeUnitAt(start)) &&
        _isHighSurrogate(text.codeUnitAt(start - 1))) {
      start--;
    }
    return start;
  }

  bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xd800 && codeUnit <= 0xdbff;

  bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xdc00 && codeUnit <= 0xdfff;
}
