import 'package:flutter/widgets.dart';

/// Visual and behavioral configuration for the loading overlay.
///
/// When several tasks are active at once, the config from whichever call
/// started the overlay (transitioned it from empty to non-empty) wins;
/// configs passed by calls that join an already-visible overlay are ignored.
/// This keeps the overlay's appearance stable for the duration of a display
/// session instead of flickering between configs.
@immutable
class FutureLoadingOverlayConfig {
  const FutureLoadingOverlayConfig({
    this.indicator,
    this.background,
    this.minDisplayDuration = Duration.zero,
    this.dismissible = false,
  });

  /// The widget centered on screen while loading. Defaults to a
  /// [CircularProgressIndicator] when `null`.
  final Widget? indicator;

  /// The widget drawn full-screen behind [indicator]. Defaults to a
  /// translucent gray (`Color(0x33000000)`) when `null`.
  final Widget? background;

  /// The overlay stays visible at least this long after it starts, even if
  /// every active task finishes sooner. Prevents flicker on very fast
  /// requests.
  final Duration minDisplayDuration;

  /// When `true`, tapping the barrier or attempting to navigate back clears
  /// every active task and closes the overlay immediately (the underlying
  /// tasks keep running in the background; only the overlay is dismissed).
  ///
  /// Defaults to `false`: the overlay only closes once every active task
  /// finishes or its handle is disposed. Back navigation and swipe-to-pop
  /// gestures never reach the screen below while the overlay is showing.
  final bool dismissible;
}
