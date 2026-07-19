# API Reference

Full reference for every public symbol exported from
`package:future_loading_overlay/future_loading_overlay.dart` and
`package:future_loading_overlay/riverpod.dart`. For a task-oriented guide,
see [README.md](README.md).

## Contents

- [`FutureLoadingOverlay`](#futureloadingoverlay-static-facade)
- [`FutureLoadingOverlayConfig`](#futureloadingoverlayconfig)
- [`LoadingHandle`](#loadinghandle)
- [`LoadingTask<T>`](#loadingtaskt)
- [`ActiveTaskInfo`](#activetaskinfo)
- [`ActiveTaskSource`](#activetasksource)
- [`ExecutionMode`](#executionmode)
- [`TaskResult<T>` / `TaskSuccess<T>` / `TaskFailure<T>` / `TaskSkipped<T>`](#taskresultt)
- [`FutureLoadingOverlayEvent`](#futureloadingoverlayevent-and-subtypes)
- [`FutureLoadingOverlayController`](#futureloadingoverlaycontroller)
- [`FutureLoadingOverlayHost`](#futureloadingoverlayhost)
- [`BackButtonGuard`](#backbuttonguard)
- [Riverpod providers](#riverpod-providers)

---

## `FutureLoadingOverlay` (static facade)

The main entry point. All members are `static`; the class cannot be
instantiated.

### `FutureLoadingOverlay.controller`

```dart
static FutureLoadingOverlayController get controller
```

The single app-wide controller backing every other static method.
Read-only — only [`init`](#futureloadingoverlayinit) and `resetForTest` can
swap the underlying instance, which keeps [`BackButtonGuard`](#backbuttonguard)
(constructed with a specific controller instance) from ever ending up
watching an orphaned one. Exposed for advanced use (custom state-management
bridges); most apps only need the Riverpod providers or the
`events`/`isShowingListenable` getters on it directly.

### `FutureLoadingOverlay.init`

```dart
static TransitionBuilder init({FutureLoadingOverlayConfig? defaultConfig})
```

Returns a `builder` for `MaterialApp`/`CupertinoApp` that mounts the overlay
UI into the app's widget tree, and — on first call — registers the
[`BackButtonGuard`](#backbuttonguard) that blocks back navigation while the
overlay is showing.

- Use as the `builder:` argument.
- The first call must run **before** `runApp()` builds the widget tree —
  evaluating it as a constructor argument (as in the usual
  `MaterialApp(builder: FutureLoadingOverlay.init())` usage) already
  satisfies this.
- **Idempotent by design**: `builder:` arguments are re-evaluated every time
  the widget constructing `MaterialApp` rebuilds, so repeat calls keep the
  existing controller (in-flight tasks survive) and keep the existing
  guard's position in the binding's observer list (re-registering it would
  demote it behind `MaterialApp`'s own observer and silently break
  back-blocking).
- If `defaultConfig` is supplied, it is applied to the existing controller
  via [`updateDefaultConfig`](#futureloadingoverlaycontroller) as the
  fallback config for calls that don't pass their own.

### `FutureLoadingOverlay.show`

```dart
static LoadingHandle show({FutureLoadingOverlayConfig? config, String? label})
```

Starts a manually-managed loading request and returns a handle. The overlay
shows immediately (or stays showing, if it already was). Dispose the handle
when the work it represents is done.

### `FutureLoadingOverlay.run`

```dart
static Future<T> run<T>(
  Future<T> Function() future, {
  FutureLoadingOverlayConfig? config,
  String? label,
})
```

Shows the overlay for the duration of `future`. Hides it once `future`
completes, whether it succeeds or throws — the error is rethrown unchanged.

### `FutureLoadingOverlay.runAll`

```dart
static Future<List<TaskResult<T>>> runAll<T>(
  List<Future<T> Function()> futures, {
  List<String>? labels,
  ExecutionMode mode = ExecutionMode.parallel,
  bool stopOnError = false,
  FutureLoadingOverlayConfig? config,
})
```

Runs every future in `futures` under a single overlay display session.
Returns one [`TaskResult`](#taskresultt) per future, in the same order as
`futures` — a failing task never throws out of this call or (in `parallel`
mode) affects the others.

- `labels`, if supplied, must be the same length as `futures`; otherwise
  tasks are labeled `task#0`, `task#1`, etc.
- `mode: ExecutionMode.parallel` (default): all futures start at once.
- `mode: ExecutionMode.sequential`: futures run one at a time, in order.
  `stopOnError: true` skips remaining tasks (as `TaskSkipped`) after the
  first failure; ignored in `parallel` mode.
- An empty `futures` list returns `[]` immediately without showing the
  overlay.

### `FutureLoadingOverlay.runAllTasks`

```dart
static Future<List<TaskResult<T>>> runAllTasks<T>(
  List<LoadingTask<T>> tasks, {
  ExecutionMode mode = ExecutionMode.parallel,
  bool stopOnError = false,
  FutureLoadingOverlayConfig? config,
})
```

Same as `runAll`, but takes pre-labeled [`LoadingTask`](#loadingtaskt)s
instead of a separate `labels` list — useful when labels are naturally
computed alongside each task.

### `FutureLoadingOverlay.resetForTest`

```dart
@visibleForTesting
static void resetForTest({FutureLoadingOverlayConfig? defaultConfig})
```

Replaces `controller` with a fresh instance and drops any registered
`BackButtonGuard`. Only meant for isolating test cases from each other; app
code should never call this.

---

## `FutureLoadingOverlayConfig`

```dart
class FutureLoadingOverlayConfig {
  const FutureLoadingOverlayConfig({
    this.indicator,
    this.background,
    this.minDisplayDuration = Duration.zero,
    this.dismissible = false,
  });

  final Widget? indicator;
  final Widget? background;
  final Duration minDisplayDuration;
  final bool dismissible;
}
```

| Field | Default | Description |
|---|---|---|
| `indicator` | `CircularProgressIndicator()` | Widget centered on screen while loading. |
| `background` | translucent gray, `Color(0x33000000)` | Widget drawn full-screen behind `indicator`. |
| `minDisplayDuration` | `Duration.zero` | Overlay stays visible at least this long after it starts, to avoid flicker on fast requests. |
| `dismissible` | `false` | When `true`, a barrier tap or back-navigation attempt clears every active task and closes the overlay immediately. In-flight `run`/`runAll` futures keep running in the background regardless. |

When several `show`/`run`/`runAll` calls overlap, the config from whichever
call transitioned the overlay from hidden to showing wins; configs from
calls that join an already-open session are ignored (first-wins). A fresh
session — after the overlay has fully closed — adopts whatever new config
is passed next.

---

## `LoadingHandle`

```dart
abstract class LoadingHandle {
  void dispose();
}
```

Returned by `FutureLoadingOverlay.show`/`FutureLoadingOverlayController.show`.
The overlay hides once every outstanding handle (and every task started via
`run`/`runAll`) has finished, subject to `minDisplayDuration`. Calling
`dispose()` more than once is safe and a no-op after the first call.

---

## `LoadingTask<T>`

```dart
class LoadingTask<T> {
  const LoadingTask(this.label, this.future);

  final String label;
  final Future<T> Function() future;
}
```

A labeled unit of work for `runAllTasks`/`FutureLoadingOverlayController.runAll`.

---

## `ActiveTaskInfo`

```dart
class ActiveTaskInfo {
  const ActiveTaskInfo({
    required this.id,
    required this.label,
    required this.startedAt,
    required this.source,
  });

  final int id;
  final String label;
  final DateTime startedAt;
  final ActiveTaskSource source;
}
```

Immutable snapshot of a single in-flight loading request, as seen through
`FutureLoadingOverlayController.activeTasks`/`activeTasksListenable` or a
`TaskStarted`/`TaskFinished` event. `id` is unique and monotonically
increasing for the controller's lifetime.

---

## `ActiveTaskSource`

```dart
enum ActiveTaskSource { manual, run, runAll }
```

Which API created an `ActiveTaskInfo` — `show` (`manual`), `run`, or
`runAll`/`runAllTasks`.

---

## `ExecutionMode`

```dart
enum ExecutionMode { parallel, sequential }
```

How a list of tasks passed to `runAll`/`runAllTasks` is executed. See
[`FutureLoadingOverlay.runAll`](#futureloadingoverlayrunall) above.

---

## `TaskResult<T>`

```dart
sealed class TaskResult<T> {}

final class TaskSuccess<T> extends TaskResult<T> {
  const TaskSuccess(this.value);
  final T value;
}

final class TaskFailure<T> extends TaskResult<T> {
  const TaskFailure(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;
}

final class TaskSkipped<T> extends TaskResult<T> {
  const TaskSkipped();
}
```

The outcome of a single task passed to `runAll`/`runAllTasks`. Exactly one
`TaskResult` is produced per input task, in the same order and with the same
length as the input list. Being a `sealed class`, it pattern-matches
exhaustively:

```dart
switch (result) {
  case TaskSuccess(:final value): ...
  case TaskFailure(:final error, :final stackTrace): ...
  case TaskSkipped(): ...
}
```

`TaskSuccess` implements value equality (`==`/`hashCode`) over its `value`;
`TaskFailure` and `TaskSkipped` do not.

---

## `FutureLoadingOverlayEvent` and subtypes

```dart
sealed class FutureLoadingOverlayEvent {}

final class OverlayShown extends FutureLoadingOverlayEvent {}
final class OverlayHidden extends FutureLoadingOverlayEvent {}
final class BackButtonBlocked extends FutureLoadingOverlayEvent {}
final class BarrierTapped extends FutureLoadingOverlayEvent {}

final class TaskStarted extends FutureLoadingOverlayEvent {
  final ActiveTaskInfo task;
}

final class TaskFinished extends FutureLoadingOverlayEvent {
  final ActiveTaskInfo task;
  final Duration elapsed;
  final bool succeeded;
}
```

| Event | Fired when |
|---|---|
| `OverlayShown` | The overlay transitions from hidden to visible (first task of a session starts). |
| `OverlayHidden` | The overlay transitions from visible to hidden (last task finishes, after `minDisplayDuration`). |
| `BackButtonBlocked` | A back-navigation attempt (button, gesture, or predictive back) was swallowed because the overlay was showing. |
| `BarrierTapped` | The barrier was tapped. Informational only unless `dismissible: true`, in which case it also triggers a clear. |
| `TaskStarted` | Any task starts, via `show`, `run`, `runAll`, or `runAllTasks`. |
| `TaskFinished` | Any task finishes. `succeeded` is always `true` for `show`-created tasks unless cut short by a dismissible clear, in which case it's `false`. |

Delivered on `FutureLoadingOverlayController.events`, a broadcast `Stream`
with **no replay buffer** — subscribe before an event happens to observe it.

---

## `FutureLoadingOverlayController`

The framework-agnostic state owner behind the static facade. Construct your
own instance for tests; the app-wide singleton lives at
`FutureLoadingOverlay.controller`.

```dart
class FutureLoadingOverlayController {
  FutureLoadingOverlayController({FutureLoadingOverlayConfig? defaultConfig});

  ValueListenable<bool> get isShowingListenable;
  bool get isShowing;

  ValueListenable<List<ActiveTaskInfo>> get activeTasksListenable;
  List<ActiveTaskInfo> get activeTasks;

  Stream<FutureLoadingOverlayEvent> get events;

  FutureLoadingOverlayConfig get effectiveConfig;
  void updateDefaultConfig(FutureLoadingOverlayConfig config);

  LoadingHandle show({FutureLoadingOverlayConfig? config, String? label});

  Future<T> run<T>(
    Future<T> Function() future, {
    FutureLoadingOverlayConfig? config,
    String? label,
  });

  Future<List<TaskResult<T>>> runAll<T>(
    List<LoadingTask<T>> tasks, {
    ExecutionMode mode = ExecutionMode.parallel,
    bool stopOnError = false,
    FutureLoadingOverlayConfig? config,
  });

  void forceClear();
  void notifyBackButtonBlocked();
  void notifyBarrierTapped();

  @visibleForTesting
  void dispose();
}
```

Notable members not already covered by the facade:

- **`activeTasks` / `activeTasksListenable`** — every task currently keeping
  the overlay visible, oldest first. Backed by a single internal `Map<int,
  ActiveTaskInfo>` that is the sole source of truth `isShowing` and
  `activeTasks` are both derived from, so they can never drift out of sync
  with each other.
- **`effectiveConfig`** — the config in effect for the current display
  session (see the first-wins rule under
  [`FutureLoadingOverlayConfig`](#futureloadingoverlayconfig)), or the
  controller's default when nothing is showing.
- **`updateDefaultConfig(config)`** — replaces the fallback config used when
  a call doesn't pass its own. Does not affect a session already in progress
  (its config was captured when the session opened). This is what
  `FutureLoadingOverlay.init(defaultConfig: ...)` calls internally.
- **`forceClear()`** — forcibly clears every active task and hides the
  overlay immediately. Tasks already in flight (from `run`/`runAll`) keep
  running to completion in the background; only their overlay bookkeeping is
  discarded. This is what a dismissible barrier tap / back-navigation
  attempt calls internally.
- **`notifyBackButtonBlocked()` / `notifyBarrierTapped()`** — called by
  `BackButtonGuard`/`FutureLoadingOverlayHost` respectively; emits the
  corresponding event and, if `effectiveConfig.dismissible` is `true`, calls
  `forceClear()`. Public so a custom host/guard implementation can drive the
  same controller.
- **`dispose()`** — `@visibleForTesting`. Releases the controller's
  `ValueNotifier`s and closes its event stream. Only meant for throwaway
  controllers created in tests; the app-wide singleton lives for the app's
  lifetime and is never disposed.

---

## `FutureLoadingOverlayHost`

```dart
class FutureLoadingOverlayHost extends StatefulWidget {
  const FutureLoadingOverlayHost({
    super.key,
    required this.controller,
    required this.child,
  });

  final FutureLoadingOverlayController controller;
  final Widget? child;
}
```

The widget `FutureLoadingOverlay.init()`'s returned builder mounts. Renders
`child` as the base layer at all times (via `Stack`) and draws the overlay
barrier on top when `controller.isShowing` is `true` — `child` is never
removed or replaced, which is what prevents a blank screen when the overlay
toggles.

Only renders UI. Back-navigation blocking is handled separately by
`BackButtonGuard` — using this widget directly (instead of through
`FutureLoadingOverlay.init()`) gets you the visual overlay but not the
back-button guarantee; see `BackButtonGuard`'s doc comment for why the two
are split.

---

## `BackButtonGuard`

```dart
class BackButtonGuard with WidgetsBindingObserver {
  BackButtonGuard(this.controller);

  final FutureLoadingOverlayController controller;

  void dispose();
}
```

Intercepts back navigation ahead of the app's own `Navigator`/go_router so it
can be swallowed while the overlay is showing.

This is a bare `WidgetsBindingObserver`, not a widget, registered directly
with `WidgetsBinding.instance` — and registered by `FutureLoadingOverlay.init()`
*before* `runApp()` builds any widget tree. That timing is deliberate:
`WidgetsBinding.handlePopRoute()` asks observers in **registration order**,
not widget-tree order, so an observer added by a widget nested inside
`MaterialApp` (e.g. one living on `FutureLoadingOverlayHost`) always loses
the race to `MaterialApp`'s own observer, which registers the moment its
tree mounts. Registering here, before that tree exists, guarantees this
observer is asked first.

`PopScope` isn't an option for this at all: it requires a `ModalRoute`
ancestor, which a context-free, call-from-anywhere API like this one doesn't
have.

Most apps never construct this directly — `FutureLoadingOverlay.init()`
manages one internally.

---

## Riverpod providers

From `package:future_loading_overlay/riverpod.dart` (a separate import — the
main library doesn't export these, though the package always depends on
`flutter_riverpod`).

```dart
final futureLoadingOverlayEventProvider =
    StreamProvider.autoDispose<FutureLoadingOverlayEvent>(...);

final isFutureLoadingOverlayShowingProvider =
    StreamProvider.autoDispose<bool>(...);

final activeLoadingTasksProvider =
    StreamProvider.autoDispose<List<ActiveTaskInfo>>(...);
```

| Provider | Type | Notes |
|---|---|---|
| `isFutureLoadingOverlayShowingProvider` | `StreamProvider<bool>` | Emits the current value immediately on first watch, then on every change. |
| `activeLoadingTasksProvider` | `StreamProvider<List<ActiveTaskInfo>>` | Same emission behavior, for the active task list. |
| `futureLoadingOverlayEventProvider` | `StreamProvider<FutureLoadingOverlayEvent>` | Mirrors `controller.events` — no replay buffer, only events after first watch. |

All three read `FutureLoadingOverlay.controller` at watch time and bridge its
`ValueListenable`s to `Stream`s by listening/unlistening around each
subscription — they never call `dispose()` on the controller's own
`ValueNotifier`s, so the app-wide controller's state stays valid regardless
of how many widgets are (or stop) watching it.

Access `AsyncValue<T>` as usual:

```dart
final isShowing = ref.watch(isFutureLoadingOverlayShowingProvider).valueOrNull ?? false;
```
