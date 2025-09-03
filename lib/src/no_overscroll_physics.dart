import 'package:flutter/widgets.dart';

/// A horizontal ScrollPhysics that clamps without any ballistic overscroll
/// or bounce. When the user drags past the edges it just stops immediately
/// (no spring / glow / ballistic animation).
class NoOverscrollPhysics extends ScrollPhysics {
  const NoOverscrollPhysics({ScrollPhysics? parent}) : super(parent: parent);

  @override
  NoOverscrollPhysics applyTo(ScrollPhysics? ancestor) {
    return NoOverscrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    // If attempting to go beyond min or max, disallow by returning delta.
    if (value < position.pixels && position.pixels <= position.minScrollExtent) {
      // Underscroll
      return value - position.pixels;
    }
    if (value > position.pixels && position.pixels >= position.maxScrollExtent) {
      // Overscroll
      return value - position.pixels;
    }
    if (value < position.minScrollExtent && position.minScrollExtent < position.pixels) {
      return value - position.minScrollExtent;
    }
    if (value > position.maxScrollExtent && position.pixels < position.maxScrollExtent) {
      return value - position.maxScrollExtent;
    }
    return 0.0; // Accept normal movement within bounds.
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) => true;

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    // If out of range, jump back immediately (no animation) by returning null after clamp.
    if (position.pixels < position.minScrollExtent ||
        position.pixels > position.maxScrollExtent) {
      return null; // framework will clamp
    }
    if (velocity.abs() < 10) {
      return null; // stop quickly, no ballistic continue
    }
    return ClampingScrollSimulation(
      position: position.pixels,
      velocity: velocity,
      tolerance: tolerance,
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}
