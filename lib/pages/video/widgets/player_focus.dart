import 'dart:async';
import 'dart:io' show exit, Platform;
import 'dart:math' as math;

import 'package:PiliPlus/pages/common/common_intro_controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyUpEvent, LogicalKeyboardKey, HardwareKeyboard;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

class PlayerFocus extends StatefulWidget {
  const PlayerFocus({
    super.key,
    required this.child,
    required this.plPlayerController,
    this.introController,
    required this.onSendDanmaku,
    this.canPlay,
    this.onSkipSegment,
    this.onRefresh,
    this.focusNode,
    this.sidePanelActive = false,
    this.onEnterSidePanel,
  });

  final Widget child;
  final PlPlayerController plPlayerController;
  final CommonIntroController? introController;
  final VoidCallback onSendDanmaku;
  final ValueGetter<bool>? canPlay;
  final ValueGetter<bool>? onSkipSegment;
  final VoidCallback? onRefresh;

  /// 由页面提供 FocusNode，便于把焦点交还给播放器；
  /// 为 null 时组件内部自建。
  final FocusNode? focusNode;

  /// 焦点是否在右侧栏目。为 true 时本组件放行所有按键，
  /// 让默认焦点遍历（方向键/确定键）在侧栏生效。
  final bool sidePanelActive;

  /// 菜单键（遥控器/键盘 Menu 键）：非全屏时把焦点移入右侧栏目。
  final VoidCallback? onEnterSidePanel;

  @override
  State<PlayerFocus> createState() => PlayerFocusState();
}

class PlayerFocusState extends State<PlayerFocus> {
  FocusNode? _internalNode;

  FocusNode get _node =>
      widget.focusNode ??
      (_internalNode ??= FocusNode(debugLabel: 'PlayerFocus'));

  @override
  void dispose() {
    _internalNode?.dispose();
    super.dispose();
  }

  /// 请求焦点回到播放器
  void requestFocus() => _node.requestFocus();

  static bool _shouldHandle(LogicalKeyboardKey logicalKey) {
    return logicalKey == LogicalKeyboardKey.tab ||
        logicalKey == LogicalKeyboardKey.arrowLeft ||
        logicalKey == LogicalKeyboardKey.arrowRight ||
        logicalKey == LogicalKeyboardKey.arrowUp ||
        logicalKey == LogicalKeyboardKey.arrowDown;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: true,
      onKeyEvent: (node, event) {
        final handled = _handleKey(context, event);
        if (handled) {
          return KeyEventResult.handled;
        }
        // 焦点在播放器上时，方向键/Tab 由播放器消费（阻止焦点遍历）；
        // 焦点在右侧栏目时放行，让默认遍历生效。
        if (!widget.sidePanelActive && _shouldHandle(event.logicalKey)) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: widget.child,
    );
  }

  bool get isFullScreen => widget.plPlayerController.isFullScreen.value;
  bool get hasPlayer => widget.plPlayerController.videoPlayerController != null;

  void _setVolume({required bool isIncrease}) {
    final volume = isIncrease
        ? math.min(
            widget.plPlayerController.maxVolume,
            widget.plPlayerController.volume.value + 0.1,
          )
        : math.max(0.0, widget.plPlayerController.volume.value - 0.1);
    widget.plPlayerController.setVolume(volume);
  }

  void _stepPlaybackSpeed({required bool isIncrease}) {
    final speed = widget.plPlayerController.playbackSpeed;
    final speedList = widget.plPlayerController.speedList;
    final newSpeed = isIncrease
        ? speedList.where((e) => e > speed).minOrNull
        : speedList.where((e) => e < speed).maxOrNull;
    if (newSpeed != null) {
      widget.plPlayerController.setPlaybackSpeed(newSpeed);
    }
    SmartDialog.showToast('${newSpeed ?? speed}x播放');
  }

  void _updateVolume(KeyEvent event, {required bool isIncrease}) {
    if (event is KeyDownEvent) {
      if (hasPlayer) {
        _setVolume(isIncrease: isIncrease);
        widget.plPlayerController
          ..longPressTimer?.cancel()
          ..longPressTimer = Timer.periodic(
            const Duration(milliseconds: 150),
            (_) => _setVolume(isIncrease: isIncrease),
          );
      }
    } else if (event is KeyUpEvent) {
      widget.plPlayerController.cancelLongPressTimer();
    }
  }

  bool _handleKey(BuildContext context, KeyEvent event) {
    // 焦点在右侧栏目时，播放器热键全部让位给焦点遍历
    if (widget.sidePanelActive) {
      return false;
    }

    final key = event.logicalKey;

    final isKeyQ = key == LogicalKeyboardKey.keyQ;
    if (isKeyQ || key == LogicalKeyboardKey.keyR) {
      if (HardwareKeyboard.instance.isMetaPressed) {
        if (isKeyQ && Platform.isMacOS) {
          exit(0);
        }
        return true;
      }
      if (event is KeyDownEvent) {
        if (widget.plPlayerController.isLive) {
          widget.onRefresh?.call();
        } else {
          widget.introController!.onStartTriple();
        }
      } else if (event is KeyUpEvent && !widget.plPlayerController.isLive) {
        widget.introController!.onCancelTriple(isKeyQ);
      }
      return true;
    } else if (event is KeyDownEvent) {
      if (widget.introController?.isTripling ?? false) {
        widget.introController!.onCancelTriple();
      }
    }

    final isArrowUp = key == LogicalKeyboardKey.arrowUp;
    if (isArrowUp || key == LogicalKeyboardKey.arrowDown) {
      if (isArrowUp) {
        // 上键：切换全屏 / 非全屏
        if (event is KeyDownEvent) {
          widget.plPlayerController.triggerFullScreen(status: !isFullScreen);
        }
        return true;
      }
      _updateVolume(event, isIncrease: false);
      return true;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (!widget.plPlayerController.isLive) {
        if (event is KeyDownEvent) {
          if (hasPlayer && !widget.plPlayerController.longPressStatus.value) {
            widget.plPlayerController
              ..longPressTimer?.cancel()
              ..longPressTimer = Timer(
                const Duration(milliseconds: 200),
                () => widget.plPlayerController
                  ..cancelLongPressTimer()
                  ..setLongPressStatus(true),
              );
          }
        } else if (event is KeyUpEvent) {
          widget.plPlayerController.cancelLongPressTimer();
          if (hasPlayer) {
            if (widget.plPlayerController.longPressStatus.value) {
              widget.plPlayerController.setLongPressStatus(false);
            } else {
              widget.plPlayerController.onForward(
                widget.plPlayerController.fastForBackwardDuration,
              );
            }
          }
        }
      }
      return true;
    }

    if (event is KeyDownEvent) {
      switch (key) {
        case LogicalKeyboardKey.space:
          if (widget.plPlayerController.isLive || widget.canPlay!()) {
            if (hasPlayer) {
              widget.plPlayerController.onDoubleTapCenter();
            }
          }
          return true;

        case LogicalKeyboardKey.keyF:
          final isFullScreen = this.isFullScreen;
          if (isFullScreen && widget.plPlayerController.controlsLock.value) {
            widget.plPlayerController
              ..controlsLock.value = false
              ..showControls.value = false;
          }
          widget.plPlayerController.triggerFullScreen(
            status: !isFullScreen,
            inAppFullScreen: HardwareKeyboard.instance.isShiftPressed,
          );
          return true;

        case LogicalKeyboardKey.contextMenu:
          // 菜单键（遥控器 Menu / 键盘 Application 键）：
          // 非全屏时把焦点移入右侧栏目，便于操作评论/相关视频。
          if (!widget.sidePanelActive && !isFullScreen) {
            widget.onEnterSidePanel?.call();
          }
          return true;

        case LogicalKeyboardKey.keyD:
          final newVal =
              !widget.plPlayerController.enableShowDanmakuAdaptive.value;
          widget.plPlayerController.enableShowDanmakuAdaptive.value = newVal;
          if (!widget.plPlayerController.tempPlayerConf) {
            GStorage.setting.put(
              widget.plPlayerController.isLive
                  ? SettingBoxKey.enableShowLiveDanmaku
                  : SettingBoxKey.enableShowDanmaku,
              newVal,
            );
          }
          return true;

        case LogicalKeyboardKey.keyP:
          if (PlatformUtils.isDesktop && hasPlayer && !isFullScreen) {
            widget.plPlayerController
              ..toggleDesktopPip()
              ..controlsLock.value = false
              ..showControls.value = false;
          }
          return true;

        case LogicalKeyboardKey.keyM:
          if (hasPlayer) {
            final isMuted = !widget.plPlayerController.isMuted;
            widget.plPlayerController.videoPlayerController!.setVolume(
              isMuted ? 0 : widget.plPlayerController.volume.value * 100,
            );
            widget.plPlayerController.isMuted = isMuted;
            SmartDialog.showToast('${isMuted ? '' : '取消'}静音');
          }
          return true;

        case LogicalKeyboardKey.keyS:
          if (hasPlayer && isFullScreen) {
            widget.plPlayerController.takeScreenshot();
          }
          return true;

        case LogicalKeyboardKey.keyL:
          if (isFullScreen || widget.plPlayerController.isDesktopPip) {
            widget.plPlayerController.onLockControl(
              !widget.plPlayerController.controlsLock.value,
            );
          }
          return true;

        case LogicalKeyboardKey.enter:
          if (widget.onSkipSegment?.call() ?? false) {
            return true;
          }
          widget.onSendDanmaku();
          return true;
      }

      if (!widget.plPlayerController.isLive) {
        final isDigit1 = key == LogicalKeyboardKey.digit1;
        if (isDigit1 || key == LogicalKeyboardKey.digit2) {
          if (HardwareKeyboard.instance.isShiftPressed && hasPlayer) {
            final speed = isDigit1 ? 1.0 : 2.0;
            if (speed != widget.plPlayerController.playbackSpeed) {
              widget.plPlayerController.setPlaybackSpeed(speed);
            }
            SmartDialog.showToast('${speed}x播放');
          }
          return true;
        }

        switch (key) {
          case LogicalKeyboardKey.arrowLeft:
            if (hasPlayer) {
              widget.plPlayerController.onBackward(
                widget.plPlayerController.fastForBackwardDuration,
              );
            }
            return true;

          case LogicalKeyboardKey.keyW:
            if (HardwareKeyboard.instance.isMetaPressed) {
              return true;
            }
            widget.introController?.actionCoinVideo();
            return true;

          case LogicalKeyboardKey.keyE:
            widget.introController?.actionFavVideo(isQuick: true);
            return true;

          case LogicalKeyboardKey.keyT || LogicalKeyboardKey.keyV:
            widget.introController?.viewLater();
            return true;

          case LogicalKeyboardKey.keyG:
            if (widget.introController case final UgcIntroController ugcCtr) {
              ugcCtr.actionRelationMod(context);
            }
            return true;

          case LogicalKeyboardKey.bracketLeft:
            if (widget.introController case final introController?) {
              if (!introController.prevPlay()) {
                SmartDialog.showToast('已经是第一集了');
              }
            }
            return true;

          case LogicalKeyboardKey.bracketRight:
            if (widget.introController case final introController?) {
              if (!introController.nextPlay()) {
                SmartDialog.showToast('已经是最后一集了');
              }
            }
            return true;

          case LogicalKeyboardKey.comma || LogicalKeyboardKey.period:
            if (hasPlayer && !widget.plPlayerController.longPressStatus.value) {
              _stepPlaybackSpeed(isIncrease: key == LogicalKeyboardKey.period);
            }
            return true;
        }
      }
    }

    return false;
  }
}
