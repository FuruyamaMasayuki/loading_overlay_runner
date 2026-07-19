import 'dart:async';

import 'package:flutter/foundation.dart';

/// Bridges a [ValueListenable] into a [Stream] that starts with the current
/// value and then emits on every change.
///
/// The listener is attached and the initial value read inside `onListen`, in
/// that order and synchronously — an `async*` generator that yields the
/// current value first and attaches the listener after resuming would leave
/// a suspension gap where a change lands between the two, going unseen and
/// leaving subscribers stale until the *next* change.
///
/// This intentionally does *not* use `ChangeNotifierProvider`: that provider
/// calls `dispose()` on the notifier when the provider is disposed (e.g. via
/// `autoDispose`), which would tear down the shared, app-lifetime
/// [ValueNotifier]s owned by `LoadingOverlayRunnerController` the moment the
/// last widget stopped watching them — leaving the controller permanently
/// broken for the rest of the app. Listening and unlistening here, instead
/// of owning/disposing the listenable, keeps the controller's state
/// independent of how many widgets are currently watching it.
Stream<T> listenableToStream<T>(ValueListenable<T> listenable) {
  late StreamController<T> controller;
  void listener() => controller.add(listenable.value);
  controller = StreamController<T>(
    onListen: () {
      listenable.addListener(listener);
      controller.add(listenable.value);
    },
    onCancel: () {
      listenable.removeListener(listener);
    },
  );
  return controller.stream;
}
