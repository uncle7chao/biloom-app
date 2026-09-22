import 'dart:async';

import 'package:fl_clash/common/app_ports.dart';
import 'package:fl_clash/common/preferences.dart';
import 'package:fl_clash/models/config.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/actions/system_exit.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestSystemAction extends SystemAction {
  final List<String> calls = [];
  final List<bool> cleanupNeedSave = [];
  Completer<void>? closeCoreGate;
  Object? cleanupError;
  Duration watchdog = const Duration(hours: 1);

  @override
  Duration get exitWatchdogDuration => watchdog;

  @override
  Future<void> cleanupExitResources(bool needSave) async {
    calls.add('cleanup');
    cleanupNeedSave.add(needSave);
    final error = cleanupError;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }

  @override
  Future<void> closeWindow() async => calls.add('window');

  @override
  Future<void> closeCore() async {
    calls.add('core');
    final gate = closeCoreGate;
    if (gate != null) {
      await gate.future;
    }
  }

  @override
  Future<void> exitApplication() async => calls.add('exit');
}

class _PersistenceSystemAction extends SystemAction {
  Future<void> persist() => savePreferences();
}

/// 只记录「有没有人来要求启动 / 停止」，其余一概不碰。
/// 真实实现会去拉内核实连接，在单元测试里那是一串永远等不到回应的定时器。
class _RecordingSetupAction extends SetupAction {
  final List<bool> calls = [];

  @override
  Future<bool> setRunning(bool running, {bool initialize = false}) async {
    calls.add(running);
    // 真实实现会在这里同步更新 runTimeProvider，而对齐逻辑正是靠它判断
    // 「此刻算不算已连接」。照着做，否则第二次拨开关会因为「状态没变」提前返回，
    // 测到的就不是真正的行为了。
    ref.read(runTimeProvider.notifier).value = running ? 0 : null;
    return true;
  }
}

class _GeometryWindowPort implements WindowPort {
  final WindowProps geometry;
  final Error? error;

  _GeometryWindowPort(this.geometry, {this.error});

  @override
  Future<WindowProps?> captureNormalGeometry(WindowProps current) async {
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return geometry;
  }

  @override
  Future<void> close() async {}

  @override
  void forceExit() {}

  @override
  Future<void> hide() async {}

  @override
  Future<void> toggle() async {}

  @override
  Future<void> show() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('coalesces repeated exit requests and runs cleanup once', () async {
    final closeCoreCompleter = Completer<void>();
    final calls = <String>[];
    final coordinator = SystemExitCoordinator(
      watchdogDuration: const Duration(hours: 1),
      closeWindow: () async => calls.add('window'),
      closeCore: () async {
        calls.add('core');
        await closeCoreCompleter.future;
      },
      exitApplication: () async => calls.add('exit'),
    );

    final first = coordinator.exit(cleanup: () async => calls.add('cleanup'));
    final second = coordinator.exit(
      cleanup: () async => calls.add('unexpected cleanup'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(identical(first, second), isTrue);
    expect(calls, ['cleanup', 'window', 'core']);

    closeCoreCompleter.complete();
    await Future.wait([first, second]);

    expect(calls, ['cleanup', 'window', 'core', 'exit']);
  });

  test('watchdog and normal completion share one application exit', () async {
    final closeCoreCompleter = Completer<void>();
    var exitCount = 0;
    final coordinator = SystemExitCoordinator(
      watchdogDuration: const Duration(milliseconds: 1),
      closeWindow: () async {},
      closeCore: () => closeCoreCompleter.future,
      exitApplication: () async => exitCount++,
    );

    final operation = coordinator.exit(cleanup: () async {});
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(exitCount, 1);
    closeCoreCompleter.complete();
    await operation;
    expect(exitCount, 1);
  });

  test('cleanup failure does not skip window or Core shutdown', () async {
    final calls = <String>[];
    final coordinator = SystemExitCoordinator(
      watchdogDuration: const Duration(hours: 1),
      closeWindow: () async => calls.add('window'),
      closeCore: () async => calls.add('core'),
      exitApplication: () async => calls.add('exit'),
    );

    await expectLater(
      coordinator.exit(
        cleanup: () async {
          calls.add('cleanup');
          throw StateError('cleanup failed');
        },
      ),
      throwsStateError,
    );

    expect(calls, ['cleanup', 'window', 'core', 'exit']);
  });

  group('SystemAction exit orchestration', () {
    late TestSystemAction action;
    late ProviderContainer container;

    setUp(() {
      action = TestSystemAction();
      container = ProviderContainer(
        overrides: [systemActionProvider.overrideWith(() => action)],
      );
      globalState.container = container;
      container.read(systemActionProvider.notifier);
    });

    tearDown(() {
      final gate = action.closeCoreGate;
      if (gate != null && !gate.isCompleted) {
        gate.complete();
      }
      container.dispose();
    });

    SystemAction notifier() => container.read(systemActionProvider.notifier);

    test('runs cleanup, window, Core and application exit in order', () async {
      await notifier().handleExit();

      expect(action.calls, ['cleanup', 'window', 'core', 'exit']);
      expect(action.cleanupNeedSave, [true]);
    });

    test('forwards an explicit save opt-out to resource cleanup', () async {
      await notifier().handleExit(false);

      expect(action.cleanupNeedSave, [false]);
    });

    test('concurrent exit requests share one shutdown', () async {
      action.closeCoreGate = Completer<void>();

      final first = notifier().handleExit();
      final second = notifier().handleExit(true);
      await Future<void>.delayed(Duration.zero);

      expect(action.calls, ['cleanup', 'window', 'core']);

      action.closeCoreGate!.complete();
      await Future.wait([first, second]);

      expect(action.calls, ['cleanup', 'window', 'core', 'exit']);
      expect(action.cleanupNeedSave, [true]);
    });

    test('a later exit request never restarts a finished shutdown', () async {
      await notifier().handleExit();
      await notifier().handleExit();

      expect(action.calls, ['cleanup', 'window', 'core', 'exit']);
    });

    test(
      'the watchdog exits the application when Core shutdown hangs',
      () async {
        action.watchdog = const Duration(milliseconds: 1);
        action.closeCoreGate = Completer<void>();

        final operation = notifier().handleExit();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(action.calls, ['cleanup', 'window', 'core', 'exit']);

        action.closeCoreGate!.complete();
        await operation;

        expect(
          action.calls.where((call) => call == 'exit').length,
          1,
          reason: 'the watchdog and normal completion share one exit',
        );
      },
    );

    test('a cleanup failure still closes the window, Core and app', () async {
      action.cleanupError = StateError('cleanup failed');

      await expectLater(notifier().handleExit(), throwsStateError);

      expect(action.calls, ['cleanup', 'window', 'core', 'exit']);
    });
  });

  test(
    'saving preferences captures the latest normal window geometry',
    () async {
      SharedPreferences.setMockInitialValues({});
      const geometry = WindowProps(width: 1180, height: 760, left: 72, top: 48);
      windowPort = _GeometryWindowPort(geometry);
      final action = _PersistenceSystemAction();
      final container = ProviderContainer(
        overrides: [systemActionProvider.overrideWith(() => action)],
      );
      globalState.container = container;
      addTearDown(() {
        windowPort = null;
        container.dispose();
      });

      container.read(systemActionProvider.notifier);
      await action.persist();

      expect(container.read(windowSettingProvider), geometry);
      expect((await preferences.getConfig())?.windowProps, geometry);
    },
  );

  test(
    'a geometry failure does not prevent saving the current config',
    () async {
      SharedPreferences.setMockInitialValues({});
      const current = WindowProps(width: 900, height: 640, left: 24, top: 16);
      windowPort = _GeometryWindowPort(
        const WindowProps(),
        error: StateError('window unavailable'),
      );
      final action = _PersistenceSystemAction();
      final container = ProviderContainer(
        overrides: [
          windowSettingProvider.overrideWithBuild((_, _) => current),
          systemActionProvider.overrideWith(() => action),
        ],
      );
      globalState.container = container;
      addTearDown(() {
        windowPort = null;
        container.dispose();
      });

      container.read(systemActionProvider.notifier);
      await action.persist();

      expect((await preferences.getConfig())?.windowProps, current);
    },
  );

  group('SystemAction setting toggles', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      globalState.container = container;
    });

    tearDown(() => container.dispose());

    test('updateTun flips the patched Core tun flag', () {
      final before = container.read(patchClashConfigProvider).tun.enable;

      container.read(systemActionProvider.notifier).updateTun();

      expect(container.read(patchClashConfigProvider).tun.enable, !before);
    });

    test('updateSystemProxy flips the system proxy flag', () {
      final before = container.read(networkSettingProvider).systemProxy;

      container.read(systemActionProvider.notifier).updateSystemProxy();

      expect(container.read(networkSettingProvider).systemProxy, !before);
    });

    test('updateAutoLaunch flips the auto launch flag', () {
      final before = container.read(appSettingProvider).autoLaunch;

      container.read(systemActionProvider.notifier).updateAutoLaunch();

      expect(container.read(appSettingProvider).autoLaunch, !before);
    });
  });

  // 「打开系统代理」和「启动」在用户心里是同一件事。这一组就是把这件事钉死：
  // 拨开任意一种接管方式（系统代理 / TUN）就必须连上，两种都关掉就必须断开 ——
  // 不允许出现「开关亮着却没连接」这种自相矛盾的状态。
  group('takeover switches and the running state are one thing', () {
    late _RecordingSetupAction setup;
    late ProviderContainer container;

    setUp(() {
      setup = _RecordingSetupAction();
      container = ProviderContainer(
        overrides: [setupActionProvider.overrideWith(() => setup)],
      );
      globalState.container = container;
      container.read(setupActionProvider.notifier);
      // 能点到这些开关的时候 bootstrap 一定已经跑完（initProvider 为 true）。
      // 显式置位是为了让对齐逻辑真的执行，而不是走「还没起来就别动」那条短路。
      container.read(initProvider.notifier).value = true;
    });

    tearDown(() => container.dispose());

    SystemAction action() => container.read(systemActionProvider.notifier);

    test('turning the system proxy on starts the connection', () {
      action().updateSystemProxy();

      expect(container.read(networkSettingProvider).systemProxy, isTrue);
      expect(setup.calls, [true]);
    });

    test('turning it back off stops the connection', () {
      action().updateSystemProxy();
      action().updateSystemProxy();

      expect(container.read(networkSettingProvider).systemProxy, isFalse);
      expect(setup.calls, [true, false]);
    });

    test('the TUN switch means the same thing as connecting', () {
      action().updateTun();

      expect(container.read(patchClashConfigProvider).tun.enable, isTrue);
      expect(setup.calls, [true]);
    });

    test('closing one takeover way keeps the connection', () {
      action().updateTun();
      action().updateSystemProxy();
      action().updateTun();

      expect(container.read(patchClashConfigProvider).tun.enable, isFalse);
      expect(container.read(networkSettingProvider).systemProxy, isTrue);
      expect(
        setup.calls,
        [true],
        reason: '系统代理还开着，就不该断开',
      );
    });

    test('closing both takeover ways stops the connection', () {
      action().updateTun();
      action().updateSystemProxy();
      action().updateSystemProxy();
      action().updateTun();

      expect(container.read(networkSettingProvider).systemProxy, isFalse);
      expect(container.read(patchClashConfigProvider).tun.enable, isFalse);
      expect(setup.calls, [true, false]);
    });

    test('the main connect entry picks system proxy when nothing is on', () {
      action().connect();

      expect(container.read(networkSettingProvider).systemProxy, isTrue);
      expect(setup.calls, [true]);
    });

    test('the main disconnect entry releases every takeover way', () {
      action().updateTun();
      action().disconnect();

      expect(container.read(networkSettingProvider).systemProxy, isFalse);
      expect(container.read(patchClashConfigProvider).tun.enable, isFalse);
      expect(setup.calls, [true, false]);
    });

    test('before the app is ready a switch only flips its own flag', () {
      container.read(initProvider.notifier).value = false;

      action().updateSystemProxy();

      expect(container.read(networkSettingProvider).systemProxy, isTrue);
      expect(
        setup.calls,
        isEmpty,
        reason: 'bootstrap 还没跑完，启动要交给它自己的恢复流程',
      );
    });
  });
}
