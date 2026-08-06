import 'package:flutter/material.dart';

import '../../../core/services/chat_service.dart';
import '../../../core/theme/citizen_ui.dart';
import '../../../core/widgets/Home/Chat-bubbles/chat_bubbles_widget.dart';
import '../../../core/widgets/Home/Chat-bubbles/chat_panel_card.dart';

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

/// Window size. Roughly Messenger's: wide enough for a readable thread, short
/// enough to leave the feed visible behind it.
const double _kChatWidth = 360;
const double _kChatHeight = 520;

/// Distance from the viewport's bottom-right corner.
const double _kDockInset = 20;

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

    return Positioned(
      right: _kDockInset,
      bottom: _kDockInset,
      // Only the window itself takes hits. Everything around it — the feed, the
      // rails, the top nav — keeps receiving pointer events, which is what makes
      // this non-blocking where the modal was not.
      child: minimised ? _minimisedPill() : _window(),
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
