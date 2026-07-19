import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../active_task_info.dart';
import '../events.dart';
import '../future_loading_overlay.dart';
import 'listenable_stream.dart';

/// Emits every [FutureLoadingOverlayEvent] as it happens.
///
/// Like `FutureLoadingOverlayController.events`, this has no replay buffer —
/// only events that occur after this provider is first watched are
/// delivered. For point-in-time state, use
/// [isFutureLoadingOverlayShowingProvider] or [activeLoadingTasksProvider].
final futureLoadingOverlayEventProvider =
    StreamProvider.autoDispose<FutureLoadingOverlayEvent>((ref) {
      return FutureLoadingOverlay.controller.events;
    });

/// Whether the overlay is currently visible. Emits an initial value
/// immediately, then updates on every change.
final isFutureLoadingOverlayShowingProvider = StreamProvider.autoDispose<bool>(
  (ref) {
    return listenableToStream(
      FutureLoadingOverlay.controller.isShowingListenable,
    );
  },
);

/// Snapshot of every task currently keeping the overlay visible, oldest
/// first. Emits an initial value immediately, then updates on every change.
final activeLoadingTasksProvider =
    StreamProvider.autoDispose<List<ActiveTaskInfo>>((ref) {
      return listenableToStream(
        FutureLoadingOverlay.controller.activeTasksListenable,
      );
    });
