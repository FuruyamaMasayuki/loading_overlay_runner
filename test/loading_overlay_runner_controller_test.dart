import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:loading_overlay_runner/loading_overlay_runner.dart';

void main() {
  group('show/dispose (ticket-based visibility)', () {
    test('single handle shows then hides', () {
      final controller = LoadingOverlayRunnerController();
      expect(controller.isShowing, isFalse);

      final handle = controller.show();
      expect(controller.isShowing, isTrue);

      handle.dispose();
      expect(controller.isShowing, isFalse);
    });

    test('overlay stays visible until every outstanding handle is disposed', () {
      final controller = LoadingOverlayRunnerController();
      final a = controller.show();
      final b = controller.show();

      expect(controller.isShowing, isTrue);
      a.dispose();
      expect(controller.isShowing, isTrue, reason: 'b is still outstanding');
      b.dispose();
      expect(controller.isShowing, isFalse);
    });

    test('disposing the same handle twice is a no-op', () {
      final controller = LoadingOverlayRunnerController();
      final a = controller.show();
      final b = controller.show();

      a.dispose();
      a.dispose(); // must not affect b's outstanding count
      expect(controller.isShowing, isTrue);

      b.dispose();
      expect(controller.isShowing, isFalse);
    });
  });

  group('minDisplayDuration / stale-hide protection', () {
    test('a delayed hide does not close an overlay reopened while it waited', () async {
      final controller = LoadingOverlayRunnerController(
        defaultConfig: const LoadingOverlayRunnerConfig(
          minDisplayDuration: Duration(milliseconds: 30),
        ),
      );

      final first = controller.show();
      first.dispose(); // schedules a hide ~30ms from now

      // Reopen before the delayed hide fires.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final second = controller.show();
      expect(controller.isShowing, isTrue);

      // Wait past when the stale hide would have fired.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(
        controller.isShowing,
        isTrue,
        reason: 'the stale delayed hide from `first` must not close the '
            'overlay that `second` reopened',
      );

      second.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(controller.isShowing, isFalse);
    });

    test('overlay hides immediately when minDisplayDuration is zero', () {
      final controller = LoadingOverlayRunnerController();
      final handle = controller.show();
      handle.dispose();
      expect(controller.isShowing, isFalse);
    });

    test('minDisplayDuration counts from when the overlay appeared, not from the last dispose', () async {
      final controller = LoadingOverlayRunnerController(
        defaultConfig: const LoadingOverlayRunnerConfig(
          minDisplayDuration: Duration(milliseconds: 60),
        ),
      );

      final handle = controller.show();
      // The task outlives the minimum: by dispose time the guarantee is
      // already satisfied, so the overlay must hide immediately — waiting
      // the full 60ms *again* here was the bug.
      await Future<void>.delayed(const Duration(milliseconds: 90));
      handle.dispose();
      expect(controller.isShowing, isFalse);
    });

    test('a task shorter than minDisplayDuration keeps the overlay up for the remainder', () async {
      final controller = LoadingOverlayRunnerController(
        defaultConfig: const LoadingOverlayRunnerConfig(
          minDisplayDuration: Duration(milliseconds: 60),
        ),
      );

      final handle = controller.show();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      handle.dispose();
      expect(controller.isShowing, isTrue, reason: 'only ~10ms of 60ms shown');

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(controller.isShowing, isFalse);
    });
  });

  group('config first-wins', () {
    test('the config of the call that opens the session wins', () {
      final controller = LoadingOverlayRunnerController();
      const first = LoadingOverlayRunnerConfig(dismissible: true);
      const second = LoadingOverlayRunnerConfig(dismissible: false);

      final a = controller.show(config: first);
      controller.show(config: second); // joins an already-open session

      expect(controller.effectiveConfig.dismissible, isTrue);
      a.dispose();
    });

    test('a fresh session after fully closing adopts the new config', () {
      final controller = LoadingOverlayRunnerController();
      const first = LoadingOverlayRunnerConfig(dismissible: true);
      const second = LoadingOverlayRunnerConfig(dismissible: false);

      controller.show(config: first).dispose();
      expect(controller.isShowing, isFalse);

      controller.show(config: second);
      expect(controller.effectiveConfig.dismissible, isFalse);
    });

    test('reopening during the closing grace period adopts the new config '
        'and emits no duplicate OverlayShown', () async {
      const first = LoadingOverlayRunnerConfig(
        dismissible: true,
        minDisplayDuration: Duration(milliseconds: 60),
      );
      const second = LoadingOverlayRunnerConfig(dismissible: false);
      final controller = LoadingOverlayRunnerController();

      final shownEvents = <OverlayShown>[];
      final sub = controller.events
          .where((e) => e is OverlayShown)
          .cast<OverlayShown>()
          .listen(shownEvents.add);

      controller.show(config: first).dispose();
      expect(controller.isShowing, isTrue, reason: 'closing grace period');

      // Reopen while still visible: a new session, but no hide happened in
      // between, so no second OverlayShown may be emitted.
      controller.show(config: second);
      expect(controller.effectiveConfig.dismissible, isFalse);

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(shownEvents, hasLength(1));
    });
  });

  group('run', () {
    test('hides after success and returns the value', () async {
      final controller = LoadingOverlayRunnerController();
      final result = await controller.run(() async => 42);
      expect(result, 42);
      expect(controller.isShowing, isFalse);
    });

    test('hides and rethrows on failure', () async {
      final controller = LoadingOverlayRunnerController();
      await expectLater(
        controller.run(() async => throw StateError('boom')),
        throwsA(isA<StateError>()),
      );
      expect(controller.isShowing, isFalse);
    });

    test('shows while pending', () async {
      final controller = LoadingOverlayRunnerController();
      final done = Completer<void>();
      final future = controller.run(() async {
        expect(controller.isShowing, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        done.complete();
      });
      await future;
      expect(done.isCompleted, isTrue);
      expect(controller.isShowing, isFalse);
    });
  });

  group('runAll', () {
    test('empty list returns immediately without showing', () async {
      final controller = LoadingOverlayRunnerController();
      final results = await controller.runAll<int>(const []);
      expect(results, isEmpty);
      expect(controller.isShowing, isFalse);
    });

    test('parallel preserves input order regardless of completion order', () async {
      final controller = LoadingOverlayRunnerController();
      final results = await controller.runAll<int>([
        LoadingTask('slow', () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return 1;
        }),
        LoadingTask('fast', () async => 2),
      ]);
      expect(results, [const TaskSuccess<int>(1), const TaskSuccess<int>(2)]);
    });

    test('parallel: one failure does not affect the others', () async {
      final controller = LoadingOverlayRunnerController();
      final results = await controller.runAll<int>([
        LoadingTask('ok', () async => 1),
        LoadingTask('bad', () async => throw StateError('bad')),
        LoadingTask('ok2', () async => 3),
      ]);
      expect(results[0], const TaskSuccess<int>(1));
      expect(results[1], isA<TaskFailure<int>>());
      expect(results[2], const TaskSuccess<int>(3));
    });

    test('sequential runs one at a time, in order', () async {
      final controller = LoadingOverlayRunnerController();
      final order = <String>[];
      await controller.runAll<int>(
        [
          LoadingTask('a', () async {
            order.add('a-start');
            await Future<void>.delayed(const Duration(milliseconds: 10));
            order.add('a-end');
            return 1;
          }),
          LoadingTask('b', () async {
            order.add('b-start');
            return 2;
          }),
        ],
        mode: ExecutionMode.sequential,
      );
      expect(order, ['a-start', 'a-end', 'b-start']);
    });

    test('sequential with stopOnError skips remaining tasks', () async {
      final controller = LoadingOverlayRunnerController();
      var thirdRan = false;
      final results = await controller.runAll<int>(
        [
          LoadingTask('a', () async => 1),
          LoadingTask('b', () async => throw StateError('bad')),
          LoadingTask('c', () async {
            thirdRan = true;
            return 3;
          }),
        ],
        mode: ExecutionMode.sequential,
        stopOnError: true,
      );
      expect(results[0], const TaskSuccess<int>(1));
      expect(results[1], isA<TaskFailure<int>>());
      expect(results[2], isA<TaskSkipped<int>>());
      expect(thirdRan, isFalse);
    });

    test('sequential batch is a single session: no hide/re-show between tasks', () async {
      final controller = LoadingOverlayRunnerController();
      final shownEvents = <OverlayShown>[];
      final hiddenEvents = <OverlayHidden>[];
      final subShown = controller.events
          .where((e) => e is OverlayShown)
          .cast<OverlayShown>()
          .listen(shownEvents.add);
      final subHidden = controller.events
          .where((e) => e is OverlayHidden)
          .cast<OverlayHidden>()
          .listen(hiddenEvents.add);

      var visibleAtSecondTaskStart = false;
      await controller.runAll<int>(
        [
          LoadingTask('a', () async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return 1;
          }),
          LoadingTask('b', () async {
            // The moment between task a finishing and task b starting is
            // exactly where the overlay used to flicker off and back on.
            visibleAtSecondTaskStart = controller.isShowing;
            return 2;
          }),
        ],
        mode: ExecutionMode.sequential,
      );

      await Future<void>.delayed(Duration.zero);
      await subShown.cancel();
      await subHidden.cancel();

      expect(visibleAtSecondTaskStart, isTrue);
      expect(shownEvents, hasLength(1));
      expect(hiddenEvents, hasLength(1));
      expect(controller.isShowing, isFalse);
    });

    test('dismissing mid-batch keeps the overlay closed for the rest of the batch, '
        'but remaining tasks still produce results', () async {
      final controller = LoadingOverlayRunnerController();
      final shownEvents = <OverlayShown>[];
      final sub = controller.events
          .where((e) => e is OverlayShown)
          .cast<OverlayShown>()
          .listen(shownEvents.add);

      final gate1 = Completer<int>();
      final resultsFuture = controller.runAll<int>(
        [
          LoadingTask('a', () => gate1.future),
          LoadingTask('b', () async => 2),
        ],
        mode: ExecutionMode.sequential,
        config: const LoadingOverlayRunnerConfig(dismissible: true),
      );

      await Future<void>.delayed(Duration.zero);
      expect(controller.isShowing, isTrue);

      // The user dismisses while task a is in flight.
      controller.notifyBarrierTapped();
      expect(controller.isShowing, isFalse);

      gate1.complete(1);
      final results = await resultsFuture;

      expect(results[0], const TaskSuccess<int>(1));
      expect(results[1], const TaskSuccess<int>(2),
          reason: 'remaining tasks still run after dismissal');
      expect(controller.isShowing, isFalse,
          reason: 'the dismissed batch must not reopen the overlay');
      expect(controller.activeTasks, isEmpty);

      // A fresh, unrelated request afterwards shows normally.
      final handle = controller.show();
      expect(controller.isShowing, isTrue);
      handle.dispose();

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(shownEvents, hasLength(2),
          reason: 'one for the batch, one for the fresh show() — none from '
              'the dismissed batch reopening');
    });

    test('overlay shows for the whole batch, not once per task', () async {
      final controller = LoadingOverlayRunnerController();
      final shownEvents = <OverlayShown>[];
      final sub = controller.events
          .where((e) => e is OverlayShown)
          .cast<OverlayShown>()
          .listen(shownEvents.add);

      await controller.runAll<int>([
        LoadingTask('a', () async => 1),
        LoadingTask('b', () async => 2),
        LoadingTask('c', () async => 3),
      ]);

      await sub.cancel();
      expect(shownEvents.length, 1);
    });

    test('a run() started mid-batch joins the batch session and keeps it open '
        'until both are done', () async {
      final controller = LoadingOverlayRunnerController();
      final shownEvents = <OverlayShown>[];
      final hiddenEvents = <OverlayHidden>[];
      final subShown = controller.events
          .where((e) => e is OverlayShown)
          .cast<OverlayShown>()
          .listen(shownEvents.add);
      final subHidden = controller.events
          .where((e) => e is OverlayHidden)
          .cast<OverlayHidden>()
          .listen(hiddenEvents.add);

      final batchGate = Completer<int>();
      final runGate = Completer<int>();

      // Sequential batch of one long task, so the batch pin is held while we
      // slip a run() in alongside it.
      final batchFuture = controller.runAll<int>(
        [LoadingTask('batch', () => batchGate.future)],
        mode: ExecutionMode.sequential,
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.isShowing, isTrue);

      final runFuture = controller.run(() => runGate.future);
      await Future<void>.delayed(Duration.zero);
      expect(controller.activeTasks, hasLength(2));

      // Batch finishes first: its pin releases, but the run() task is still
      // active, so the overlay must stay up.
      batchGate.complete(1);
      await batchFuture;
      expect(controller.isShowing, isTrue, reason: 'run() still in flight');

      runGate.complete(2);
      await runFuture;
      expect(controller.isShowing, isFalse);

      await Future<void>.delayed(Duration.zero);
      await subShown.cancel();
      await subHidden.cancel();
      expect(shownEvents, hasLength(1), reason: 'one joined session');
      expect(hiddenEvents, hasLength(1));
    });
  });

  group('activeTasks stays in sync', () {
    test('show/run/runAll register and deregister tasks', () async {
      final controller = LoadingOverlayRunnerController();
      expect(controller.activeTasks, isEmpty);

      final handle = controller.show(label: 'manual');
      expect(controller.activeTasks.map((t) => t.label), ['manual']);

      final runFuture = controller.run(() async {
        expect(controller.activeTasks.map((t) => t.label), containsAll(['manual', 'task#1']));
        return null;
      }, label: 'task#1');
      await runFuture;
      expect(controller.activeTasks.map((t) => t.label), ['manual']);

      handle.dispose();
      expect(controller.activeTasks, isEmpty);
    });

    test('runAll(parallel) shows every task as its own entry at once', () async {
      final controller = LoadingOverlayRunnerController();
      final gate = Completer<void>();
      late List<String> labelsWhileRunning;

      final future = controller.runAll<void>([
        LoadingTask('one', () => gate.future),
        LoadingTask('two', () => gate.future),
      ]);

      // Let both tasks register before either resolves.
      await Future<void>.delayed(Duration.zero);
      labelsWhileRunning = controller.activeTasks.map((t) => t.label).toList();
      gate.complete();
      await future;

      expect(labelsWhileRunning, unorderedEquals(['one', 'two']));
      expect(controller.activeTasks, isEmpty);
    });
  });

  group('forceClear / dismissible', () {
    test('forceClear hides immediately and marks tasks unsuccessful', () async {
      final controller = LoadingOverlayRunnerController();
      final finishedEvents = <TaskFinished>[];
      final sub = controller.events
          .where((e) => e is TaskFinished)
          .cast<TaskFinished>()
          .listen(finishedEvents.add);

      controller.show(label: 'a');
      controller.show(label: 'b');
      controller.forceClear();

      expect(controller.isShowing, isFalse);
      expect(controller.activeTasks, isEmpty);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(finishedEvents, hasLength(2));
      expect(finishedEvents.every((e) => !e.succeeded), isTrue);
    });

    test('barrier tap only force-clears when dismissible is true', () {
      final controller = LoadingOverlayRunnerController();
      controller.show(
        config: const LoadingOverlayRunnerConfig(dismissible: false),
      );
      controller.notifyBarrierTapped();
      expect(controller.isShowing, isTrue);

      final controller2 = LoadingOverlayRunnerController();
      controller2.show(
        config: const LoadingOverlayRunnerConfig(dismissible: true),
      );
      controller2.notifyBarrierTapped();
      expect(controller2.isShowing, isFalse);
    });
  });

  group('dismissible during the closing grace period', () {
    test('barrier tap during minDisplayDuration grace hides immediately', () {
      final controller = LoadingOverlayRunnerController();
      controller
          .show(
            config: const LoadingOverlayRunnerConfig(
              dismissible: true,
              minDisplayDuration: Duration(seconds: 5),
            ),
          )
          .dispose();
      // Zero tasks, zero pins — but still visible for up to 5s.
      expect(controller.isShowing, isTrue, reason: 'grace period');

      controller.notifyBarrierTapped();
      expect(
        controller.isShowing,
        isFalse,
        reason: 'dismissible must be able to cut the grace period short',
      );
    });
  });

  group('updateDefaultConfig vs open session', () {
    test('a session opened without a per-call config keeps the default it '
        'was opened with', () {
      final controller = LoadingOverlayRunnerController(
        defaultConfig: const LoadingOverlayRunnerConfig(dismissible: true),
      );
      final handle = controller.show(); // no per-call config
      expect(controller.effectiveConfig.dismissible, isTrue);

      controller.updateDefaultConfig(
        const LoadingOverlayRunnerConfig(dismissible: false),
      );
      expect(
        controller.effectiveConfig.dismissible,
        isTrue,
        reason: 'the open session captured its config when it opened; '
            'changing the default must not restyle or re-behave it mid-flight',
      );

      handle.dispose();
      // The next session picks up the new default.
      controller.show();
      expect(controller.effectiveConfig.dismissible, isFalse);
    });
  });

  group('back button / barrier notifications', () {
    test('notifyBackButtonBlocked emits BackButtonBlocked', () async {
      final controller = LoadingOverlayRunnerController();
      final events = <BackButtonBlocked>[];
      final sub = controller.events
          .where((e) => e is BackButtonBlocked)
          .cast<BackButtonBlocked>()
          .listen(events.add);

      controller.show();
      controller.notifyBackButtonBlocked();
      controller.notifyBackButtonBlocked();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(events, hasLength(2));
      expect(controller.isShowing, isTrue, reason: 'not dismissible by default');
    });

    test('notifyBarrierTapped emits BarrierTapped', () async {
      final controller = LoadingOverlayRunnerController();
      final events = <BarrierTapped>[];
      final sub = controller.events
          .where((e) => e is BarrierTapped)
          .cast<BarrierTapped>()
          .listen(events.add);

      controller.show();
      controller.notifyBarrierTapped();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(events, hasLength(1));
    });
  });
}
