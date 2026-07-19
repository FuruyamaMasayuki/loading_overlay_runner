import 'package:flutter/widgets.dart';

import 'controller.dart';

/// Intercepts back navigation ahead of the app's own [Navigator]/go_router so
/// it can be swallowed while the overlay is showing.
///
/// This is a bare [WidgetsBindingObserver] — not a widget — registered
/// directly with [WidgetsBinding.instance] by `FutureLoadingOverlay.init`,
/// called synchronously before `runApp`. That timing is what matters:
/// [WidgetsBinding.handlePopRoute] asks observers in *registration order*,
/// not widget-tree order, so a [WidgetsBindingObserver] added by a widget
/// nested inside `MaterialApp` (e.g. via its `builder`) always loses the
/// race to `MaterialApp`'s own observer, which registers in its `initState`
/// the moment the tree mounts. Registering here, before that tree exists,
/// guarantees this observer is asked first — while `PopScope` isn't an
/// option at all, since it requires a [ModalRoute] ancestor that a
/// context-free, call-from-anywhere API like this one doesn't have.
class BackButtonGuard with WidgetsBindingObserver {
  BackButtonGuard(this.controller) {
    WidgetsBinding.instance.addObserver(this);
  }

  final FutureLoadingOverlayController controller;
  bool _disposed = false;

  @override
  Future<bool> didPopRoute() async {
    if (controller.isShowing) {
      controller.notifyBackButtonBlocked();
      return true; // swallow this one attempt; nothing is queued for later
    }
    return false;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
  }
}
