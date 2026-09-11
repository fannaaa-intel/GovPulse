import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Makes a hand-drawn tap target reachable by keyboard, without restyling it.
///
/// ── Why this exists ───────────────────────────────────────────────────────
/// Citizen web draws most of its controls as a [GestureDetector] wrapped
/// around a decorated box. A GestureDetector contributes NO focus node and NO
/// semantics node, so every one of those controls is unreachable by Tab and
/// silent to a screen reader — which for a government service is a real
/// accessibility defect, not a polish item.
///
/// The obvious fix — swap in an [InkWell] or a Material button — is wrong
/// wherever the control owns a press animation. Several of these drive a
/// scale-down from `onTapDown` / `onTapUp`, a pair no Material button exposes,
/// so converting them changes how the control feels and risks the visual
/// regression that makes an accessibility pass unshippable.
///
/// This wraps instead of replacing. The gesture handling underneath is
/// untouched; this adds only what was missing:
///
///   * a [Focus] node, so the control is in the Tab order;
///   * Enter and Space activation, which is what a keyboard user expects of
///     something announced as a button;
///   * a visible focus ring, because a focusable control nobody can SEE is
///     focused is no better than an unreachable one.
///
/// The semantics label is deliberately NOT set here — the caller wraps this in
/// its own [Semantics] with a name it actually knows ("Police", "Submit"),
/// since a generic label is worse than none.
class FocusActivate extends StatefulWidget {
  const FocusActivate({
    super.key,
    required this.child,
    required this.onActivate,
    this.borderRadius = 16,
    this.enabled = true,
  });

  final Widget child;

  /// Run when the control is activated from the KEYBOARD. The pointer path
  /// keeps whatever handler the wrapped widget already had, so a control that
  /// distinguishes tap-down from tap-up is unaffected.
  final VoidCallback onActivate;

  /// Radius of the focus ring. Match the wrapped card so the ring traces its
  /// real edge rather than a rectangle around it.
  final double borderRadius;

  /// False removes it from the Tab order, for a control that is currently
  /// disabled — a disabled button should still be ANNOUNCED (the caller's
  /// Semantics handles that) but should not be a stop on the way to a control
  /// that works.
  final bool enabled;

  @override
  State<FocusActivate> createState() => _FocusActivateState();
}

class _FocusActivateState extends State<FocusActivate> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: widget.enabled,
      skipTraversal: !widget.enabled,
      onFocusChange: (v) {
        if (mounted) setState(() => _focused = v);
      },
      onKeyEvent: (node, event) {
        if (!widget.enabled) return KeyEventResult.ignored;
        // KeyDownEvent only: a key held down repeats, and acting on repeats
        // would fire a submit or a dial several times from one press.
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          widget.onActivate();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(
            // Transparent rather than absent so the box never changes size
            // when focus arrives — a ring that adds 2px would shift the
            // layout of everything beside it.
            color: _focused ? AppColors.primaryBlue : Colors.transparent,
            width: 2,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
