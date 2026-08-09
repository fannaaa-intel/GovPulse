import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/services/chat_service.dart';
import '../../../core/theme/citizen_ui.dart';
import '../../../core/widgets/Home/Chat-bubbles/chat_bubbles_widget.dart';
import '../../../core/widgets/Home/Chat-bubbles/chat_panel_card.dart';
import '../../../core/widgets/Home/nav/nav_band.dart'
    show kNavPhoneShortestSide;

// ════════════════════════════════════════════════════════════════════════════
//  Docked chat window for the citizen web shell — Messenger-style.
//
//  Pinned to the bottom-right, floating above the three columns, and
//  deliberately NOT a dialog or a route: there is no barrier and no dimmed
//  backdrop, so the feed keeps scrolling and every rail item stays clickable
//  while the chat is open. That is the whole difference from the modal it
//  replaces.
//
//  ── What this reuses ──────────────────────────────────────────────────────
//  Everything that matters. This file contains no chat logic at all:
//
//    • [ChatService.I] is the single source of truth for messages, sending,
//      history, staff hand-off and realtime — untouched.
//    • [HomeChatPanelCard] renders the whole thread and the input row, and is
//      already "a pure view that listens to the service". It is the same widget
//      the draggable global bubble uses, so the docked window and the bubble
//      cannot drift apart.
//    • The header — agent avatar, name, and the green Online / "Connected to a
//      person" subtitle — comes from that card too. It only needed somewhere to
//      put minimise and close, which is the `headerActions` slot.
//    • [ChatAgentAvatar] for the minimised pill.
//
//  What is new here is only the WINDOW: where it sits, how big it is, and the
//  open / minimised / closed state. Nothing about chat itself.
//
//  ── Why not reuse HomeChatBubble ──────────────────────────────────────────
//  The global bubble (main.dart's overlay) does something related but
//  incompatible: it is draggable, it has a delete zone, and it paints a
//  full-screen scrim (`Color(0x61000000)`) that swallows taps behind it. Inside
//  the shell that scrim is exactly wrong — the page has to stay live. So this
//  reuses the bubble's PANEL while leaving its chrome alone. The bubble itself
//  is untouched and still serves the mobile app and the live web route.
// ════════════════════════════════════════════════════════════════════════════

/// Window size for the DOCKED (wide) band. Roughly Messenger's: wide enough for
/// a readable thread, short enough to leave the feed visible behind it.
const double _kChatWidth = 360;
const double _kChatHeight = 520;

/// Distance from the viewport's bottom-right corner.
const double _kDockInset = 20;

/// Below this the docked card stops making sense and the window goes
/// full-screen instead. See [_CitizenDockedChatState.build].
///
/// Reuses [kNavPhoneShortestSide] rather than inventing a number: 600 is
/// already where this shell declares a viewport too narrow for normal chrome
/// (it is the same line the user chip collapses to avatar-only at).
const double _kFullScreenBelow = kNavPhoneShortestSide;

/// Horizontal space a message bubble can never occupy, subtracted before the
/// fraction below is applied: the message list's own padding (14 each side)
/// plus the avatar and its gap (28 + 7) on whichever side the bubble sits.
const double _kBubbleChrome = 63;

/// Share of the REMAINING width a bubble may take in the full-screen sheet.
/// A normal chat proportion; 240 is kept as a floor so this can only ever
/// widen a bubble, never narrow one.
const double _kSheetBubbleFraction = 0.70;

/// The card's own default, repeated here as the floor. Kept in sync by the
/// floor's purpose rather than by import: the point is that the sheet never
/// renders a bubble narrower than every other caller already gets.
const double _kBubbleFloor = 240;

/// Open / minimised / closed, owned by the shell so the window survives tab
/// switches and the "Chat with Agent" action can restore it.
enum DockedChatState { closed, open, minimised }

class CitizenDockedChat extends StatefulWidget {
  final DockedChatState state;

  /// Minimise ⇄ restore, and dismiss. The shell owns the state so that closing
  /// the window does not lose the conversation — [ChatService] keeps it either
  /// way, but the window position and the unread count live here.
  final VoidCallback onMinimise;
  final VoidCallback onRestore;
  final VoidCallback onClose;

  const CitizenDockedChat({
    super.key,
    required this.state,
    required this.onMinimise,
    required this.onRestore,
    required this.onClose,
  });

  @override
  State<CitizenDockedChat> createState() => _CitizenDockedChatState();
}

class _CitizenDockedChatState extends State<CitizenDockedChat> {
  /// Agent messages that arrived while minimised. Cleared on restore.
  int _unread = 0;

  @override
  void didUpdateWidget(covariant CitizenDockedChat old) {
    super.didUpdateWidget(old);
    if (widget.state == DockedChatState.open &&
        old.state != DockedChatState.open) {
      _unread = 0;
    }
  }

  void _onAgentMessage() {
    if (widget.state == DockedChatState.minimised && mounted) {
      setState(() => _unread++);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.state == DockedChatState.closed) return const SizedBox.shrink();

    final minimised = widget.state == DockedChatState.minimised;

    // ── Narrow: full-screen sheet ──────────────────────────────────────────
    //
    // A 360-wide card docked 20px off the corner is a floating window when
    // there is a page to float over, and nothing but a cramped obstruction when
    // there is not. At 435 it covered 83% of the viewport while still drawing
    // itself as a corner card; below ~380 it simply clipped against the Stack
    // edge. Narrow gets the sheet idiom instead: edge to edge, square corners,
    // no dock inset.
    //
    // Only the EXPANDED window changes. The minimised pill is 280 at most and
    // still reads correctly parked in the corner, so it keeps the docked
    // treatment in both bands.
    if (!minimised && MediaQuery.of(context).size.width < _kFullScreenBelow) {
      return Positioned.fill(child: _fullScreenSheet(context));
    }

    return Positioned(
      right: _kDockInset,
      bottom: _kDockInset,
      // Only the window itself takes hits. Everything around it — the feed, the
      // rails, the top nav — keeps receiving pointer events, which is what makes
      // this non-blocking where the modal was not.
      child: minimised ? _minimisedPill() : _window(),
    );
  }

  /// The narrow-band window: fills the viewport rather than floating in it.
  ///
  /// Size comes from MediaQuery and is reduced by the safe-area padding and the
  /// keyboard inset, so it can never exceed the viewport — which is what fixes
  /// both the below-380 horizontal clip and the latent short-window vertical
  /// clip the fixed 520 height carried. The shell's Stack does not wrap this
  /// child in a SafeArea (only its first child), so the SafeArea is applied
  /// here.
  Widget _fullScreenSheet(BuildContext context) {
    final mq = MediaQuery.of(context);
    final pad = mq.padding;
    final w = mq.size.width - pad.left - pad.right;
    final h = mq.size.height - pad.top - pad.bottom - mq.viewInsets.bottom;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: HomeChatPanelCard(
          panelW: w,
          panelH: h,
          // Square: the card meets every viewport edge, so rounded corners
          // would leave the page showing through in four notches.
          borderRadius: BorderRadius.zero,
          // The card's 240 default is right for a 360-wide docked window and
          // too narrow once the sheet spans the viewport. Widen it in
          // proportion to the space actually available to a bubble, floored at
          // 240 so the narrow end of the band is untouched.
          bubbleMaxWidth: math.max(
            _kBubbleFloor,
            (w - _kBubbleChrome) * _kSheetBubbleFraction,
          ),
          onAgentMessage: _onAgentMessage,
          headerActions: [
            _headerButton(
              icon: Icons.remove_rounded,
              tooltip: 'Minimise',
              onTap: widget.onMinimise,
            ),
            _headerButton(
              icon: Icons.close_rounded,
              tooltip: 'Close chat',
              onTap: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }

  Widget _window() {
    return Material(
      color: Colors.transparent,
      child: HomeChatPanelCard(
        panelW: _kChatWidth,
        panelH: _kChatHeight,
        onAgentMessage: _onAgentMessage,
        headerActions: [
          _headerButton(
            icon: Icons.remove_rounded,
            tooltip: 'Minimise',
            onTap: widget.onMinimise,
          ),
          _headerButton(
            icon: Icons.close_rounded,
            tooltip: 'Close chat',
            onTap: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _headerButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: CitizenUi.textMuted),
        ),
      ),
    );
  }

  /// Collapsed state: a compact bar that keeps the conversation one click away
  /// and shows how many agent messages landed while it was away.
  Widget _minimisedPill() {
    final connected = ChatService.I.isConnectedToStaff;
    final name = connected
        ? (ChatService.I.connectedStaffName?.trim().isNotEmpty ?? false)
              ? ChatService.I.connectedStaffName!.trim()
              : 'LGU Staff'
        : 'LGU Aparri Agent';

    return Material(
      color: CitizenUi.surface,
      elevation: 8,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: widget.onRestore,
        child: Container(
          height: 52,
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: CitizenUi.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ChatAgentAvatar(
                size: 34,
                photoUrl: connected
                    ? ChatService.I.connectedStaffPhotoUrl
                    : null,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: CitizenUi.textPrimary,
                  ),
                ),
              ),
              if (_unread > 0) ...[
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: CitizenUi.badge,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _unread > 9 ? '9+' : '$_unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              _headerButton(
                icon: Icons.close_rounded,
                tooltip: 'Close chat',
                onTap: widget.onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
