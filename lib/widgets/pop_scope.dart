import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../ui/pop_scope.dart' show routeBackLayersOf;
import 'inherited.dart';

class CommonPopScope extends StatelessWidget {
  final Widget child;
  final FutureOr<bool> Function(BuildContext context)? onPop;
  final FutureOr<void> Function()? onPopSuccess;

  const CommonPopScope({
    super.key,
    required this.child,
    this.onPop,
    this.onPopSuccess,
  });

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: routeBackLayersOf(route),
      builder: (context, backLayers, _) {
        final hasBackLayer =
            backLayers > 0 || route?.willHandlePopInternally == true;
        return PopScope(
          canPop: onPop == null || hasBackLayer,
          onPopInvokedWithResult: onPop == null
              ? null
              : (didPop, _) async {
                  if (didPop) {
                    return;
                  }
                  final res = await onPop!(context);
                  if (!context.mounted) {
                    return;
                  }
                  if (!res) {
                    return;
                  }
                  Navigator.of(context).pop();
                  if (onPopSuccess != null) {
                    await onPopSuccess!();
                  }
                },
          child: child,
        );
      },
    );
  }
}

class BackLayerScope extends StatefulWidget {
  final Widget child;
  final VoidCallback onBack;
  @visibleForTesting
  final void Function(void Function(Duration) callback)?
  schedulePostFrameCallback;

  const BackLayerScope({
    super.key,
    required this.onBack,
    required this.child,
    @visibleForTesting this.schedulePostFrameCallback,
  });

  @override
  State<BackLayerScope> createState() => _BackLayerScopeState();
}

class _BackLayerScopeState extends State<BackLayerScope> {
  ModalRoute<dynamic>? _route;
  LocalHistoryEntry? _entry;
  bool _isDetaching = false;
  bool _isPageActive = true;
  int _syncRevision = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    final isPageActive = PageActivityScope.isActiveOf(context);
    if (identical(_route, route) && _isPageActive == isPageActive) {
      return;
    }
    _detach();
    _route = route;
    _isPageActive = isPageActive;
    final revision = ++_syncRevision;
    final schedulePostFrameCallback =
        widget.schedulePostFrameCallback ??
        WidgetsBinding.instance.addPostFrameCallback;
    schedulePostFrameCallback((_) {
      if (!mounted || revision != _syncRevision) {
        return;
      }
      if (!_isPageActive) {
        widget.onBack();
        return;
      }
      if (route == null) {
        return;
      }
      final entry = LocalHistoryEntry(
        impliesAppBarDismissal: false,
        onRemove: _handleRemove,
      );
      _entry = entry;
      route.addLocalHistoryEntry(entry);
      routeBackLayersOf(route).value++;
    });
  }

  void _handleRemove() {
    _entry = null;
    final route = _route;
    if (route != null) {
      final notifier = routeBackLayersOf(route);
      void decrement() => notifier.value = math.max(0, notifier.value - 1);
      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        // Detach can run inside didChangeDependencies during a build; defer
        // the decrement so ValueListenableBuilder is not marked dirty
        // mid-build. Pop-driven removals happen outside a frame and stay
        // synchronous so canPop is fresh for the next back press.
        WidgetsBinding.instance.addPostFrameCallback((_) => decrement());
      } else {
        decrement();
      }
    }
    if (!_isDetaching && mounted) {
      widget.onBack();
    }
  }

  void _detach() {
    final entry = _entry;
    if (entry == null) {
      return;
    }
    _entry = null;
    _isDetaching = true;
    entry.remove();
    _isDetaching = false;
  }

  @override
  void dispose() {
    _syncRevision++;
    _detach();
    _route = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
