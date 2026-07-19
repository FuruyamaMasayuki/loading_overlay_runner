/// Riverpod providers for `future_loading_overlay`.
///
/// Import this alongside the main library when you want to `ref.watch` the
/// overlay's state instead of using the `events`/`isShowingListenable` APIs
/// directly:
/// ```dart
/// import 'package:future_loading_overlay/future_loading_overlay.dart';
/// import 'package:future_loading_overlay/riverpod.dart';
/// ```
library;

export 'src/riverpod/providers.dart';
