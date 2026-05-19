import 'package:flutter/material.dart';

final RouteObserver<ModalRoute<void>> homeRouteObserver =
    RouteObserver<ModalRoute<void>>();

enum VerifStatus { none, pending, verified }
