import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart'
    show FocusManager, FocusNode, KeyEventResult, ValueNotifier, VoidCallback;

/// 评论详情页中“一条评论”的遥控器焦点停靠点集合。
///
/// 模型（用户需求）：
/// - 按上下键时，焦点在**评论之间**移动（落在 [whole] 上，默认几何遍历，
///   每条评论独占一行，天然逐条移动）；
/// - 评论内部的“正文 / 回复 / 翻译 / 点踩 / 点赞”**不**被方向键选中；
/// - 只有在整条评论上按确定键，焦点才进入内部，在停靠点之间选择
///   （↑↓←→ 沿链移动，到头/到尾回到 [whole]）。
///
/// 实现要点：内部停靠点的 FocusNode 都设了 `skipTraversal: true`，
/// 因此不参与方向键遍历（`traversalDescendants` 会过滤它们），
/// 但 `requestFocus` 并不检查 skipTraversal，仍可被显式聚焦。
class ReplyStops {
  ReplyStops({String? debugLabel})
    : whole = FocusNode(debugLabel: debugLabel),
      body = FocusNode(
        debugLabel: debugLabel == null ? null : '$debugLabel-body',
        skipTraversal: true,
      ),
      reply = FocusNode(
        debugLabel: debugLabel == null ? null : '$debugLabel-reply',
        skipTraversal: true,
      ),
      translate = FocusNode(
        debugLabel: debugLabel == null ? null : '$debugLabel-translate',
        skipTraversal: true,
      ),
      dislike = FocusNode(
        debugLabel: debugLabel == null ? null : '$debugLabel-dislike',
        skipTraversal: true,
      ),
      like = FocusNode(
        debugLabel: debugLabel == null ? null : '$debugLabel-like',
        skipTraversal: true,
      );

  /// 整条评论的停靠点：方向键遍历（评论间移动）落在它上面，
  /// 确定键进入评论内部。
  final FocusNode whole;

  /// 内部停靠点（均 skipTraversal，只能由 [whole] 上按确定键进入）：
  /// 正文（含图片，确定键 → 图片预览）
  final FocusNode body;

  /// 回复按钮
  final FocusNode reply;

  /// 翻译按钮（评论不支持翻译时不渲染，requestFocus 无效果）
  final FocusNode translate;

  /// 点踩按钮
  final FocusNode dislike;

  /// 点赞按钮
  final FocusNode like;

  /// 整条评论是否持有焦点（供外层画焦点底色）
  final wholeFocused = ValueNotifier<bool>(false);

  void dispose() {
    whole.dispose();
    body.dispose();
    reply.dispose();
    translate.dispose();
    dislike.dispose();
    like.dispose();
    wholeFocused.dispose();
  }

  /// 整条评论（[whole]）的按键处理。
  ///
  /// - 焦点在内部停靠点上：方向键沿 [inner] 链前后移动，到头/到尾回到
  ///   [whole] 并触发 [onExitInner]；确定键放行（由停靠点自身响应）；
  /// - 焦点在整条评论上：确定键进入内部（链首）并触发 [onEnterInner]；
  ///   方向键放行 → 默认几何遍历 → 在评论之间移动。
  static KeyEventResult handleKey(
    FocusNode node,
    KeyEvent event,
    ReplyStops stops,
    List<FocusNode> inner, {
    VoidCallback? onEnterInner,
    VoidCallback? onExitInner,
  }) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final isConfirm =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA;
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && inner.contains(focus)) {
      // 焦点在评论内部停靠点
      if (isConfirm) {
        // 放行：由停靠点自身响应（正文 → 图片预览，按钮 → onPressed）
        return KeyEventResult.ignored;
      }
      final forward =
          key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.arrowRight;
      final backward =
          key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowLeft;
      if (!forward && !backward) {
        return KeyEventResult.ignored;
      }
      final index = inner.indexOf(focus);
      final next = forward ? index + 1 : index - 1;
      if (next >= 0 && next < inner.length) {
        inner[next].requestFocus();
      } else {
        // 到头 / 到尾：回到整条评论
        stops.whole.requestFocus();
        onExitInner?.call();
      }
      return KeyEventResult.handled;
    }
    // 焦点在整条评论上
    if (isConfirm && inner.isNotEmpty) {
      inner.first.requestFocus();
      onEnterInner?.call();
      return KeyEventResult.handled;
    }
    // 方向键等放行：默认几何遍历在评论之间移动
    return KeyEventResult.ignored;
  }
}
