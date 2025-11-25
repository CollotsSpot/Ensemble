import 'package:flutter/material.dart';

class LayoutDebug extends ChangeNotifier {
  static final LayoutDebug _instance = LayoutDebug._internal();
  factory LayoutDebug() => _instance;
  LayoutDebug._internal();

  double logoPaddingLeft = 8.0;
  double logoPaddingTop = 8.0;
  double logoPaddingBottom = 8.0;
  double logoSize = 24.0;

  void update({
    double? left,
    double? top,
    double? bottom,
    double? size,
  }) {
    if (left != null) logoPaddingLeft = left;
    if (top != null) logoPaddingTop = top;
    if (bottom != null) logoPaddingBottom = bottom;
    if (size != null) logoSize = size;
    notifyListeners();
  }
}
