import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../active_task_info.dart';
import '../events.dart';
import '../loading_overlay_runner.dart';
import 'listenable_stream.dart';

/// Emits every [LoadingOverlayRunnerEvent] as it happens.
///
/// Like `LoadingOverlayRunnerController.events`, this has no replay buffer —
/// only events that occur after this provider is first watched are
/// delivered. For point-in-time state, use
/// [isLoadingOverlayRunnerShowingProvider] or [activeLoadingTasksProvider].
final loadingOverlayRunnerEventProvider =
    StreamProvider.autoDispose<LoadingOverlayRunnerEvent>((ref) {
      return LoadingOverlayRunner.controller.events;
    });

/// Whether the overlay is currently visible. Emits an initial value
/// immediately, then updates on every change.
final isLoadingOverlayRunnerShowingProvider = StreamProvider.autoDispose<bool>(
  (ref) {
    return listenableToStream(
      LoadingOverlayRunner.controller.isShowingListenable,
    );
  },
);

/// Snapshot of every task currently keeping the overlay visible, oldest
/// first. Emits an initial value immediately, then updates on every change.
final activeLoadingTasksProvider =
    StreamProvider.autoDispose<List<ActiveTaskInfo>>((ref) {
      return listenableToStream(
        LoadingOverlayRunner.controller.activeTasksListenable,
      );
    });
