import 'dart:io';

import 'package:test/test.dart';

const _entryPoints = ['lib/main.dart'];

/// Types, and the top level names a file publishes alongside them — the
/// `final appPath = AppPath()` singleton pattern is how most of `lib/common`
/// is actually consumed.
final _declaration = RegExp(
  r'^(?:abstract |sealed |final |base |mixin )*'
  r'(?:(?:class|enum|mixin)\s+([A-Za-z]\w*)'
  r'|(?:final|const)\s+(?:[\w<>,\s\[\]?]+\s+)?([a-z]\w*)\s*=)',
  multiLine: true,
);

Iterable<File> _dartFiles({required bool includeGenerated}) sync* {
  for (final root in ['lib', 'test', 'tool', 'plugins']) {
    final directory = Directory(root);
    if (!directory.existsSync()) {
      fail('$root no longer exists; update this test.');
    }
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final generated =
          entity.path.endsWith('.g.dart') ||
          entity.path.endsWith('.freezed.dart') ||
          entity.path.contains('/generated/');
      if (generated && !includeGenerated) continue;
      yield entity;
    }
  }
}

bool _isBarrel(String source) {
  final lines = source
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('//'));
  return lines.isNotEmpty &&
      lines.every(
        (line) => line.startsWith('export ') || line.startsWith('import '),
      );
}

/// Files inherited from FlClash v0.9.2 that the 0.9.2 UI rewrite left behind:
/// every name they publish is referenced only by themselves (plus the barrel
/// that keeps them compiling). They are not a mistake we introduced and they
/// are not worth a delete/modify conflict on the next upstream merge, so they
/// are pinned here instead of being silently tolerated. Anything that lands in
/// this list after today is a new dead file and must be fixed, not listed.
const _inheritedDead = {
  'lib/views/profiles/overwrite/overwrite.dart',
  'lib/views/dashboard/widgets/network_speed.dart',
  'lib/views/proxies/manage_nodes.dart',
  'lib/common/auto_exit_test.dart',
  'lib/common/proxy_share.dart',
  'lib/widgets/tab.dart',
  'lib/widgets/notification.dart',
  'lib/widgets/color_scheme_box.dart',
  'lib/widgets/donut_chart.dart',
  'lib/widgets/wave.dart',
  'lib/widgets/float_layout.dart',
  'lib/features/overwrite/overwrite_nested_sheet.dart',
};

void main() {
  test('every file under lib declares something used outside itself', () {
    // Generated code counts as a consumer but never as a declarer: a riverpod
    // notifier is reached through the provider its annotation generates.
    final consumers = {
      for (final file in _dartFiles(includeGenerated: true))
        file.path: file.readAsStringSync(),
    };
    final sources = {
      for (final file in _dartFiles(includeGenerated: false))
        file.path: consumers[file.path]!,
    };
    final barrels = {
      for (final MapEntry(key: path, value: source) in sources.entries)
        if (_isBarrel(source)) path,
    };

    final orphans = <String>[];

    for (final MapEntry(key: path, value: source) in sources.entries) {
      if (!path.startsWith('lib/')) continue;
      if (barrels.contains(path) || _entryPoints.contains(path)) continue;
      if (path.startsWith('lib/l10n/')) continue;
      // Directory.listSync hands back backslashes on Windows, so the pinned
      // list is compared in the one separator everything else here uses.
      if (_inheritedDead.contains(path.replaceAll(r'\', '/'))) continue;

      // Extensions and typedefs are reached through the types they attach to,
      // never by name, so a file that publishes only those cannot be measured
      // this way.
      final names = _declaration
          .allMatches(source)
          .map((match) => match.group(1) ?? match.group(2)!)
          .toSet();
      if (names.isEmpty) continue;

      final used = consumers.entries.any((entry) {
        if (entry.key == path || barrels.contains(entry.key)) return false;
        return names.any((name) => RegExp('\\b$name\\b').hasMatch(entry.value));
      });

      if (!used) {
        orphans.add(
          '$path — publishes ${names.join(', ')}, none of which is referenced '
          'anywhere else. A barrel export keeps it compiling; it is still dead.',
        );
      }
    }

    expect(orphans, isEmpty, reason: orphans.join('\n'));
  });
}
