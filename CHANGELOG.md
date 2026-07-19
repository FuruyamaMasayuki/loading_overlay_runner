## 0.0.1

Initial release.

* Global, context-free `show`/`run`/`runAll`/`runAllTasks` API for a
  full-screen loading overlay, wired in once via
  `MaterialApp(builder: LoadingOverlayRunner.init())`.
* Ticket-based visibility tracking (`LoadingHandle`) instead of a raw
  counter, so stray extra disposes or exceptions can't leave the overlay
  stuck.
* Back button, predictive back, and iOS edge-swipe are blocked while the
  overlay is showing, without interfering with the app's own
  `Navigator`/router; opt-in `dismissible` config to allow closing early.
* Customizable `indicator`/`background` widgets, `minDisplayDuration`
  flicker guard, and config first-wins semantics for overlapping calls.
* `activeTasks` / `activeTasksListenable` / `events` for observing what's
  currently in flight.
* Bundled Riverpod providers (`package:loading_overlay_runner/riverpod.dart`).
* `init()` is idempotent — safe against `builder:` re-evaluation on
  `MaterialApp` rebuilds (keeps the controller and the back-button guard's
  observer priority).
* `minDisplayDuration` is measured from when the overlay appeared, not from
  when the last task finished.
* Reopening the overlay during a previous session's `minDisplayDuration`
  grace period correctly adopts the new session's config (indicator/
  background) and emits exactly one `OverlayShown`/`OverlayHidden` pair per
  session instead of a duplicate.
* `LoadingOverlayRunner.controller` is read-only from outside the package,
  so it can no longer be reassigned in a way that would decouple
  `BackButtonGuard` from the controller actually driving the overlay.
* Sequential `runAll` batches hold the overlay open across task boundaries
  (one display session per batch — no flicker or duplicate
  `OverlayShown`/`OverlayHidden` between tasks), and dismissing a
  dismissible batch mid-flight sticks: remaining tasks still run and return
  results, but never reopen the overlay.
* A dismissible barrier tap / back attempt during the `minDisplayDuration`
  grace period closes the overlay immediately instead of being ignored.
* A session opened without a per-call config captures the default config at
  open time, so `updateDefaultConfig` can no longer restyle an overlay
  that's already showing.
