/// Riverpod providers for `loading_overlay_runner`.
///
/// Import this alongside the main library when you want to `ref.watch` the
/// overlay's state instead of using the `events`/`isShowingListenable` APIs
/// directly:
/// ```dart
/// import 'package:loading_overlay_runner/loading_overlay_runner.dart';
/// import 'package:loading_overlay_runner/riverpod.dart';
/// ```
library;

export 'src/riverpod/providers.dart';
