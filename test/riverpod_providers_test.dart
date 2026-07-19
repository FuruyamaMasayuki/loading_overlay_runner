import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loading_overlay_runner/loading_overlay_runner.dart';
import 'package:loading_overlay_runner/riverpod.dart';

void main() {
  setUp(() {
    LoadingOverlayRunner.resetForTest();
  });

  test('isLoadingOverlayRunnerShowingProvider reflects controller state', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Prime the provider (StreamProvider starts in loading state until the
    // first event arrives).
    final sub = container.listen(
      isLoadingOverlayRunnerShowingProvider,
      (_, _) {},
    );
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().value, isFalse);

    final handle = LoadingOverlayRunner.show();
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().value, isTrue);

    handle.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().value, isFalse);
  });

  test('activeLoadingTasksProvider reflects the active task list', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final sub = container.listen(activeLoadingTasksProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().value, isEmpty);

    final handle = LoadingOverlayRunner.show(label: 'uploading');
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().value?.map((t) => t.label), ['uploading']);

    handle.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().value, isEmpty);
  });

  test('loadingOverlayRunnerEventProvider emits lifecycle events', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final events = <LoadingOverlayRunnerEvent>[];
    container.listen(loadingOverlayRunnerEventProvider, (_, next) {
      final value = next.value;
      if (value != null) events.add(value);
    });
    await Future<void>.delayed(Duration.zero);

    final handle = LoadingOverlayRunner.show();
    handle.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(events.whereType<OverlayShown>(), hasLength(1));
    expect(events.whereType<OverlayHidden>(), hasLength(1));
  });
}
