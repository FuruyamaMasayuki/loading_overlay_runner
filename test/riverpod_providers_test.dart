import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_loading_overlay/future_loading_overlay.dart';
import 'package:future_loading_overlay/riverpod.dart';

void main() {
  setUp(() {
    FutureLoadingOverlay.resetForTest();
  });

  test('isFutureLoadingOverlayShowingProvider reflects controller state', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Prime the provider (StreamProvider starts in loading state until the
    // first event arrives).
    final sub = container.listen(
      isFutureLoadingOverlayShowingProvider,
      (_, _) {},
    );
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().value, isFalse);

    final handle = FutureLoadingOverlay.show();
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

    final handle = FutureLoadingOverlay.show(label: 'uploading');
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().value?.map((t) => t.label), ['uploading']);

    handle.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().value, isEmpty);
  });

  test('futureLoadingOverlayEventProvider emits lifecycle events', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final events = <FutureLoadingOverlayEvent>[];
    container.listen(futureLoadingOverlayEventProvider, (_, next) {
      final value = next.value;
      if (value != null) events.add(value);
    });
    await Future<void>.delayed(Duration.zero);

    final handle = FutureLoadingOverlay.show();
    handle.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(events.whereType<OverlayShown>(), hasLength(1));
    expect(events.whereType<OverlayHidden>(), hasLength(1));
  });
}
