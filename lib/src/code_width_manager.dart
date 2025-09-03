import 'package:flutter/widgets.dart';

/// Manages per code group the maximum intrinsic single-line width so that all
/// code segments inside the same logical group can align to a unified width
/// (even if some individual segments don't cause horizontal scroll yet).
class CodeWidthManager {
  CodeWidthManager._();
  static final CodeWidthManager instance = CodeWidthManager._();

  final Map<String, double> _maxLineWidthByGroup = {};

  double? getGroupWidth(String groupId) => _maxLineWidthByGroup[groupId];

  /// Update the stored width; returns true if value changed (so caller can setState).
  bool updateWidth(String groupId, double candidateWidth) {
    final current = _maxLineWidthByGroup[groupId];
    if (current == null || candidateWidth > current + 0.5) {
      // 0.5 tolerance
      _maxLineWidthByGroup[groupId] = candidateWidth;
      return true;
    }
    return false;
  }

  void clearGroup(String groupId) => _maxLineWidthByGroup.remove(groupId);
}
