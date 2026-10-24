import 'package:PiliPlus/common/skeleton/video_reply.dart';
import 'package:PiliPlus/common/sliver_single_child_delegate.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/scaffold/mini_scaffold.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/simple_colored_box.dart';
import 'package:PiliPlus/common/widgets/sliver/sliver_pinned_header.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/slide/common_slide_page.dart';
import 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:PiliPlus/pages/video/reply_reply/controller.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/extension/widget_ext.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:fixnum/fixnum.dart' show Int64;
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class VideoReplyReplyPanel extends CommonSlidePage {
  const VideoReplyReplyPanel({
    super.key,
    super.enableSlide,
    this.id,
    required this.oid,
    required this.rpid,
    this.dialog,
    this.firstFloor,
    required this.isVideoDetail,
    required this.replyType,
    this.isNested = false,
    this.upMid,
  });
  final int? id;
  final int oid;
  final int rpid;
  final int? dialog;
  final ReplyInfo? firstFloor;
  final bool isVideoDetail;
  final int replyType;
  final bool isNested;
  final Int64? upMid;

  static Future<void>? toReply({
    required int oid,
    required int rootId,
    int? rpId,
    required int type,
    Uri? uri,
  }) {
    return Get.to(
      arguments: {
        'oid': oid,
        'rpid': rootId,
        'id': ?rpId,
        'type': type,
        'enterUri': ?uri?.toString(), // save panel
      },
      () => SimpleScaffold(
        appBar: AppBar(
          title: const Text('评论详情'),
          actions: [
            IconButton(
              tooltip: '前往',
              onPressed: uri == null
                  ? null
                  : () => PiliScheme.routePush(uri, businessId: type),
              icon: const Icon(Icons.open_in_browser),
            ),
          ],
        ),
        body: ViewSafeArea(
          child: VideoReplyReplyPanel(
            enableSlide: false,
            oid: oid,
            rpid: rootId,
            isVideoDetail: false,
            replyType: type,
            firstFloor: null,
            id: rpId,
          ),
        ).constraintWidth(),
      ),
    );
  }

  @override
  State<VideoReplyReplyPanel> createState() => _VideoReplyReplyPanelState();
}

class _VideoReplyReplyPanelState extends State<VideoReplyReplyPanel>
    with SingleTickerProviderStateMixin, CommonSlideMixin {
  late VideoReplyReplyController _controller;
  late final _tag = Utils.makeHeroTag('${widget.rpid}${widget.dialog}');

  late final bool isDialogue = widget.dialog != null;

  /// 首楼焦点节点。
  /// 注意：评论详情是 MiniScaffold 的底部弹窗，与视频页同处一个 FocusScope，
  /// 打开时原焦点（评论主楼）仍在，`autofocus` 会被 FocusManager 丢弃
  /// （autofocus 仅在 scope.focusedChild == null 时生效），因此必须显式请求焦点。
  late final FocusNode _firstFloorNode;

  /// 打开本页前的焦点，关闭时归还
  FocusNode? _previousFocus;

  /// 首楼（或其操作按钮）是否持有焦点，用于给首楼加焦点底色提示
  bool _firstFloorFocused = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = PrimaryScrollController.of(context);
    _controller
      ..didChangeDependencies(context)
      ..nestedController = controller is ExtendedNestedScrollController
          ? controller
          : null;
  }

  @override
  void initState() {
    super.initState();
    _previousFocus = FocusManager.instance.primaryFocus;
    _firstFloorNode = FocusNode(debugLabel: 'replyDetailFirstFloor');
    _controller = Get.put(
      VideoReplyReplyController(
        hasRoot: widget.firstFloor != null,
        id: widget.id,
        oid: widget.oid,
        rpid: widget.rpid,
        dialog: widget.dialog,
        replyType: widget.replyType,
      ),
      tag: _tag,
    );
    // 首楼数据可能异步到达（Obx 分支里也会再试一次，未挂载时为空操作）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _firstFloorNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    final previous = _previousFocus;
    // 焦点归还给打开详情页前的节点（评论主楼）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (previous != null && previous.canRequestFocus) {
        previous.requestFocus();
      }
    });
    _firstFloorNode.dispose();
    Get.delete<VideoReplyReplyController>(tag: _tag);
    super.dispose();
  }

  @override
  Widget buildPage(ThemeData theme) {
    Widget child() => enableSlide ? slideList(theme) : buildList(theme);
    // FocusScope 把方向键遍历限制在详情页内，不会穿透到背后的视频页/评论列表
    return FocusScope(
      child: SimpleColoredBox(
        color: theme.canvasColor,
        child: MiniScaffold(
          body: widget.isVideoDetail
              ? Column(
                  children: [
                    Container(
                      height: 45,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            width: 1,
                            color: theme.dividerColor.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.only(left: 12, right: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(isDialogue ? '对话列表' : '评论详情'),
                          IconButton(
                            tooltip: '关闭',
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: Get.back,
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: child()),
                  ],
                )
              : child(),
        ),
      ),
    );
  }

  ReplyInfo? get firstFloor =>
      widget.firstFloor ?? _controller.firstFloor.value;

  ScrollController get scrollController =>
      _controller.nestedController ?? _controller.scrollController;

  @override
  Widget buildList(ThemeData theme) {
    return refreshIndicator(
      onRefresh: _controller.onRefresh,
      isClampingScrollPhysics: widget.isNested,
      child: CustomScrollView(
        key: ValueKey(scrollController.hashCode),
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (!isDialogue) ...[
            if ((widget.firstFloor ?? _controller.firstFloor.value)
                case final firstFloor?)
              _header(theme, firstFloor)
            else
              Obx(() {
                final firstFloor = _controller.firstFloor.value;
                if (firstFloor == null) {
                  return const SliverToBoxAdapter();
                }
                // 首楼异步到达：补一次焦点请求（用户已操作过则不抢焦点）
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted &&
                      FocusManager.instance.primaryFocus != _firstFloorNode) {
                    _firstFloorNode.requestFocus();
                  }
                });
                return _header(theme, firstFloor);
              }),
            _sortWidget(theme.colorScheme),
          ],
          Obx(
            () => _buildBody(theme.colorScheme, _controller.loadingState.value),
          ),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme, ReplyInfo firstFloor) {
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Focus(
            focusNode: _firstFloorNode,
            canRequestFocus: true,
            onFocusChange: (value) {
              if (mounted && value != _firstFloorFocused) {
                setState(() => _firstFloorFocused = value);
              }
            },
            onKeyEvent: (node, event) {
              // 焦点在首楼整体上时，确定键把焦点送入“正文内容”
              // （正文 + 图片，再往下是回复/翻译/点赞/点踩按钮排）；
              // 焦点已在内部停靠点时放行，由其自身响应确定键。
              if (event is KeyDownEvent &&
                  FocusManager.instance.primaryFocus == node &&
                  _isConfirmKey(event.logicalKey)) {
                node.nextFocus();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: ColoredBox(
              color: _firstFloorFocused
                  ? theme.colorScheme.primary.withValues(alpha: 0.08)
                  : Colors.transparent,
              child: ReplyItemGrpc(
                replyItem: firstFloor,
                replyLevel: 2,
                needDivider: false,
                focusableBody: false,
                focusableActions: true,
                focusableContent: true,
                onReply: (replyItem) =>
                    _controller.onReply(replyItem, index: -1),
                upMid: widget.upMid ?? _controller.upMid,
                onCheckReply: _controller.onCheckReply,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Divider(
            height: 20,
            color: theme.dividerColor.withValues(alpha: 0.1),
            thickness: 6,
          ),
        ),
      ],
    );
  }

  static bool _isConfirmKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.gameButtonA;

  Widget _sortWidget(ColorScheme colorScheme) {
    return SliverPinnedHeader(
      backgroundColor: colorScheme.surface,
      child: Padding(
        padding: const .fromLTRB(12, 2.5, 6, 2.5),
        child: Row(
          mainAxisAlignment: .spaceBetween,
          children: [
            Obx(
              () {
                final count = _controller.count.value;
                return count != -1
                    ? Text(
                        '相关回复共${NumUtils.numFormat(count)}条',
                        style: const TextStyle(fontSize: 13),
                      )
                    : const SizedBox.shrink();
              },
            ),
            TextButton.icon(
              style: Style.buttonStyle,
              onPressed: _controller.queryBySort,
              icon: Icon(Icons.sort, size: 16, color: colorScheme.secondary),
              label: Obx(
                () => Text(
                  _controller.sortType.value.label,
                  style: TextStyle(fontSize: 13, color: colorScheme.secondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    ColorScheme colorScheme,
    LoadingState<List<ReplyInfo>?> loadingState,
  ) {
    final jumpIndex = _controller.index.value;
    return switch (loadingState) {
      Loading() => const SliverPrototypeExtentList(
        prototypeItem: VideoReplySkeleton(),
        delegate: SliverSingleChildDelegate(
          count: 8,
          child: VideoReplySkeleton(),
        ),
      ),
      Success(:final response!) => SuperSliverList.builder(
        listController: _controller.listController,
        itemBuilder: (context, index) {
          if (index == response.length) {
            _controller.onLoadMore();
            return Container(
              height: 125,
              alignment: Alignment.center,
              margin: .only(bottom: MediaQuery.viewPaddingOf(context).bottom),
              child: Text(
                _controller.isEnd ? '没有更多了' : '加载中...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.outline,
                ),
              ),
            );
          }
          final child = _replyItem(context, response[index], index);
          if (jumpIndex == index) {
            return _controller.colorAnimWrapper(colorScheme, child);
          }
          return child;
        },
        itemCount: response.length + 1,
      ),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: _controller.onReload,
      ),
    };
  }

  Widget _replyItem(BuildContext context, ReplyInfo replyItem, int index) {
    return ReplyItemGrpc(
      replyItem: replyItem,
      replyLevel: isDialogue ? 3 : 2,
      // 详情页的子回复列表不参与焦点遍历（确定键焦点只在首楼操作按钮）
      focusableBody: false,
      focusableActions: false,
      onReply: (replyItem) => _controller.onReply(replyItem, index: index),
      onDelete: (item, subIndex) => _controller.onRemove(index, item, null),
      upMid: _controller.upMid,
      showDialogue: () => MiniScaffold.of(context).showBottomSheet(
        constraints: const BoxConstraints(),
        (context) => VideoReplyReplyPanel(
          oid: replyItem.oid.toInt(),
          rpid: replyItem.root.toInt(),
          dialog: replyItem.dialog.toInt(),
          replyType: widget.replyType,
          isVideoDetail: true,
          isNested: widget.isNested,
        ),
      ),
      jumpToDialogue: () {
        if (!_controller.setIndexById(replyItem.parent)) {
          SmartDialog.showToast('评论可能已被删除');
        }
      },
      onCheckReply: _controller.onCheckReply,
    );
  }
}
