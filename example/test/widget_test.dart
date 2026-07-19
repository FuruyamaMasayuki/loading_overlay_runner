import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loading_overlay_runner/loading_overlay_runner.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('run() shows the overlay and hides it once the future completes', (
    tester,
  ) async {
    LoadingOverlayRunner.resetForTest();
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    expect(find.text('Overlay is hidden'), findsOneWidget);

    final future = LoadingOverlayRunner.run(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(LoadingOverlayRunner.controller.isShowing, isTrue);

    // Advance the fake clock past the 50ms delay so the future's Timer
    // fires — awaiting a real Future.delayed directly inside a widget test
    // would hang forever, since testWidgets runs on a virtual clock that
    // only advances when explicitly pumped.
    await tester.pump(const Duration(milliseconds: 60));
    await future;
    await tester.pumpAndSettle();

    expect(LoadingOverlayRunner.controller.isShowing, isFalse);
    expect(find.text('Overlay is hidden'), findsOneWidget);
  });
}
