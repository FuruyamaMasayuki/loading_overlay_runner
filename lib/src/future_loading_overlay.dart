import 'package:flutter/widgets.dart';

import 'active_task_info.dart';
import 'back_button_guard.dart';
import 'config.dart';
import 'controller.dart';
import 'handle.dart';
import 'host.dart';
import 'task_result.dart';

/// Static facade over a single app-wide [FutureLoadingOverlayController].
///
/// Wire it up once, in `MaterialApp`/`CupertinoApp`:
/// ```dart
/// MaterialApp(builder: FutureLoadingOverlay.init());
/// ```
/// and call [show], [run], or [runAll] from anywhere in the app — no
/// [BuildContext] required, so it works the same from a widget, a service
/// class, or a background callback.
abstract final class FutureLoadingOverlay {
  /// The controller backing every static method here. Exposed for advanced
  /// use (e.g. wiring your own state-management bridge); most apps never
  /// need to touch it directly — use the Riverpod providers in
  /// `future_loading_overlay/riverpod.dart` instead.
  ///
  /// Read-only from outside this class. [BackButtonGuard] captures whichever
  /// controller instance is current at construction time — if this field
  /// could be reassigned externally, the guard would silently keep watching
  /// the orphaned old instance while the rest of the app moved on to a new
  /// one. [init] and [resetForTest] are the only two places allowed to swap
  /// it, and both keep the guard in sync when they do.
  static FutureLoadingOverlayController get controller => _controller;
  static FutureLoadingOverlayController _controller =
      FutureLoadingOverlayController();

  static BackButtonGuard? _guard;

  /// Returns a `MaterialApp`/`CupertinoApp` `builder` that wires the overlay
  /// into the app's widget tree.
  ///
  /// The first call registers the [BackButtonGuard] that blocks back
  /// navigation while the overlay is showing. That has to happen here —
  /// synchronously, before `runApp` builds any widget tree — rather than in
  /// a widget's `initState`, because it's what lets the guard win the race
  /// against `MaterialApp`'s own back-navigation observer (see
  /// [BackButtonGuard]'s doc comment).
  ///
  /// Safe to call again: `builder:` arguments are re-evaluated whenever the
  /// widget constructing `MaterialApp` rebuilds (theme/locale change, parent
  /// setState), so this method must be — and is — idempotent. Repeat calls
  /// keep the existing [controller] (in-flight tasks survive) and, crucially,
  /// keep the existing guard: disposing and re-registering it would append
  /// it *after* `MaterialApp`'s observer in the binding's observer list,
  /// silently breaking back-blocking from that rebuild on. [defaultConfig],
  /// when supplied, is applied to the existing controller as its new
  /// fallback config.
  static TransitionBuilder init({FutureLoadingOverlayConfig? defaultConfig}) {
    if (defaultConfig != null) {
      _controller.updateDefaultConfig(defaultConfig);
    }
    WidgetsFlutterBinding.ensureInitialized();
    _guard ??= BackButtonGuard(_controller);
    return (context, child) =>
        FutureLoadingOverlayHost(controller: _controller, child: child);
  }

  /// Starts a manually-managed loading request. Dispose the returned handle
  /// when the work it represents finishes.
  static LoadingHandle show({
    FutureLoadingOverlayConfig? config,
    String? label,
  }) {
    return _controller.show(config: config, label: label);
  }

  /// Shows the overlay for the duration of [future]. Hides it once [future]
  /// completes, whether it succeeds or throws (the error is rethrown
  /// unchanged).
  static Future<T> run<T>(
    Future<T> Function() future, {
    FutureLoadingOverlayConfig? config,
    String? label,
  }) {
    return _controller.run(future, config: config, label: label);
  }

  /// Runs every future in [futures] under a single overlay display session,
  /// either concurrently ([ExecutionMode.parallel], the default) or one at a
  /// time ([ExecutionMode.sequential]).
  ///
  /// Returns one [TaskResult] per future, in the same order as [futures] —
  /// one task failing never throws out of this call or skips the others
  /// (unless `stopOnError` is set for sequential mode); inspect each
  /// [TaskResult] to see what happened.
  ///
  /// [labels], if supplied, must be the same length as [futures] and is used
  /// for [ActiveTaskInfo.label]; otherwise tasks are labeled `task#0`,
  /// `task#1`, etc. For per-task labels without a separate list, use
  /// [runAllTasks] with [LoadingTask] instead.
  static Future<List<TaskResult<T>>> runAll<T>(
    List<Future<T> Function()> futures, {
    List<String>? labels,
    ExecutionMode mode = ExecutionMode.parallel,
    bool stopOnError = false,
    FutureLoadingOverlayConfig? config,
  }) {
    assert(
      labels == null || labels.length == futures.length,
      'labels must be the same length as futures',
    );
    final tasks = <LoadingTask<T>>[
      for (var i = 0; i < futures.length; i++)
        LoadingTask<T>(labels?[i] ?? 'task#$i', futures[i]),
    ];
    return _controller.runAll<T>(
      tasks,
      mode: mode,
      stopOnError: stopOnError,
      config: config,
    );
  }

  /// Like [runAll], but takes pre-labeled [LoadingTask]s.
  static Future<List<TaskResult<T>>> runAllTasks<T>(
    List<LoadingTask<T>> tasks, {
    ExecutionMode mode = ExecutionMode.parallel,
    bool stopOnError = false,
    FutureLoadingOverlayConfig? config,
  }) {
    return _controller.runAll<T>(
      tasks,
      mode: mode,
      stopOnError: stopOnError,
      config: config,
    );
  }

  /// Replaces [controller] with a fresh instance and drops any registered
  /// [BackButtonGuard]. Only meant for test isolation between test cases;
  /// app code should never need this.
  @visibleForTesting
  static void resetForTest({FutureLoadingOverlayConfig? defaultConfig}) {
    _guard?.dispose();
    _guard = null;
    _controller = FutureLoadingOverlayController(defaultConfig: defaultConfig);
  }
}
