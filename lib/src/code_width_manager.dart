import 'package:flutter/widgets.dart';

/// Manages per code group the maximum intrinsic single-line width so that all
/// code segments inside the same logical group can align to a unified width
/// (even if some individual segments don't cause horizontal scroll yet).
class CodeWidthManager {
  CodeWidthManager._();
  static final CodeWidthManager instance = CodeWidthManager._();

  final Map<String, double> _maxLineWidthByGroup = {};
  final Map<String, List<VoidCallback>> _groupListeners = {};

  double? getGroupWidth(String groupId) => _maxLineWidthByGroup[groupId];

  /// Register a listener that will be called when the group width changes
  void addGroupListener(String groupId, VoidCallback listener) {
    _groupListeners.putIfAbsent(groupId, () => []).add(listener);
  }

  /// Remove a listener for a specific group
  void removeGroupListener(String groupId, VoidCallback listener) {
    _groupListeners[groupId]?.remove(listener);
    if (_groupListeners[groupId]?.isEmpty == true) {
      _groupListeners.remove(groupId);
    }
  }

  /// Update the stored width; returns true if value changed (so caller can setState).
  /// Also notifies all listeners if the width changed.
  bool updateWidth(String groupId, double candidateWidth) {
    final current = _maxLineWidthByGroup[groupId];
    if (current == null || candidateWidth > current + 0.5) {
      // 0.5 tolerance
      _maxLineWidthByGroup[groupId] = candidateWidth;

      // Notify all listeners that the width has changed
      final listeners = _groupListeners[groupId];
      if (listeners != null) {
        for (final listener in List.from(listeners)) {
          listener();
        }
      }

      return true;
    }
    return false;
  }

  /// Force update the width even if it's smaller than current
  /// This is useful when recalculating the entire group
  void forceUpdateWidth(String groupId, double width) {
    final current = _maxLineWidthByGroup[groupId];
    if (current != width) {
      _maxLineWidthByGroup[groupId] = width;

      // Notify all listeners that the width has changed
      final listeners = _groupListeners[groupId];
      if (listeners != null) {
        for (final listener in List.from(listeners)) {
          listener();
        }
      }
    }
  }

  /// Clear the stored width and notify listeners
  void clearGroup(String groupId) {
    _maxLineWidthByGroup.remove(groupId);

    // Notify listeners that the group is cleared
    final listeners = _groupListeners[groupId];
    if (listeners != null) {
      for (final listener in List.from(listeners)) {
        listener();
      }
    }
    _groupListeners.remove(groupId);
  }

  /// Get all group IDs currently being tracked
  List<String> get groupIds => _maxLineWidthByGroup.keys.toList();

  /// Reset the width for a group to trigger recalculation
  void resetGroupWidth(String groupId) {
    _maxLineWidthByGroup.remove(groupId);

    // Notify listeners to trigger remeasurement
    final listeners = _groupListeners[groupId];
    if (listeners != null) {
      for (final listener in List.from(listeners)) {
        listener();
      }
    }
  }

  /// Recalculate the maximum width for a group by triggering all listeners
  /// This is useful when new content is added to any block in the group
  void recalculateGroupWidth(String groupId) {
    resetGroupWidth(groupId);
  }
}
