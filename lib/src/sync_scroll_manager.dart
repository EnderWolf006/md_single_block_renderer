import 'package:flutter/widgets.dart';

/// Manages synchronized horizontal scrolling across multiple code block
/// segments that belong to the same logical code block group.
///
/// Usage pattern:
///   1. Each _HighlightedCodeBlock passes its groupId when building.
///   2. On initState it calls: SyncScrollManager.instance.register(groupId, controller)
///   3. On dispose it calls: unregister.
///   4. The first added controller in a group seeds the cached offset (if any).
///   5. When any controller scrolls horizontally the manager propagates the
///      offset to the other controllers in the same group via jumpTo to avoid
///      animation feedback loops.
///
/// Reentrancy protection prevents recursive onScroll notifications.
///
/// NOTE: This manager is intentionally lightweight and keeps only lastOffset
/// per group in memory. If you need cross-route persistence you can expose
/// serialization hooks or plug PageStorage differently.
class SyncScrollManager {
  SyncScrollManager._();
  static final SyncScrollManager instance = SyncScrollManager._();

  /// Holds data per group.
  final Map<String, _GroupSync> _groups = {};

  /// Minimum delta (in logical pixels) before we propagate. Helps reduce
  /// noisy micro updates.
  static const double _propagationThreshold = 0.5; // half pixel threshold

  void register(String groupId, ScrollController controller) {
    final group = _groups.putIfAbsent(groupId, () => _GroupSync(groupId));
    group.add(controller);
  }

  void unregister(String groupId, ScrollController controller) {
    final group = _groups[groupId];
    if (group == null) return;
    group.remove(controller);
    if (group.isEmpty) {
      _groups.remove(groupId);
    }
  }

  /// Get the last cached horizontal offset for a group (if any) so newly
  /// created controllers can immediately jump to the correct position.
  double? cachedOffset(String groupId) => _groups[groupId]?.lastOffset;
}

class _GroupSync {
  final String groupId;
  final Set<ScrollController> _controllers = {};
  bool _broadcasting = false; // reentrancy guard
  double lastOffset = 0.0;

  _GroupSync(this.groupId);

  bool get isEmpty => _controllers.isEmpty;

  void add(ScrollController controller) {
    _controllers.add(controller);

    // If we already have a cached offset (from a previous controller) apply it.
    if (lastOffset > 0 && controller.hasClients) {
      controller.jumpTo(lastOffset);
    }

    // Attach listener if not already present.
    controller.addListener(() {
      if (_broadcasting) return; // Avoid feedback
      if (!controller.hasClients) return;

      final offset = controller.offset;
      // Only propagate if significant change.
      if ((offset - lastOffset).abs() < SyncScrollManager._propagationThreshold) {
        return;
      }
      lastOffset = offset;
      _broadcasting = true;
      try {
        for (final other in _controllers) {
          if (identical(other, controller)) continue;
          if (!other.hasClients) continue;
          // Keep in range; clamp if necessary.
          final maxScroll = other.position.maxScrollExtent;
          final target = offset.clamp(0.0, maxScroll);
          if ((other.offset - target).abs() >= 0.1) {
            other.jumpTo(target);
          }
        }
      } finally {
        _broadcasting = false;
      }
    });
  }

  void remove(ScrollController controller) {
    _controllers.remove(controller);
  }
}
