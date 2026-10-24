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
import 'package:PiliPlus/pages/video/reply/widgets/reply_stops.dart';
import 'package:PiliPlus/pages/video/reply_reply/controller.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/extension/widget_ext.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:fixnum/fixnum.dart' show Int64;
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

  /// 首楼的焦点停靠点集合。
  /// 注意：评论详情是 MiniScaffold 的底部弹窗，与视频页同处一个 FocusScope，
  /// 打开时原焦点（评论主楼）仍在，`autofocus` 会被 FocusManager 丢弃
  /// （autofocus 仅在 scope.focusedChild == null 时生效），因此必须显式请求焦点。
  late final ReplyStops _firstFloorStops;

  /// 楼中楼各条的焦点停靠点集合（按评论 id 缓存，列表重建不丢焦点状态）
  final Map<int, ReplyStops> _subStops = {};

  /// 打开本页前的焦点，关闭时归还
  FocusNode? _previousFocus;

  /// 打开本页前的焦点层级，关闭时恢复（一般为 2 = 侧栏内容）
  late int _previousLevel;

  /// 当前焦点处于“评论内部”的停靠点（null = 焦点在某条评论整体上）
  ReplyStops? _currentInner;

  /// 详情弹窗正在关闭（关闭动画期间禁用返回键）。
  /// 弹窗关闭走的是本地历史项移除（Get.back → Navigator.pop → LocalHistoryEntry），
  /// 关闭动画期间 PopScope 仍未注销；此时若再次返回，本地历史已空，
  /// Navigator.pop 会直接把视频页路由弹掉，因此必须挡掉。
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _previousFocus = FocusManager.instance.primaryFocus;
    _previousLevel = TvFocusLevel.level;
    TvFocusLevel.level = 3; // 评论详情
    _firstFloorStops = ReplyStops(debugLabel: 'replyDetailFirstFloor');
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
        _firstFloorStops.whole.requestFocus();
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
    TvFocusLevel.level = _previousLevel;
    _firstFloorStops.dispose();
    for (final stops in _subStops.values) {
      stops.dispose();
    }
    _subStops.clear();
    Get.delete<VideoReplyReplyController>(tag: _tag);
    super.dispose();
  }

  /// 焦点进入 / 退出某条评论的内部停靠点。
  /// 进入 = 层级 4（评论内部），退出 = 层级 3（评论详情）。
  void _onInnerStops(ReplyStops? stops) {
    _currentInner = stops;
    TvFocusLevel.level = stops != null ? 4 : 3;
  }

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
  Widget buildPage(ThemeData theme) {
    Widget child() => enableSlide ? slideList(theme) : buildList(theme);
    // FocusScope 把方向键遍历限制在详情页内，不会穿透到背后的视频页/评论列表。
    // PopScope：返回键在详情页内逐层退出——
    //   - 焦点在某条评论的内部停靠点：先退回该评论整体；
    //   - 否则：关闭详情弹窗（焦点归还评论列表）。
    // 只有侧栏最外层（TvFocusLevel == 1）的返回键才交还播放器，
    // 由视频页的 popScope 处理，这里不参与。
    return PopScope(
      // 独立路由打开的详情页（非视频详情侧栏）不拦截，返回正常弹路由
      canPop: !widget.isVideoDetail,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _closing) {
          return;
        }
        final inner = _currentInner;
        if (inner != null) {
          // 焦点在某条评论的内部停靠点：先退回该评论整体
          inner.whole.requestFocus();
          _onInnerStops(null);
        } else {
          // 焦点在某条评论整体上：关闭详情弹窗（焦点归还评论列表）
          _closing = true;
          Get.back();
        }
      },
      child: FocusScope(
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
                      FocusManager.instance.primaryFocus !=
                          _firstFloorStops.whole) {
                    _firstFloorStops.whole.requestFocus();
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
        // 首楼：整条评论是一个停靠点（_firstFloorStops.whole）。
        // 上下键在评论之间移动；确定键进入评论内部
        // （正文 → 回复 → 翻译 → 点踩 → 点赞）。
        SliverToBoxAdapter(
          child: ReplyItemGrpc(
            replyItem: firstFloor,
            replyLevel: 2,
            needDivider: false,
            innerStops: _firstFloorStops,
            onInnerFocusChange: _onInnerStops,
            onReply: (replyItem) => _controller.onReply(replyItem, index: -1),
            upMid: widget.upMid ?? _controller.upMid,
            onCheckReply: _controller.onCheckReply,
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
            // 排序按钮排除出方向键遍历：它位于首楼正下方，
            // 默认几何遍历会让它赢过楼中楼第一条，破坏“上下键在评论间移动”。
            // 触摸仍可用。
            ExcludeFocus(
              excluding: true,
              child: TextButton.icon(
                style: Style.buttonStyle,
                onPressed: _controller.queryBySort,
                icon: Icon(Icons.sort, size: 16, color: colorScheme.secondary),
                label: Obx(
                  () => Text(
                    _controller.sortType.value.label,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.secondary,
                    ),
                  ),
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
    // 楼中楼：整条评论是一个停靠点，上下键在评论之间移动；
    // 确定键进入该评论内部（正文/回复/点踩/点赞）。
    // 触摸点击仍打开这条子回复自己的详情（向后兼容）。
    final stops = _subStops.putIfAbsent(
      replyItem.id.toInt(),
      () => ReplyStops(debugLabel: 'subReply-${replyItem.id}'),
    );
    return ReplyItemGrpc(
      replyItem: replyItem,
      replyLevel: isDialogue ? 3 : 2,
      innerStops: stops,
      onInnerFocusChange: _onInnerStops,
      replyReply: (item, id) => MiniScaffold.of(context).showBottomSheet(
        constraints: const BoxConstraints(),
        (context) => VideoReplyReplyPanel(
          id: id,
          oid: item.oid.toInt(),
          rpid: item.id.toInt(),
          firstFloor: item,
          replyType: widget.replyType,
          isVideoDetail: true,
          isNested: widget.isNested,
          upMid: _controller.upMid,
        ),
      ),
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
