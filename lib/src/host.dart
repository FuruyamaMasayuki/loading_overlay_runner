import 'package:flutter/material.dart';

import 'active_task_info.dart';
import 'controller.dart';

/// Inserted by `LoadingOverlayRunner.init` into `MaterialApp.builder`.
///
/// Keeps the app's own widget tree ([child]) as the base layer at all times
/// and draws the overlay UI on top of it via [Stack] — [child] is never
/// removed or replaced, which is what prevents a blank white screen when the
/// overlay toggles on or off.
///
/// This widget only renders the overlay UI. Back-navigation blocking is
/// handled separately by [BackButtonGuard], registered by
/// `LoadingOverlayRunner.init` — see that class's doc comment for why it
/// can't live here as a widget-scoped observer.
class LoadingOverlayRunnerHost extends StatefulWidget {
  const LoadingOverlayRunnerHost({
    super.key,
    required this.controller,
    required this.child,
  });

  final LoadingOverlayRunnerController controller;
  final Widget? child;

  @override
  State<LoadingOverlayRunnerHost> createState() =>
      _LoadingOverlayRunnerHostState();
}

class _LoadingOverlayRunnerHostState extends State<LoadingOverlayRunnerHost> {
  @override
  Widget build(BuildContext context) {
    final appContent = widget.child ?? const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: widget.controller.isShowingListenable,
      builder: (context, showing, cachedChild) {
        return Stack(
          children: [
            // ExcludeSemantics keeps screen readers from reaching the app
            // behind the barrier while it's up, without ever unmounting it.
            ExcludeSemantics(excluding: showing, child: cachedChild!),
            if (showing)
              // Also rebuild on task-list changes, not just on isShowing:
              // when a new session opens during the previous session's
              // minDisplayDuration grace period, isShowing stays true the
              // whole time, and without this the barrier would keep
              // rendering the old session's indicator/background instead of
              // the new session's config.
              ValueListenableBuilder<List<ActiveTaskInfo>>(
                valueListenable: widget.controller.activeTasksListenable,
                builder: (context, _, _) =>
                    _LoadingOverlayRunnerBarrier(controller: widget.controller),
              ),
          ],
        );
      },
      child: appContent,
    );
  }
}

class _LoadingOverlayRunnerBarrier extends StatelessWidget {
  const _LoadingOverlayRunnerBarrier({required this.controller});

  final LoadingOverlayRunnerController controller;

  @override
  Widget build(BuildContext context) {
    final config = controller.effectiveConfig;
    return Positioned.fill(
      child: Semantics(
        container: true,
        label: 'Loading',
        child: GestureDetector(
          // Opaque hit-testing absorbs every pointer event in this region,
          // including the touch-down that would otherwise start an edge
          // swipe-back gesture on the route beneath — that recognizer never
          // gets a chance to see the pointer.
          behavior: HitTestBehavior.opaque,
          onTap: controller.notifyBarrierTapped,
          child: Stack(
            fit: StackFit.expand,
            children: [
              config.background ??
                  const ColoredBox(color: Color(0x33000000)),
              Center(
                child: config.indicator ?? const CircularProgressIndicator(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
