import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../theme/app_colors.dart';

import 'chat_bubbles_widget.dart';
import 'chat_panel_card.dart';

// ── Global visibility notifier ────────────────────────────────────────────────
final ValueNotifier<bool> chatBubbleVisible = ValueNotifier(false);

// ── Global close callback — called by HomePage's PopScope ────────────────────
bool handleChatBubbleBack() {
  return _activeBubbleState?.handleBack() ?? false;
}

_HomeChatBubbleState? _activeBubbleState;

class HomeChatBubble extends StatefulWidget {
  final VoidCallback onDismiss;
  const HomeChatBubble({super.key, required this.onDismiss});

  static void showGlobal() => chatBubbleVisible.value = true;
  static void hideGlobal() => chatBubbleVisible.value = false;

  @override
  State<HomeChatBubble> createState() => _HomeChatBubbleState();
}

class _HomeChatBubbleState extends State<HomeChatBubble>
    with TickerProviderStateMixin {
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;

  late final AnimationController _posCtrl;
  late Animation<double> _posLeftAnim;
  late Animation<double> _posTopAnim;

  late final AnimationController _panelCtrl;
  late final Animation<double> _panelFade;
  late final Animation<double> _panelScale;

  late final AnimationController _exitCtrl;
  late final Animation<double> _exitScale;
  late final Animation<double> _exitOpacity;

  late final AnimationController _bubbleEnterCtrl;
  late Animation<double> _bubbleEnterLeftAnim;
  late Animation<double> _bubbleEnterTopAnim;

  late final AnimationController _kbVisCtrl;

  late final AnimationController _bubbleSpawnCtrl;
  late final Animation<double> _bubbleSpawnScale;
  late final Animation<double> _bubbleSpawnOpacity;

  double _left = 0;
  double _top = 0;
  bool _posInit = false;
  double? _savedLeft;
  double? _savedTop;
  Size? _screen;

  bool _isDragging = false;
  bool _isOverDelete = false;
  bool _chatOpen = false;
  bool _isOnline = true;
  bool _hasUnread = false;

  bool _bubbleMoving = false;
  double _animatedBubbleLeft = 0;
  double _animatedBubbleTop = 0;

  bool _kbIsOpen = false;

  static const double _bubbleSize = 58;
  static const double _margin = 8;
  static const double _deleteNormal = _bubbleSize + 2;
  static const double _deleteHover = _bubbleSize + 8;
  static const double _dotSize = 14;
  static const double _kbOpenThreshold = 220;

  bool handleBack() {
    final keyboardOpen =
        (MediaQuery.maybeOf(context)?.viewInsets.bottom ?? 0) >
        _kbOpenThreshold;
    if (keyboardOpen) {
      FocusScope.of(context).unfocus();
      return true;
    }
    if (_chatOpen) {
      _closeChatAnimated();
      return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _activeBubbleState = this;
    _initAnimations();
    _listenConnectivity();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    _reactToKeyboard(keyboardH);
  }

  void _reactToKeyboard(double keyboardH) {
    if (!_chatOpen) return;

    final nowOpen = keyboardH > _kbOpenThreshold;

    if (nowOpen == _kbIsOpen) {
      return;
    }

    _kbIsOpen = nowOpen;

    if (nowOpen) {
      _kbVisCtrl.reverse();
    } else {
      Future.delayed(const Duration(milliseconds: 80), () {
        if (!mounted || _kbIsOpen) return;

        _kbVisCtrl.forward();
      });
    }
  }

  void _initAnimations() {
    // ── Slide-in on first mount ───────────────────────────────────────────
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(1.6, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

    // ── Spawn scale+fade ──────────────────────────────────────────────────
    _bubbleSpawnCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _bubbleSpawnScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _bubbleSpawnCtrl,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInBack,
      ),
    );
    _bubbleSpawnOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _bubbleSpawnCtrl,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _slideCtrl.forward();
      _bubbleSpawnCtrl.forward();
    });

    // ── Positional snap ───────────────────────────────────────────────────
    _posCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _posLeftAnim = Tween<double>(begin: 0, end: 0).animate(_posCtrl);
    _posTopAnim = Tween<double>(begin: 0, end: 0).animate(_posCtrl);
    _posCtrl.addListener(() {
      if (mounted) {
        setState(() {
          _left = _posLeftAnim.value;
          _top = _posTopAnim.value;
        });
      }
    });

    // ── Panel open/close ──────────────────────────────────────────────────
    _panelCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _panelFade = CurvedAnimation(parent: _panelCtrl, curve: Curves.easeOut);
    _panelScale = Tween<double>(
      begin: 0.88,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _panelCtrl, curve: Curves.easeOutBack));

    // ── Delete-zone exit ──────────────────────────────────────────────────
    _exitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _exitScale = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _exitCtrl, curve: Curves.easeInBack));
    _exitOpacity = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _exitCtrl, curve: Curves.easeIn));

    // ── Bubble panel-corner animation ─────────────────────────────────────
    _bubbleEnterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _bubbleEnterLeftAnim = Tween<double>(
      begin: 0,
      end: 0,
    ).animate(_bubbleEnterCtrl);
    _bubbleEnterTopAnim = Tween<double>(
      begin: 0,
      end: 0,
    ).animate(_bubbleEnterCtrl);
    _bubbleEnterCtrl.addListener(() {
      if (mounted) {
        setState(() {
          _animatedBubbleLeft = _bubbleEnterLeftAnim.value;
          _animatedBubbleTop = _bubbleEnterTopAnim.value;
        });
      }
    });
    _bubbleEnterCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() => _bubbleMoving = false);
      }
    });

    // ── Keyboard visibility animation ────────────────────────────────────
    _kbVisCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 220),
      value: 1.0,
    );

    // Smooth upward motion

    CurvedAnimation(
      parent: _kbVisCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInOut,
    );

    // Very subtle scale

    CurvedAnimation(
      parent: _kbVisCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInOut,
    );
  }

  void _listenConnectivity() {
    Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      final online = results.any((r) => r != ConnectivityResult.none);
      if (!online) _forceCloseChat();
      setState(() => _isOnline = online);
    });
    Connectivity().checkConnectivity().then((results) {
      if (!mounted) return;
      setState(
        () => _isOnline = results.any((r) => r != ConnectivityResult.none),
      );
    });
  }

  @override
  void dispose() {
    if (_activeBubbleState == this) _activeBubbleState = null;
    _slideCtrl.dispose();
    _bubbleSpawnCtrl.dispose();
    _posCtrl.dispose();
    _panelCtrl.dispose();
    _exitCtrl.dispose();
    _bubbleEnterCtrl.dispose();
    _kbVisCtrl.dispose();
    super.dispose();
  }

  void _initPosition(Size screen) {
    if (!_posInit) {
      _left = screen.width - _bubbleSize - _margin;
      _top = screen.height * 0.44;
      _posInit = true;
    }
  }

  void _animateTo(
    double targetLeft,
    double targetTop, {
    Duration dur = const Duration(milliseconds: 320),
  }) {
    _posCtrl.duration = dur;
    _posCtrl.stop();
    _posLeftAnim = Tween<double>(
      begin: _left,
      end: targetLeft,
    ).animate(CurvedAnimation(parent: _posCtrl, curve: Curves.easeOutCubic));
    _posTopAnim = Tween<double>(
      begin: _top,
      end: targetTop,
    ).animate(CurvedAnimation(parent: _posCtrl, curve: Curves.easeOutCubic));
    _posCtrl.forward(from: 0);
  }

  void _snapToSide(Size screen) {
    final mid = _left + _bubbleSize / 2;
    final target = mid < screen.width / 2
        ? _margin
        : screen.width - _bubbleSize - _margin;
    _animateTo(target, _top);
  }

  _PanelGeometry _panelGeometry(Size screen) {
    final topSafe = MediaQuery.of(context).padding.top + 8;
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    final panelW = min(screen.width - 32.0, 400.0);
    final availH = screen.height - keyboardH - topSafe - 16;
    final maxH = (keyboardH > 0 ? availH - 8 : availH).clamp(
      200.0,
      double.infinity,
    );
    final panelH = min(min(screen.height * 0.72, 520.0), maxH);
    final panelLeft = (screen.width - panelW) / 2;
    final panelTop = (topSafe + (availH - panelH) / 2).clamp(
      topSafe,
      screen.height - panelH - 8,
    );
    return _PanelGeometry(
      left: panelLeft,
      top: panelTop,
      width: panelW,
      height: panelH,
    );
  }

  Offset _bubbleCorner(_PanelGeometry pg) =>
      Offset(pg.left - _bubbleSize / 2 + 30, pg.top - _bubbleSize / 2 - 35);

  void _openChat() {
    _savedLeft = _left;
    _savedTop = _top;

    final pg = _panelGeometry(_screen!);
    final corner = _bubbleCorner(pg);

    _bubbleEnterCtrl.stop();
    _bubbleEnterLeftAnim = Tween<double>(begin: _left, end: corner.dx).animate(
      CurvedAnimation(parent: _bubbleEnterCtrl, curve: Curves.easeOutCubic),
    );
    _bubbleEnterTopAnim = Tween<double>(begin: _top, end: corner.dy).animate(
      CurvedAnimation(parent: _bubbleEnterCtrl, curve: Curves.easeOutCubic),
    );

    _kbVisCtrl.value = 1.0;
    _kbIsOpen = false;

    setState(() {
      _chatOpen = true;
      _hasUnread = false;
      _bubbleMoving = true;
      _animatedBubbleLeft = _left;
      _animatedBubbleTop = _top;
    });

    _bubbleEnterCtrl.forward(from: 0);
    _panelCtrl.forward(from: 0);
  }

  void _closeChatAnimated() {
    if (_screen == null) return;

    _kbIsOpen = false;

    _kbVisCtrl.animateTo(
      1.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );

    final pg = _panelGeometry(_screen!);
    final corner = _bubbleCorner(pg);

    _bubbleEnterCtrl.stop();
    _bubbleEnterLeftAnim =
        Tween<double>(begin: corner.dx, end: _savedLeft ?? _left).animate(
          CurvedAnimation(
            parent: _bubbleEnterCtrl,
            curve: Curves.easeInOutCubic,
          ),
        );
    _bubbleEnterTopAnim =
        Tween<double>(begin: corner.dy, end: _savedTop ?? _top).animate(
          CurvedAnimation(
            parent: _bubbleEnterCtrl,
            curve: Curves.easeInOutCubic,
          ),
        );

    setState(() {
      _bubbleMoving = true;
      _animatedBubbleLeft = corner.dx;
      _animatedBubbleTop = corner.dy;
    });

    _bubbleEnterCtrl.forward(from: 0);
    _panelCtrl.reverse().then((_) {
      if (!mounted) return;
      if (_savedLeft != null && _savedTop != null) {
        _left = _savedLeft!;
        _top = _savedTop!;
      }
      setState(() => _chatOpen = false);
    });
  }

  void _forceCloseChat() {
    if (!mounted) return;

    _kbIsOpen = false;
    _panelCtrl.reset();
    _bubbleEnterCtrl.reset();
    _kbVisCtrl.value = 1.0;
    setState(() {
      _chatOpen = false;
      _bubbleMoving = false;
    });
    if (_savedLeft != null && _savedTop != null) {
      _left = _savedLeft!;
      _top = _savedTop!;
    }
  }

  void _onAgentMessage() {
    if (!_chatOpen && mounted) setState(() => _hasUnread = true);
  }

  bool _checkDelete(Size screen) {
    final bx = _left + _bubbleSize / 2;
    final by = _top + _bubbleSize / 2;
    final dx = bx - screen.width / 2;
    final dy = by - (screen.height - 100);
    return (dx * dx + dy * dy) < (55.0 * 55.0);
  }

  void _onPanStart(DragStartDetails _) {
    if (_chatOpen) return;
    _posCtrl.stop();
    setState(() => _isDragging = true);
  }

  void _onPanUpdate(DragUpdateDetails d, Size screen) {
    if (!_isDragging) return;
    setState(() {
      _left = (_left + d.delta.dx).clamp(
        _margin,
        screen.width - _bubbleSize - _margin,
      );
      _top = (_top + d.delta.dy).clamp(
        _margin,
        screen.height - _bubbleSize - _margin * 6,
      );
      _isOverDelete = _checkDelete(screen);
    });
  }

  void _onPanEnd(DragEndDetails _, Size screen) {
    if (!_isDragging) return;
    if (_isOverDelete) {
      setState(() {
        _isDragging = false;
        _isOverDelete = false;
      });
      _panelCtrl.reset();
      setState(() => _chatOpen = false);
      _bubbleSpawnCtrl.reverse().then((_) => widget.onDismiss());
      return;
    }
    setState(() {
      _isDragging = false;
      _isOverDelete = false;
    });
    _snapToSide(screen);
  }

  bool get _isOnLeft => _left < (_screen?.width ?? 400) / 2;

  @override
  Widget build(BuildContext context) {
    if (!_isOnline) return const SizedBox.shrink();

    _screen = MediaQuery.of(context).size;
    final screen = _screen!;
    _initPosition(screen);

    final pg = _panelGeometry(screen);
    final corner = _bubbleCorner(pg);

    if (_chatOpen && !_bubbleMoving) {
      _animatedBubbleLeft = corner.dx;
      _animatedBubbleTop = corner.dy;
    }

    final double bubbleLeft;
    final double bubbleTop;
    if (_chatOpen || _bubbleMoving) {
      bubbleLeft = _animatedBubbleLeft;
      bubbleTop = _animatedBubbleTop;
    } else {
      bubbleLeft = _left;
      bubbleTop = _top;
    }

    return Stack(
      children: [
        // ── 1. Backdrop ───────────────────────────────────────────────
        if (_chatOpen || _panelCtrl.isAnimating)
          Positioned.fill(
            child: FadeTransition(
              opacity: _panelFade,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeChatAnimated,
                child: const ColoredBox(color: Color(0x61000000)),
              ),
            ),
          ),

        // ── 2. Panel ──────────────────────────────────────────────────
        if (_chatOpen || _panelCtrl.isAnimating)
          Positioned(
            left: pg.left,
            top: pg.top,
            child: AnimatedBuilder(
              animation: _panelCtrl,
              builder: (_, child) => Opacity(
                opacity: _panelFade.value.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: _panelScale.value,
                  alignment: Alignment.center,
                  child: child,
                ),
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: SizedBox(
                  width: pg.width,
                  height: pg.height,
                  child: HomeChatPanelCard(
                    panelW: pg.width,
                    panelH: pg.height,
                    onAgentMessage: _onAgentMessage,
                  ),
                ),
              ),
            ),
          ),

        // ── 3. Delete zone ────────────────────────────────────────────
        Positioned(
          bottom: 88,
          left: 0,
          right: 0,
          child: AnimatedOpacity(
            opacity: _isDragging ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 180),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: _isOverDelete ? _deleteHover : _deleteNormal,
                height: _isOverDelete ? _deleteHover : _deleteNormal,
                decoration: BoxDecoration(
                  color: _isOverDelete
                      ? Colors.red
                      : Colors.red.withValues(alpha: 0.75),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.delete_rounded,
                  color: Colors.white,
                  size: _isOverDelete ? 26 : 22,
                ),
              ),
            ),
          ),
        ),

        // ── 4. Bubble ─────────────────────────────────────────────────
        Positioned(
          left: bubbleLeft,
          top: bubbleTop,
          child: AnimatedBuilder(
            animation: Listenable.merge([_bubbleSpawnCtrl, _exitCtrl]),
            builder: (_, child) => Opacity(
              opacity: (_bubbleSpawnOpacity.value * _exitOpacity.value).clamp(
                0.0,
                1.0,
              ),
              child: Transform.scale(
                scale: (_bubbleSpawnScale.value * _exitScale.value).clamp(
                  0.0,
                  1.0,
                ),
                alignment: Alignment.center,
                child: child,
              ),
            ),
            child: SlideTransition(
              position: _slideAnim,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: _chatOpen ? null : _onPanStart,
                onPanUpdate: _chatOpen ? null : (d) => _onPanUpdate(d, screen),
                onPanEnd: _chatOpen ? null : (d) => _onPanEnd(d, screen),
                onTap: () => _chatOpen ? _closeChatAnimated() : _openChat(),
                // ── Keyboard visibility wrapper ──────────────────────
                // Opacity fades independently from slide so it feels
                // lighter. Spring overshoot (easeOutBack) on entrance,
                // smooth acceleration (easeInCubic) on exit.
                child: AnimatedBuilder(
                  animation: _kbVisCtrl,
                  builder: (_, child) {
                    final progress = _chatOpen ? _kbVisCtrl.value : 1.0;

                    // Move UP while fading
                    final translateY = -(1.0 - progress) * 12;

                    // Fade DURING movement
                    final opacity = progress;

                    // Tiny shrink for softness
                    final scale = 0.94 + (progress * 0.06);

                    return Opacity(
                      opacity: opacity.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, translateY),
                        child: Transform.scale(
                          scale: scale,
                          alignment: Alignment.center,
                          child: child,
                        ),
                      ),
                    );
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: _isOverDelete ? _bubbleSize * 1.15 : _bubbleSize,
                        height: _isOverDelete
                            ? _bubbleSize * 1.15
                            : _bubbleSize,
                        decoration: BoxDecoration(
                          color: _isOverDelete
                              ? Colors.red
                              : AppColors.primaryBlue,
                          shape: BoxShape.circle,
                          border: _chatOpen
                              ? Border.all(color: Colors.white, width: 2.5)
                              : null,
                          boxShadow: [
                            BoxShadow(
                              color:
                                  (_isOverDelete
                                          ? Colors.red
                                          : AppColors.primaryBlue)
                                      .withValues(alpha: 0.28),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Image.asset(
                            'assets/images/customer.png',
                            width: _bubbleSize * 0.50,
                            height: _bubbleSize * 0.50,
                            color: Colors.white,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.support_agent_rounded,
                                  color: Colors.white,
                                  size: _bubbleSize * 0.50,
                                ),
                          ),
                        ),
                      ),

                      Positioned(
                        bottom: -_dotSize / 2 + _bubbleSize * 0.15,
                        right: -_dotSize / 2 + _bubbleSize * 0.15,
                        child: const ChatOnlineDot(),
                      ),

                      if (_hasUnread && !_chatOpen)
                        Positioned(
                          top: -4,
                          right: _isOnLeft ? null : -4,
                          left: _isOnLeft ? -4 : null,
                          child: const ChatUnreadBadge(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PanelGeometry {
  final double left, top, width, height;
  const _PanelGeometry({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}
