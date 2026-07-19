import 'package:flutter/foundation.dart';

import 'active_task_info.dart';

/// Base type for events emitted on `LoadingOverlayRunnerController.events`.
///
/// The stream is a broadcast stream with no replay buffer: subscribe before
/// an event happens to observe it. For point-in-time state, read
/// `isShowingListenable` or `activeTasksListenable` instead.
@immutable
sealed class LoadingOverlayRunnerEvent {
  const LoadingOverlayRunnerEvent();
}

/// The overlay transitioned from hidden to visible.
final class OverlayShown extends LoadingOverlayRunnerEvent {
  const OverlayShown();
}

/// The overlay transitioned from visible to hidden.
final class OverlayHidden extends LoadingOverlayRunnerEvent {
  const OverlayHidden();
}

/// A back-navigation attempt (button, gesture, or predictive back) was
/// swallowed because the overlay was showing.
final class BackButtonBlocked extends LoadingOverlayRunnerEvent {
  const BackButtonBlocked();
}

/// The user tapped the overlay barrier while it was showing.
///
/// By default this is informational only and does not close the overlay.
/// When `LoadingOverlayRunnerConfig.dismissible` is `true`, it also clears
/// every active task (see `LoadingOverlayRunnerController.forceClear`).
final class BarrierTapped extends LoadingOverlayRunnerEvent {
  const BarrierTapped();
}

/// A task started, via `show`, `run`, `runAll`, or `runAllTasks`.
final class TaskStarted extends LoadingOverlayRunnerEvent {
  const TaskStarted(this.task);

  final ActiveTaskInfo task;
}

/// A task finished, successfully or not.
final class TaskFinished extends LoadingOverlayRunnerEvent {
  const TaskFinished(
    this.task, {
    required this.elapsed,
    required this.succeeded,
  });

  final ActiveTaskInfo task;
  final Duration elapsed;

  /// Whether the task completed without throwing. Always `true` for tasks
  /// started via `show`, since manual show/dispose has no notion of success
  /// or failure — unless it was cut short by `forceClear`, in which case
  /// it's `false`.
  final bool succeeded;
}
