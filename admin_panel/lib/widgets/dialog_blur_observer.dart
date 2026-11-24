import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Observes the root [Navigator] and tracks whether any modal dialog or bottom
/// sheet route is currently open (ignoring dropdown menus and popup menus).
///
/// Used by `AdminShell` to smoothly blur the background whenever a popup modal
/// (such as New Receiving Entry, Process Payment, Official Receipt, etc.) is shown.
class DialogBlurObserver extends NavigatorObserver {
  DialogBlurObserver._();

  static final DialogBlurObserver instance = DialogBlurObserver._();

  final ValueNotifier<bool> hasActiveDialog = ValueNotifier<bool>(false);
  int _activeModalCount = 0;

  bool _isModalDialogRoute(Route<dynamic>? route) {
    return route is DialogRoute ||
        route is RawDialogRoute ||
        route is ModalBottomSheetRoute;
  }

  void _syncNotifier() {
    final shouldBlur = _activeModalCount > 0;
    if (hasActiveDialog.value == shouldBlur) return;

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.transientCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        hasActiveDialog.value = _activeModalCount > 0;
      });
    } else {
      hasActiveDialog.value = shouldBlur;
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (_isModalDialogRoute(route)) {
      _activeModalCount++;
      _syncNotifier();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (_isModalDialogRoute(route)) {
      _activeModalCount = (_activeModalCount - 1).clamp(0, 999);
      _syncNotifier();
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (_isModalDialogRoute(route)) {
      _activeModalCount = (_activeModalCount - 1).clamp(0, 999);
      _syncNotifier();
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    final wasModal = _isModalDialogRoute(oldRoute);
    final isModal = _isModalDialogRoute(newRoute);
    if (wasModal && !isModal) {
      _activeModalCount = (_activeModalCount - 1).clamp(0, 999);
      _syncNotifier();
    } else if (!wasModal && isModal) {
      _activeModalCount++;
      _syncNotifier();
    }
  }
}
