import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'path.dart';
import 'preferences.dart';

/// 自动备份设置 —— 持久化（shared_preferences）。
///
/// 不进 [Config]（freezed）：这是一份「机器本地行为开关」，不是要随备份
/// 走到另一台设备的数据 —— 恢复备份把「每次加订阅都自动备份」一起搬过去
/// 反而是意外。SP 直存，与 ProxyChainStore / ProxyFavoritesStore 同一模式，
/// 也绕开了改 freezed 模型必须重新生成代码的依赖。
const kAutoBackupSettingsKey = 'autoBackupSettings';

enum AutoBackupTrigger { addProfile, removeProfile }

class AutoBackupSettings {
  final bool onAddProfile;
  final bool onRemoveProfile;

  /// 本地历史保留份数，超出按文件名（时间戳序）淘汰最旧的。
  final int keepCount;

  const AutoBackupSettings({
    this.onAddProfile = false,
    this.onRemoveProfile = false,
    this.keepCount = defaultKeepCount,
  });

  static const defaultKeepCount = 5;
  static const maxKeepCount = 20;

  bool enabledFor(AutoBackupTrigger trigger) {
    return switch (trigger) {
      AutoBackupTrigger.addProfile => onAddProfile,
      AutoBackupTrigger.removeProfile => onRemoveProfile,
    };
  }

  Map<String, dynamic> toJson() => {
    'onAddProfile': onAddProfile,
    'onRemoveProfile': onRemoveProfile,
    'keepCount': keepCount,
  };

  factory AutoBackupSettings.fromJson(Map<String, dynamic> json) =>
      AutoBackupSettings(
        onAddProfile: json['onAddProfile'] == true,
        onRemoveProfile: json['onRemoveProfile'] == true,
        keepCount: json['keepCount'] is int
            ? (json['keepCount'] as int).clamp(1, maxKeepCount)
            : defaultKeepCount,
      );

  AutoBackupSettings copyWith({
    bool? onAddProfile,
    bool? onRemoveProfile,
    int? keepCount,
  }) {
    return AutoBackupSettings(
      onAddProfile: onAddProfile ?? this.onAddProfile,
      onRemoveProfile: onRemoveProfile ?? this.onRemoveProfile,
      keepCount: keepCount ?? this.keepCount,
    );
  }
}

class AutoBackupStore {
  static const dirName = 'auto_backups';
  static const filePrefix = 'auto_';

  static Future<AutoBackupSettings> loadSettings() async {
    final prefs = await preferences.sharedPreferencesCompleter.future;
    final raw = prefs?.getString(kAutoBackupSettingsKey);
    if (raw == null || raw.isEmpty) {
      return const AutoBackupSettings();
    }
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) {
        return const AutoBackupSettings();
      }
      return AutoBackupSettings.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // 坏数据当默认设置，不影响其它功能。
      return const AutoBackupSettings();
    }
  }

  static Future<void> saveSettings(AutoBackupSettings settings) async {
    final prefs = await preferences.sharedPreferencesCompleter.future;
    await prefs?.setString(
      kAutoBackupSettingsKey,
      json.encode(settings.toJson()),
    );
  }

  /// 自动备份目录：<数据目录>/auto_backups/。惰性创建。
  static Future<Directory> dir() async {
    final directory = Directory(p.join(await appPath.homeDirPath, dirName));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// 把一份现成的备份 zip 收进自动备份目录（时间戳命名），并按
  /// [keepCount] 滚动淘汰最旧的。返回落盘后的文件。
  static Future<File> createFromZip(
    String sourceZipPath, {
    required int keepCount,
  }) async {
    final directory = await dir();
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final target = File(p.join(directory.path, '$filePrefix$stamp.zip'));
    await File(sourceZipPath).copy(target.path);
    await prune(keepCount: keepCount);
    return target;
  }

  /// 列出全部自动备份，**新在前**（文件名含时间戳，倒序即可）。
  static Future<List<File>> list() async {
    final directory = await dir();
    if (!await directory.exists()) {
      return const [];
    }
    final files = await directory
        .list()
        .where((entity) => entity is File)
        .where((entity) => p.basename(entity.path).startsWith(filePrefix))
        .where((entity) => p.extension(entity.path) == '.zip')
        .cast<File>()
        .toList();
    files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    return files;
  }

  /// 按 [keepCount] 滚动淘汰：列表新在前，保留前 [keepCount] 份。
  static Future<void> prune({required int keepCount}) async {
    final files = await list();
    for (final file in files.skip(
      keepCount.clamp(1, AutoBackupSettings.maxKeepCount),
    )) {
      try {
        await file.delete();
      } catch (_) {
        // 单个文件删不掉（被占用等）不阻塞整体，下次 prune 再试。
      }
    }
  }
}
