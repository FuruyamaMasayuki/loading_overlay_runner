import 'package:flutter/foundation.dart';

/// Identifies which API created an [ActiveTaskInfo].
enum ActiveTaskSource {
  /// Created via [FutureLoadingOverlay.show].
  manual,

  /// Created via [FutureLoadingOverlay.run].
  run,

  /// Created via [FutureLoadingOverlay.runAll] / [FutureLoadingOverlay.runAllTasks].
  runAll,
}

/// Immutable snapshot of a single in-flight loading request.
@immutable
class ActiveTaskInfo {
  const ActiveTaskInfo({
    required this.id,
    required this.label,
    required this.startedAt,
    required this.source,
  });

  /// Unique id assigned by the controller when the task starts. Monotonically
  /// increasing for the lifetime of the controller.
  final int id;

  /// Human readable label. Defaults to `task#<id>` when the caller doesn't
  /// supply one.
  final String label;

  /// When this task started, for computing elapsed duration.
  final DateTime startedAt;

  /// Which API created this task.
  final ActiveTaskSource source;

  @override
  String toString() => 'ActiveTaskInfo(#$id, $label, source: $source)';
}

/// A labeled unit of work for [FutureLoadingOverlay.runAllTasks].
@immutable
class LoadingTask<T> {
  const LoadingTask(this.label, this.future);

  /// Shown in [ActiveTaskInfo.label] while this task is running.
  final String label;

  final Future<T> Function() future;
}
