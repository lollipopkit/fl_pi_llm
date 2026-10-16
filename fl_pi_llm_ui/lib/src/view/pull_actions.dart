import 'dart:math' as math;

import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// What pulling a scrollable past one of its ends does.
final class PullAction {
  const PullAction({
    required this.icon,
    required this.label,
    required this.readyLabel,
    required this.onTrigger,
    this.hold = Duration.zero,
  });

  final IconData icon;

  /// Shown while it is being pulled, short of [PullActions.threshold].
  final String label;

  /// Shown past it: what letting go does, or, with a [hold], what holding
  /// does.
  final String readyLabel;

  final VoidCallback onTrigger;

  /// Zero: done on letting go past the threshold. Otherwise done once held
  /// past it this long, finger still down; a ring fills meanwhile.
  final Duration hold;
}

/// Pull past the top or the bottom of [child] (a scrollable) to do
/// something: a label shows what, and [PullAction.hold] says how.
///
/// The scrollable must overscroll for this to see a pull: give it
/// [PullActions.physics].
class PullActions extends StatefulWidget {
  const PullActions({super.key, this.top, this.bottom, required this.child});

  final PullAction? top;
  final PullAction? bottom;
  final Widget child;

  /// How far past an end a pull must go, in logical pixels.
  static const threshold = 64.0;

  /// Overscrolls on every platform, even when everything fits.
  static const physics = AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics());

  @override
  State<PullActions> createState() => _PullActionsState();
}

class _PullActionsState extends State<PullActions> with SingleTickerProviderStateMixin {
  /// How far past the top and the bottom the content is now.
  final _top = 0.0.vn;
  final _bottom = 0.0.vn;

  /// The finger is on the scrollable.
  var _dragging = false;

  /// The top pull is past the threshold with the finger down: letting go
  /// does it.
  var _topReady = false;

  /// The bottom pull fired during this drag: once per drag.
  var _bottomDone = false;

  late final _hold = AnimationController(vsync: this)..addStatusListener(_onHoldStatus);

  @override
  void dispose() {
    _hold.dispose();
    _top.dispose();
    _bottom.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    final m = n.metrics;
    _top.value = math.max(0, m.minScrollExtent - m.pixels);
    _bottom.value = math.max(0, m.pixels - m.maxScrollExtent);

    final dragging = switch (n) {
      ScrollStartNotification(:final dragDetails) => dragDetails != null,
      ScrollUpdateNotification(:final dragDetails) => dragDetails != null,
      OverscrollNotification(:final dragDetails) => dragDetails != null,
      ScrollEndNotification() => false,
      _ => _dragging,
    };
    final released = _dragging && !dragging;
    _dragging = dragging;
    if (dragging) _bottomDone = _bottomDone && _bottom.value > 0;

    _updateTop(released);
    _updateBottom();
    return false;
  }

  void _updateTop(bool released) {
    final action = widget.top;
    if (action == null) return;
    if (released) {
      if (_topReady) {
        _topReady = false;
        HapticFeedback.mediumImpact();
        action.onTrigger();
      }
      return;
    }
    if (!_dragging) return;
    final ready = _top.value >= PullActions.threshold;
    if (ready && !_topReady) HapticFeedback.selectionClick();
    if (ready != _topReady) setState(() => _topReady = ready);
  }

  void _updateBottom() {
    final action = widget.bottom;
    if (action == null || action.hold == Duration.zero) return;
    final holding = _dragging && !_bottomDone && _bottom.value >= PullActions.threshold;
    if (holding) {
      if (_hold.status != AnimationStatus.forward && !_hold.isCompleted) {
        HapticFeedback.selectionClick();
        _hold
          ..duration = action.hold
          ..forward();
      }
    } else if (_hold.value > 0 && _hold.status != AnimationStatus.reverse) {
      _hold
        ..reverseDuration = const Duration(milliseconds: 150)
        ..reverse();
    }
  }

  void _onHoldStatus(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    _bottomDone = true;
    _hold.value = 0;
    HapticFeedback.mediumImpact();
    widget.bottom?.onTrigger();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          widget.child,
          if (widget.top case final a?)
            Positioned(
              top: 7,
              left: 0,
              right: 0,
              child: _top.listenVal((d) => _Indicator(
                action: a,
                pulled: d,
                ready: _topReady,
                progress: null,
              )),
            ),
          if (widget.bottom case final a?)
            Positioned(
              bottom: 7,
              left: 0,
              right: 0,
              child: ListenableBuilder(
                listenable: Listenable.merge([_bottom, _hold]),
                builder: (_, _) => _Indicator(
                  action: a,
                  pulled: _bottom.value,
                  ready: _hold.value > 0,
                  progress: a.hold == Duration.zero ? null : _hold.value,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// An icon and a line, fading in with the pull.
class _Indicator extends StatelessWidget {
  const _Indicator({required this.action, required this.pulled, required this.ready, required this.progress});

  final PullAction action;
  final double pulled;
  final bool ready;

  /// The hold so far, 0 to 1; null for an action done on letting go.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    if (pulled <= 0) return const SizedBox.shrink();
    final scheme = context.theme.colorScheme;
    final color = ready ? scheme.primary : scheme.onSurfaceVariant;
    return IgnorePointer(
      child: Opacity(
        opacity: (pulled / PullActions.threshold).clamp(0.0, 1.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 28,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (progress case final p?)
                    CircularProgressIndicator(
                      value: p,
                      strokeWidth: 2,
                      backgroundColor: scheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  Icon(action.icon, size: 17, color: color),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              ready ? action.readyLabel : action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
