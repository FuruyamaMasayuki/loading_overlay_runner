/// Returned by `FutureLoadingOverlay.show`. Call [dispose] when the work
/// this handle represents is done.
///
/// The overlay hides once every outstanding handle (and every task started
/// via `run`/`runAll`) has finished, subject to
/// `FutureLoadingOverlayConfig.minDisplayDuration`. Calling [dispose] more
/// than once is safe and a no-op after the first call.
abstract class LoadingHandle {
  /// Releases this handle's contribution to the overlay's visibility.
  void dispose();
}
