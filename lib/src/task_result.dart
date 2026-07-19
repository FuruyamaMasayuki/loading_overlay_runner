import 'package:flutter/foundation.dart';

/// How a list of tasks passed to `runAll`/`runAllTasks` is executed.
enum ExecutionMode {
  /// All tasks start at once (`Future.wait` semantics). One slow or failing
  /// task does not delay or cancel the others.
  parallel,

  /// Tasks run one at a time, in list order.
  sequential,
}

/// The outcome of a single task passed to `runAll`/`runAllTasks`.
///
/// Exactly one [TaskResult] is produced per input task, in the same order
/// and with the same length as the input list.
@immutable
sealed class TaskResult<T> {
  const TaskResult();
}

/// The task completed successfully.
final class TaskSuccess<T> extends TaskResult<T> {
  const TaskSuccess(this.value);

  final T value;

  @override
  bool operator ==(Object other) =>
      other is TaskSuccess<T> && other.value == value;

  @override
  int get hashCode => Object.hash(TaskSuccess<T>, value);

  @override
  String toString() => 'TaskSuccess($value)';
}

/// The task threw.
final class TaskFailure<T> extends TaskResult<T> {
  const TaskFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;

  @override
  String toString() => 'TaskFailure($error)';
}

/// The task never started because an earlier task in the same
/// [ExecutionMode.sequential] batch failed and `stopOnError` was `true`.
final class TaskSkipped<T> extends TaskResult<T> {
  const TaskSkipped();

  @override
  String toString() => 'TaskSkipped()';
}
