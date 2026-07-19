# loading_overlay_runner

A global, full-screen loading overlay for Flutter. Wire it up once and call it
from anywhere — no `BuildContext` required — to show a spinner while a
`Future` (or a batch of them) runs.

![Demo: showing the overlay via run(), a manual handle, a custom indicator/background, and calling it from a second screen](https://raw.githubusercontent.com/FuruyamaMasayuki/loading_overlay_runner/main/doc/demo.gif)

## Features

- **Call from anywhere.** No `BuildContext` plumbing — works from a widget, a
  service class, or a background callback, on any screen.
- **`run()` / `runAll()`.** Wrap a `Future` (or a list of them, in parallel or
  sequentially) and the overlay shows and hides itself automatically, even on
  error.
- **Ticket-based, not a counter.** Overlapping `show()` calls are tracked as
  independent handles, so a stray extra `hide()` or an exception can't leave
  the overlay stuck or close it early.
- **Doesn't disappear on back/swipe.** Back button, predictive back, and
  iOS edge-swipe are blocked while the overlay is up — no accidental dismiss
  mid-request. Opt into dismissible behavior per call if you want it.
- **Fully customizable.** Swap the indicator and/or the background for any
  widget.
- **Observable.** Watch `isShowing`, the list of active tasks, and a stream of
  lifecycle events (shown/hidden/back-blocked/barrier-tapped/task
  started/finished) — directly or through the bundled Riverpod providers.
- **Never a blank screen.** The host keeps your app's widget tree mounted at
  all times; the overlay is drawn on top, never in place of it.

## Getting started

```yaml
dependencies:
  loading_overlay_runner: ^0.0.1
```

Wire it into `MaterialApp` (or `CupertinoApp`) once, at the root of your app:

```dart
import 'package:flutter/material.dart';
import 'package:loading_overlay_runner/loading_overlay_runner.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: LoadingOverlayRunner.init(),
      home: const HomePage(),
    );
  }
}
```

That's it — every screen in the app can now call `LoadingOverlayRunner.*`.

## Usage

### Run a future

```dart
final profile = await LoadingOverlayRunner.run(
  () => api.fetchProfile(),
  label: 'Fetching profile',
);
```

The overlay shows for the duration of the future and hides once it completes
— whether it succeeds or throws. Errors are rethrown unchanged, so handle
them the way you normally would:

```dart
try {
  await LoadingOverlayRunner.run(() => api.save(form));
} catch (e) {
  showErrorDialog(e);
}
```

### Manual show / hide

For cases that aren't a single `Future` — e.g. showing the overlay across
several imperative steps — `show()` returns a handle. Dispose it when the
work is done:

```dart
final handle = LoadingOverlayRunner.show(label: 'Uploading');
try {
  await step1();
  await step2();
} finally {
  handle.dispose();
}
```

Multiple outstanding handles (from `show`, `run`, or `runAll`) compose
correctly: the overlay only hides once every one of them has been disposed.
Disposing the same handle twice is a safe no-op, so accidental double-release
can't corrupt the count.

### Run several futures at once

```dart
final results = await LoadingOverlayRunner.runAllTasks<Profile>([
  LoadingTask('Profile', () => api.fetchProfile()),
  LoadingTask('Settings', () => api.fetchSettings()),
]);

for (final result in results) {
  switch (result) {
    case TaskSuccess(:final value):
      print('got $value');
    case TaskFailure(:final error):
      print('failed: $error');
    case TaskSkipped():
      print('skipped');
  }
}
```

- `mode: ExecutionMode.parallel` (default) runs every task at once; one
  failing doesn't affect, delay, or cancel the others.
- `mode: ExecutionMode.sequential` runs them one at a time, in order. Pass
  `stopOnError: true` to skip the remaining tasks (as `TaskSkipped`) after the
  first failure.
- The overlay shows once for the whole batch — not once per task — but every
  task still shows up as its own entry in `activeTasks` while it's running.

If you don't need per-task labels, `runAll` takes a plain list of futures
instead of `LoadingTask`s:

```dart
final results = await LoadingOverlayRunner.runAll<void>([
  () => api.ping(),
  () => api.sync(),
]);
```

### Customizing the appearance

```dart
LoadingOverlayRunner.run(
  () => api.save(),
  config: const LoadingOverlayRunnerConfig(
    indicator: MyBrandedSpinner(),
    background: ColoredBox(color: Color(0xCC1A1A2E)),
    minDisplayDuration: Duration(milliseconds: 250),
  ),
);
```

- `indicator` — the widget centered on screen. Defaults to
  `CircularProgressIndicator`.
- `background` — the widget drawn full-screen behind it. Defaults to a
  translucent gray (`Color(0x33000000)`). Pass any widget — a gradient, an
  image, a `BackdropFilter` blur, whatever fits your app.
- `minDisplayDuration` — keeps the overlay up for at least this long, even if
  the work finishes sooner, to avoid flicker on very fast requests.
- `dismissible` — see below.

Set a default for the whole app via `LoadingOverlayRunner.init(defaultConfig:
...)`; a `config` passed to an individual `show`/`run`/`runAll` call overrides
it for that call.

If several `show`/`run`/`runAll` calls overlap, the config from whichever one
opened the display session wins — configs from calls that join an
already-visible overlay are ignored, so the overlay's appearance can't change
mid-flight.

### Back button, swipe, and dismissal

By default the overlay is **not dismissible**: back button presses,
predictive back, and iOS edge-swipe-to-pop are all blocked while it's
showing, and tapping the barrier does nothing. The overlay only closes once
every active task finishes or every handle is disposed.

Set `dismissible: true` on a config to opt out — a back-navigation attempt or
a barrier tap then immediately clears every active task and closes the
overlay. Any `run`/`runAll` futures that were in flight keep running in the
background; only the overlay's bookkeeping is discarded, so their results
(or thrown errors) still resolve normally.

> While the overlay is showing, it's drawn above everything else in the app
> — including dialogs, snack bars, and bottom sheets. That's intentional: the
> whole point is that nothing else is reachable while it's up. If you need UI
> to sit above the overlay (e.g. a "still working, hang tight" dialog), watch
> `events`/`activeTasks` and drive that UI separately rather than trying to
> stack it on top.

### Watching state

```dart
LoadingOverlayRunner.controller.isShowingListenable; // ValueListenable<bool>
LoadingOverlayRunner.controller.activeTasksListenable; // ValueListenable<List<ActiveTaskInfo>>
LoadingOverlayRunner.controller.events; // Stream<LoadingOverlayRunnerEvent>
```

`events` has no replay buffer — subscribe before something happens to observe
it. For point-in-time state, read the `ValueListenable`s (or their current
`.value`) instead.

### Riverpod

```dart
import 'package:loading_overlay_runner/loading_overlay_runner.dart';
import 'package:loading_overlay_runner/riverpod.dart';

class LoadingBanner extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isShowing =
        ref.watch(isLoadingOverlayRunnerShowingProvider).valueOrNull ?? false;
    final tasks =
        ref.watch(activeLoadingTasksProvider).valueOrNull ?? const [];
    ...
  }
}
```

Three providers are included:

- `isLoadingOverlayRunnerShowingProvider` — `StreamProvider<bool>`
- `activeLoadingTasksProvider` — `StreamProvider<List<ActiveTaskInfo>>`
- `loadingOverlayRunnerEventProvider` — `StreamProvider<LoadingOverlayRunnerEvent>`

## Caveats

- **Generic type per `runAll` call.** `runAll<T>`/`runAllTasks<T>` require a
  single result type for the whole batch. Mixing return types means calling
  with `T = Object?` and casting each `TaskResult.value` yourself.
- **Hardware keyboard events are not blocked.** The barrier absorbs every
  pointer event, but focus is deliberately left where it was (so a focused
  `TextField`'s IME state isn't destroyed by a brief overlay). That means a
  hardware keyboard can still reach the focused widget behind the overlay —
  e.g. pressing Enter could activate a focused button. If that matters for a
  flow, call `FocusManager.instance.primaryFocus?.unfocus()` before showing
  the overlay.
- **Android predictive back on the root route.** When the navigator has only
  one route, `WidgetsApp` tells the OS the framework won't handle back, and
  Android 14+ predictive back can then background the app entirely at the
  system level — without ever consulting the framework, so no overlay can
  intercept it (this is an OS-level behavior, not specific to this package).
  With one or more routes pushed, back is delivered to the framework and
  blocked as documented.
- **`indicator`/`background` render outside your app's exact theme context
  in edge cases.** They're built inside `MaterialApp`'s own tree (via
  `builder`), so `Theme.of`/`Directionality` resolve normally — this only
  matters if you construct `LoadingOverlayRunnerHost` directly instead of
  through `LoadingOverlayRunner.init()`.
- **`LoadingOverlayRunner.init()`'s first call must run before `runApp()`
  builds the tree** — it's what lets its back-button handling register ahead
  of your `Navigator`/router (see the `BackButtonGuard` doc comment for
  why). Passing it as the `builder:` argument, as shown above, already
  guarantees this. Repeat calls (which happen naturally whenever the widget
  constructing `MaterialApp` rebuilds) are safe: the controller and guard
  registration are preserved.

## Additional information

See `example/lib/main.dart` for a runnable demo of every feature in this
README, including the Riverpod providers.

File issues and contribute at the package repository.
