import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/overlay_exit.dart';

class DoubleBackExit extends StatefulWidget {
  final Widget child;

  const DoubleBackExit({required this.child});

  @override
  State<DoubleBackExit> createState() => _DoubleBackExitState();
}

class _DoubleBackExitState extends State<DoubleBackExit> {
  DateTime? lastBackPressed;

  void onPopInvoked(bool didPop) {
    final now = DateTime.now();

    if (lastBackPressed == null ||
        now.difference(lastBackPressed!) > Duration(seconds: 2)) {
      lastBackPressed = now;

      ExitOverlay.show(context, "Tap again to exit");
      return;
    }

    SystemNavigator.pop(); // exit app
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // prevents automatic pop
      onPopInvoked: onPopInvoked,
      child: widget.child,
    );
  }
}
