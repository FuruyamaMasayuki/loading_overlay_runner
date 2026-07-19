import 'dart:async';

import 'package:flutter/foundation.dart';

import 'active_task_info.dart';
import 'config.dart';
import 'events.dart';
import 'handle.dart';
import 'task_result.dart';

class _LoadingHandleImpl implements LoadingHandle {
  _LoadingHandleImpl(this._id, this._release);

  final int _id;
  final void Function(int id) _release;
  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _release(_id);
  }
}

/// Owns all loading-overlay state: which tasks are active, whether the
/// overlay is showing, and the event stream.
///
/// Framework-agnostic — nothing here depends on [BuildContext] or [Overlay],
/// which is what lets `LoadingOverlayRunnerHost` render it and Riverpod
/// providers observe it without either one owning the state.
///
/// The single source of truth is [_tasks] plus [_sessionPins]. Every other
/// piece of state (`isShowing`, `activeTasks`) is derived from them, so they
/// can never drift out of sync with each other.
class LoadingOverlayRunnerController {
  LoadingOverlayRunnerController({LoadingOverlayRunnerConfig? defaultConfig})
    : _defaultConfig = defaultConfig ?? const LoadingOverlayRunnerConfig();

  LoadingOverlayRunnerConfig _defaultConfig;

  /// Replaces the fallback config used when a `show`/`run`/`runAll` call
  /// doesn't pass its own. Does not affect the session already in progress:
  /// the session resolved and captured its config (per-call or the default
  /// at that moment) when it opened.
  void updateDefaultConfig(LoadingOverlayRunnerConfig config) {
    _defaultConfig = config;
  }

  final Map<int, ActiveTaskInfo> _tasks = <int, ActiveTaskInfo>{};
  int _nextId = 0;

  /// Session pins held by in-progress `runAll` batches. While any pin is
  /// held the overlay must not hide, even at the instant [_tasks] is empty —
  /// which happens between two tasks of a sequential batch. Without this,
  /// a sequential `runAll` with `minDisplayDuration: zero` would hide and
  /// re-show the overlay between every task (flicker, plus a spurious
  /// OverlayShown/OverlayHidden pair per task), breaking the documented
  /// "single display session per batch" contract.
  int _sessionPins = 0;

  /// Bumped by [forceClear]. A `runAll` batch snapshots this at start; a
  /// mismatch later means the user dismissed the session mid-batch, so the
  /// batch must not release a pin it no longer holds (forceClear zeroed
  /// them) and must run its remaining tasks without overlay bookkeeping —
  /// reopening the overlay right after an explicit dismissal is the one
  /// thing a dismissal must never do.
  int _dismissEpoch = 0;

  /// Bumped on every task start and every hide decision. A delayed hide
  /// (from `minDisplayDuration`) only takes effect if the generation it
  /// captured is still current, which is what stops a stale hide from
  /// closing an overlay that a later `show()` reopened while it waited.
  int _generation = 0;

  LoadingOverlayRunnerConfig? _sessionConfig;

  /// When the current display session became visible. Basis for
  /// [LoadingOverlayRunnerConfig.minDisplayDuration]: the guarantee is
  /// "visible at least this long since it appeared", so the delayed hide
  /// waits only the *remaining* time, not the full duration after the last
  /// task finishes.
  DateTime? _shownAt;

  final ValueNotifier<bool> _isShowing = ValueNotifier<bool>(false);
  final ValueNotifier<List<ActiveTaskInfo>> _activeTasks =
      ValueNotifier<List<ActiveTaskInfo>>(const <ActiveTaskInfo>[]);

  final StreamController<LoadingOverlayRunnerEvent> _events =
      StreamController<LoadingOverlayRunnerEvent>.broadcast();

  /// Whether the overlay is currently visible (including the
  /// `minDisplayDuration` grace period after the last task finished).
  ValueListenable<bool> get isShowingListenable => _isShowing;

  bool get isShowing => _isShowing.value;

  /// Snapshot of every task currently keeping the overlay visible, oldest
  /// first.
  ValueListenable<List<ActiveTaskInfo>> get activeTasksListenable =>
      _activeTasks;

  List<ActiveTaskInfo> get activeTasks => _activeTasks.value;

  /// Broadcast stream of overlay lifecycle and task events. No replay
  /// buffer: subscribe before events occur to observe them.
  Stream<LoadingOverlayRunnerEvent> get events => _events.stream;

  /// The config in effect for the current display session — whichever
  /// `show`/`run`/`runAll` call started it — or the controller's default
  /// when nothing is showing.
  LoadingOverlayRunnerConfig get effectiveConfig =>
      _sessionConfig ?? _defaultConfig;

  /// Starts a manually-managed loading request. Dispose the returned handle
  /// when the work it represents finishes.
  LoadingHandle show({LoadingOverlayRunnerConfig? config, String? label}) {
    final id = _startTask(
      config: config,
      label: label,
      source: ActiveTaskSource.manual,
    );
    return _LoadingHandleImpl(id, (id) => _finishTask(id, succeeded: true));
  }

  /// Runs [future] while a task is active, guaranteeing the task finishes
  /// (successfully or not) even if [future] throws.
  Future<T> run<T>(
    Future<T> Function() future, {
    LoadingOverlayRunnerConfig? config,
    String? label,
  }) async {
    final id = _startTask(
      config: config,
      label: label,
      source: ActiveTaskSource.run,
    );
    try {
      final result = await future();
      _finishTask(id, succeeded: true);
      return result;
    } catch (_) {
      _finishTask(id, succeeded: false);
      rethrow;
    }
  }

  /// Runs every task in [tasks], either concurrently or one at a time, and
  /// returns one [TaskResult] per task, in input order.
  ///
  /// Each task is registered as its own entry in [activeTasks] (so, e.g.,
  /// five parallel tasks show up as five entries at once), but they all
  /// share a single overlay display session.
  Future<List<TaskResult<T>>> runAll<T>(
    List<LoadingTask<T>> tasks, {
    ExecutionMode mode = ExecutionMode.parallel,
    bool stopOnError = false,
    LoadingOverlayRunnerConfig? config,
  }) async {
    if (tasks.isEmpty) return <TaskResult<T>>[];

    final epoch = _dismissEpoch;
    _acquireSessionPin(config);

    Future<TaskResult<T>> runOne(LoadingTask<T> task) async {
      if (_dismissEpoch != epoch) {
        // The user dismissed this batch's session (forceClear). Remaining
        // tasks still run and produce results, but without overlay
        // bookkeeping — no activeTasks entry, no TaskStarted/TaskFinished.
        try {
          return TaskSuccess<T>(await task.future());
        } catch (error, stackTrace) {
          return TaskFailure<T>(error, stackTrace);
        }
      }
      final id = _startTask(
        config: config,
        label: task.label,
        source: ActiveTaskSource.runAll,
      );
      try {
        final value = await task.future();
        _finishTask(id, succeeded: true);
        return TaskSuccess<T>(value);
      } catch (error, stackTrace) {
        _finishTask(id, succeeded: false);
        return TaskFailure<T>(error, stackTrace);
      }
    }

    try {
      if (mode == ExecutionMode.parallel) {
        // Future.wait preserves input order in its result list regardless
        // of completion order.
        return await Future.wait(tasks.map(runOne));
      }

      final results = <TaskResult<T>>[];
      var aborted = false;
      for (final task in tasks) {
        if (aborted) {
          results.add(const TaskSkipped());
          continue;
        }
        final result = await runOne(task);
        results.add(result);
        if (stopOnError && result is TaskFailure<T>) {
          aborted = true;
        }
      }
      return results;
    } finally {
      // Skip the release if forceClear already zeroed the pins mid-batch —
      // releasing a pin this batch no longer holds would underflow the
      // count and could hide a session some *other* caller opened since.
      if (_dismissEpoch == epoch) {
        _releaseSessionPin();
      }
    }
  }

  /// Forcibly clears every active task and hides the overlay immediately,
  /// e.g. from a dismissible barrier tap. Tasks already in flight (from
  /// `run`/`runAll`) keep running to completion in the background; only
  /// their overlay bookkeeping is discarded. The not-yet-started remainder
  /// of a dismissed `runAll` batch also still runs and produces results,
  /// but without reopening the overlay — an explicit dismissal must stick
  /// for the whole batch.
  void forceClear() {
    // The overlay can be visible with zero tasks and zero pins: the
    // minDisplayDuration grace period after the last task finished. A
    // dismissible tap/back during that window must still close it, so
    // "visible" alone is enough to proceed.
    if (_tasks.isEmpty && _sessionPins == 0 && !_isShowing.value) return;
    final finished = _tasks.values.toList(growable: false);
    _tasks.clear();
    _publishTasks();
    for (final info in finished) {
      _events.add(
        TaskFinished(
          info,
          elapsed: DateTime.now().difference(info.startedAt),
          succeeded: false,
        ),
      );
    }
    _generation++;
    // Zero the pins and advance the epoch: in-flight runAll batches detect
    // the epoch change, skip their own (now already-released) pin release,
    // and stop registering overlay bookkeeping for their remaining tasks.
    // A fresh, unrelated show()/run() after this starts a brand-new session
    // and displays normally.
    _sessionPins = 0;
    _dismissEpoch++;
    _sessionConfig = null;
    _shownAt = null;
    if (_isShowing.value) {
      _isShowing.value = false;
      _events.add(const OverlayHidden());
    }
  }

  /// Called by the host when a back-navigation attempt is swallowed because
  /// the overlay is showing.
  void notifyBackButtonBlocked() {
    _events.add(const BackButtonBlocked());
    if (effectiveConfig.dismissible) forceClear();
  }

  /// Called by the host when the barrier is tapped.
  void notifyBarrierTapped() {
    _events.add(const BarrierTapped());
    if (effectiveConfig.dismissible) forceClear();
  }

  /// Opens (or joins) a display session on behalf of a `runAll` batch,
  /// keeping the overlay up across the batch's task boundaries.
  void _acquireSessionPin(LoadingOverlayRunnerConfig? config) {
    final wasIdle = _tasks.isEmpty && _sessionPins == 0;
    _sessionPins++;
    _generation++; // invalidates any delayed hide currently in flight
    if (wasIdle) {
      // Resolve against the default NOW, not lazily in effectiveConfig:
      // a session opened without a per-call config must not change its
      // appearance mid-flight if updateDefaultConfig is called while it's
      // showing — "captured when the session opened" has to be literal.
      _sessionConfig = config ?? _defaultConfig;
      _shownAt = DateTime.now();
      if (!_isShowing.value) {
        _isShowing.value = true;
        _events.add(const OverlayShown());
      }
    }
  }

  void _releaseSessionPin() {
    assert(_sessionPins > 0, 'pin released more often than acquired');
    if (_sessionPins > 0) _sessionPins--;
    _scheduleHideIfEmpty();
  }

  int _startTask({
    LoadingOverlayRunnerConfig? config,
    String? label,
    required ActiveTaskSource source,
  }) {
    final id = _nextId++;
    // "Idle" (no tasks AND no batch pins) marks a new display session —
    // even if the overlay is still visible from the previous session's
    // minDisplayDuration grace period ("closing"). The new session adopts
    // the new config and restarts the min-display clock. A task starting
    // under an active pin joins the pin's session instead (first-wins).
    final wasIdle = _tasks.isEmpty && _sessionPins == 0;
    if (wasIdle) {
      // Resolved eagerly for the same reason as in _acquireSessionPin.
      _sessionConfig = config ?? _defaultConfig;
      _shownAt = DateTime.now();
    }
    final info = ActiveTaskInfo(
      id: id,
      label: label ?? 'task#$id',
      startedAt: DateTime.now(),
      source: source,
    );
    _tasks[id] = info;
    _generation++; // invalidates any delayed hide currently in flight
    _publishTasks();
    if (wasIdle && !_isShowing.value) {
      // Guarded on the actual transition: reopening during the closing
      // grace period keeps isShowing true throughout, and must not emit a
      // second OverlayShown with no OverlayHidden in between.
      _isShowing.value = true;
      _events.add(const OverlayShown());
    }
    _events.add(TaskStarted(info));
    return id;
  }

  void _finishTask(int id, {required bool succeeded}) {
    final info = _tasks.remove(id);
    if (info == null) return; // already released (idempotent dispose, or forceClear beat us to it)
    _publishTasks();
    _events.add(
      TaskFinished(
        info,
        elapsed: DateTime.now().difference(info.startedAt),
        succeeded: succeeded,
      ),
    );
    _scheduleHideIfEmpty();
  }

  void _scheduleHideIfEmpty() {
    if (_tasks.isNotEmpty || _sessionPins > 0) return;
    final gen = ++_generation;
    var remaining = Duration.zero;
    final minDisplay = effectiveConfig.minDisplayDuration;
    if (minDisplay > Duration.zero && _shownAt != null) {
      remaining = minDisplay - DateTime.now().difference(_shownAt!);
    }
    if (remaining <= Duration.zero) {
      _hideNow(gen);
      return;
    }
    Future<void>.delayed(remaining, () => _hideNow(gen));
  }

  void _hideNow(int gen) {
    if (_disposed) return; // a pending delayed hide may outlive dispose()
    if (gen != _generation) return; // superseded by a later show()/task start
    // The generation check already covers these (every task start and pin
    // acquisition bumps it), but re-checking the actual state is free and
    // keeps a future refactor of the generation logic from turning this
    // into a hide-while-busy.
    if (_tasks.isNotEmpty || _sessionPins > 0) return;
    if (!_isShowing.value) return;
    _isShowing.value = false;
    _sessionConfig = null;
    _shownAt = null;
    _events.add(const OverlayHidden());
  }

  void _publishTasks() {
    _activeTasks.value = List<ActiveTaskInfo>.unmodifiable(_tasks.values);
  }

  bool _disposed = false;

  /// Releases all resources. Only meant for tests that create throwaway
  /// controllers; the app-wide controller lives for the app's lifetime.
  @visibleForTesting
  void dispose() {
    _disposed = true; // pending delayed hides become no-ops (see _hideNow)
    _isShowing.dispose();
    _activeTasks.dispose();
    unawaited(_events.close());
  }
}
