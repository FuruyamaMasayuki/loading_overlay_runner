import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:future_loading_overlay/future_loading_overlay.dart';
import 'package:future_loading_overlay/riverpod.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'future_loading_overlay demo',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
      // The one line that wires the whole package in. From here on, every
      // screen in the app can call FutureLoadingOverlay.show/run/runAll
      // without a BuildContext.
      builder: FutureLoadingOverlay.init(
        defaultConfig: const FutureLoadingOverlayConfig(
          minDisplayDuration: Duration(milliseconds: 250),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _fakeNetworkCall({bool fail = false}) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    if (fail) throw Exception('simulated failure');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('future_loading_overlay demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _ActiveTasksBanner(),
          const SizedBox(height: 16),
          _Section(
            title: 'run() — the common case',
            children: [
              FilledButton(
                onPressed: () => FutureLoadingOverlay.run(
                  () => _fakeNetworkCall(),
                  label: 'Fetching profile',
                ),
                child: const Text('Run a future that succeeds'),
              ),
              FilledButton(
                onPressed: () async {
                  try {
                    await FutureLoadingOverlay.run(
                      () => _fakeNetworkCall(fail: true),
                      label: 'Saving (will fail)',
                    );
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Caught: $e')));
                    }
                  }
                },
                child: const Text('Run a future that throws'),
              ),
            ],
          ),
          _Section(
            title: 'show() / handle.dispose() — manual control',
            children: [
              FilledButton(
                onPressed: () {
                  final handle = FutureLoadingOverlay.show(
                    label: 'Manual 2s',
                  );
                  Future<void>.delayed(
                    const Duration(seconds: 2),
                    handle.dispose,
                  );
                },
                child: const Text('Show for 2 seconds'),
              ),
            ],
          ),
          _Section(
            title: 'runAll() — batch of futures',
            children: [
              FilledButton(
                onPressed: () => FutureLoadingOverlay.runAllTasks<void>([
                  LoadingTask('Profile', () => _fakeNetworkCall()),
                  LoadingTask('Settings', () => _fakeNetworkCall()),
                  LoadingTask(
                    'Notifications (fails)',
                    () => _fakeNetworkCall(fail: true),
                  ),
                ]),
                child: const Text('Run 3 in parallel (one fails)'),
              ),
              FilledButton(
                onPressed: () => FutureLoadingOverlay.runAllTasks<void>(
                  [
                    LoadingTask('Step 1', () => _fakeNetworkCall()),
                    LoadingTask(
                      'Step 2 (fails)',
                      () => _fakeNetworkCall(fail: true),
                    ),
                    LoadingTask('Step 3 (skipped)', () => _fakeNetworkCall()),
                  ],
                  mode: ExecutionMode.sequential,
                  stopOnError: true,
                ),
                child: const Text('Run 3 sequentially, stop on error'),
              ),
            ],
          ),
          _Section(
            title: 'Custom appearance',
            children: [
              FilledButton(
                onPressed: () => FutureLoadingOverlay.run(
                  () => _fakeNetworkCall(),
                  config: const FutureLoadingOverlayConfig(
                    indicator: _BrandedIndicator(),
                    background: ColoredBox(color: Color(0xCC1A1A2E)),
                  ),
                ),
                child: const Text('Custom indicator + background'),
              ),
              FilledButton(
                onPressed: () => FutureLoadingOverlay.run(
                  () => _fakeNetworkCall(),
                  config: const FutureLoadingOverlayConfig(
                    dismissible: true,
                  ),
                ),
                child: const Text('Dismissible (tap or back closes it)'),
              ),
            ],
          ),
          _Section(
            title: 'Cross-screen',
            children: [
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SecondPage()),
                ),
                child: const Text('Open second screen'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SecondPage extends StatelessWidget {
  const SecondPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Second screen')),
      body: Center(
        child: FilledButton(
          // No BuildContext plumbing needed — this call works exactly the
          // same from any screen in the app.
          onPressed: () => FutureLoadingOverlay.run(
            () => Future<void>.delayed(const Duration(seconds: 1)),
            label: 'From the second screen',
          ),
          child: const Text('Run a future from here too'),
        ),
      ),
    );
  }
}

/// Shows the overlay's live state via the bundled Riverpod providers.
class _ActiveTasksBanner extends ConsumerWidget {
  const _ActiveTasksBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isShowing =
        ref.watch(isFutureLoadingOverlayShowingProvider).valueOrNull ?? false;
    final tasks =
        ref.watch(activeLoadingTasksProvider).valueOrNull ??
        const <ActiveTaskInfo>[];

    if (!isShowing) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Overlay is hidden'),
        ),
      );
    }
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Overlay showing — active tasks: '
          '${tasks.map((t) => t.label).join(', ')}',
        ),
      ),
    );
  }
}

class _BrandedIndicator extends StatelessWidget {
  const _BrandedIndicator();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: Colors.white),
        SizedBox(height: 12),
        Text('Loading…', style: TextStyle(color: Colors.white)),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...children.map(
          (w) => Padding(padding: const EdgeInsets.only(bottom: 8), child: w),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
