import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_loading_overlay/future_loading_overlay.dart';

class _RecordingNavigatorObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}

class _TwoRouteHome extends StatelessWidget {
  const _TwoRouteHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            key: const Key('push'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const Scaffold(body: Center(child: Text('second page'))),
              ),
            ),
            child: const Text('home page'),
          ),
        ),
      ),
    );
  }
}

/// Builds the app the way real usage is documented: wiring through
/// [FutureLoadingOverlay.init], not by hand-constructing
/// [FutureLoadingOverlayHost]. The back-button race this suite guards
/// against only reproduces (and only gets fixed) through this exact path —
/// see [BackButtonGuard]'s doc comment.
Widget _app({
  required NavigatorObserver observer,
  FutureLoadingOverlayConfig? defaultConfig,
}) {
  FutureLoadingOverlay.resetForTest(defaultConfig: defaultConfig);
  return MaterialApp(
    navigatorObservers: [observer],
    builder: FutureLoadingOverlay.init(),
    home: const _TwoRouteHome(),
  );
}

void main() {
  testWidgets('app content stays in the tree while the overlay shows and after it hides', (
    tester,
  ) async {
    await tester.pumpWidget(_app(observer: _RecordingNavigatorObserver()));

    expect(find.text('home page'), findsOneWidget);

    final handle = FutureLoadingOverlay.show();
    await tester.pump();
    expect(
      find.text('home page'),
      findsOneWidget,
      reason: 'app content must never be removed from the tree, or the '
          'screen goes blank while the overlay shows',
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    handle.dispose();
    await tester.pump();
    expect(find.text('home page'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('back navigation is swallowed while showing, and not queued for later', (
    tester,
  ) async {
    final observer = _RecordingNavigatorObserver();
    await tester.pumpWidget(_app(observer: observer));

    await tester.tap(find.byKey(const Key('push')));
    await tester.pumpAndSettle();
    expect(find.text('second page'), findsOneWidget);

    final handle = FutureLoadingOverlay.show();
    await tester.pump();

    // Simulate 3 back-button presses while the overlay is showing. Event-
    // stream assertions for this are covered separately by the controller
    // unit tests (`notifyBackButtonBlocked` there); subscribing to a
    // broadcast stream from inside a widget test that also pushes a route
    // triggers an unrelated flutter_test/fake-async teardown hang on some
    // toolchains, so this test sticks to route-stack/observer assertions.
    await tester.binding.handlePopRoute();
    await tester.binding.handlePopRoute();
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(observer.popCount, 0, reason: 'no route should have popped');
    expect(find.text('second page'), findsOneWidget);

    handle.dispose();
    await tester.pumpAndSettle();

    // None of the 3 blocked attempts should replay now that the overlay
    // is gone — the route stack must be exactly as it was.
    expect(observer.popCount, 0);
    expect(find.text('second page'), findsOneWidget);
  });

  testWidgets('back blocking survives MaterialApp being rebuilt (init re-evaluated)', (
    tester,
  ) async {
    // `builder:` arguments are re-evaluated whenever the widget constructing
    // MaterialApp rebuilds, so init() runs again with MaterialApp's own
    // back-navigation observer already registered. If init() re-registered
    // its guard (dispose + new), the guard would move to the END of the
    // observer list — behind MaterialApp's — and this pop would go through.
    FutureLoadingOverlay.resetForTest();
    final observer = _RecordingNavigatorObserver();
    Widget build() => MaterialApp(
      navigatorObservers: [observer],
      builder: FutureLoadingOverlay.init(),
      home: const _TwoRouteHome(),
    );

    await tester.pumpWidget(build());
    await tester.pumpWidget(build()); // rebuild → init() called a second time

    await tester.tap(find.byKey(const Key('push')));
    await tester.pumpAndSettle();
    expect(find.text('second page'), findsOneWidget);

    final handle = FutureLoadingOverlay.show();
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(observer.popCount, 0, reason: 'guard must still be consulted first');
    expect(find.text('second page'), findsOneWidget);

    handle.dispose();
    await tester.pumpAndSettle();
  });

  testWidgets('back navigation works normally when the overlay is not showing', (
    tester,
  ) async {
    final observer = _RecordingNavigatorObserver();
    await tester.pumpWidget(_app(observer: observer));

    await tester.tap(find.byKey(const Key('push')));
    await tester.pumpAndSettle();
    expect(find.text('second page'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(observer.popCount, 1);
    expect(find.text('home page'), findsOneWidget);
  });

  testWidgets('barrier tap does not dismiss by default', (tester) async {
    await tester.pumpWidget(_app(observer: _RecordingNavigatorObserver()));

    FutureLoadingOverlay.show();
    await tester.pump();
    expect(FutureLoadingOverlay.controller.isShowing, isTrue);

    await tester.tapAt(const Offset(10, 10));
    await tester.pump();

    expect(
      FutureLoadingOverlay.controller.isShowing,
      isTrue,
      reason: 'default config is not dismissible',
    );
  });

  testWidgets('barrier tap dismisses when dismissible is true', (
    tester,
  ) async {
    await tester.pumpWidget(_app(observer: _RecordingNavigatorObserver()));

    FutureLoadingOverlay.show(
      config: const FutureLoadingOverlayConfig(dismissible: true),
    );
    await tester.pump();
    expect(FutureLoadingOverlay.controller.isShowing, isTrue);

    await tester.tapAt(const Offset(10, 10));
    await tester.pump();

    expect(FutureLoadingOverlay.controller.isShowing, isFalse);
  });

  testWidgets('reopening during the closing grace period renders the NEW config', (
    tester,
  ) async {
    await tester.pumpWidget(_app(observer: _RecordingNavigatorObserver()));

    FutureLoadingOverlay.show(
      config: const FutureLoadingOverlayConfig(
        indicator: Text('spinner A'),
        minDisplayDuration: Duration(milliseconds: 100),
      ),
    ).dispose(); // enters the closing grace period, still visible
    await tester.pump();
    expect(find.text('spinner A'), findsOneWidget);

    // isShowing never toggles here — the barrier must still rebuild.
    final second = FutureLoadingOverlay.show(
      config: const FutureLoadingOverlayConfig(indicator: Text('spinner B')),
    );
    await tester.pump();

    expect(find.text('spinner B'), findsOneWidget);
    expect(find.text('spinner A'), findsNothing);

    second.dispose();
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('custom indicator and background are rendered', (tester) async {
    await tester.pumpWidget(_app(observer: _RecordingNavigatorObserver()));

    FutureLoadingOverlay.show(
      config: const FutureLoadingOverlayConfig(
        indicator: Text('loading...'),
        background: ColoredBox(color: Colors.red),
      ),
    );
    await tester.pump();

    expect(find.text('loading...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
