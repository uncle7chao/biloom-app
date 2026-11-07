import 'package:fl_clash/common/update_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> siteJson({
    required String version,
    List<Object?>? files,
    String? notes,
  }) =>
      {
        'enabled': true,
        'latest': {
          'version': version,
          'date': '2026-11-05',
          if (notes != null) 'notes': notes,
          if (files != null) 'files': files,
        },
      };

  List<Object?> standardFiles() => [
        {
          'label': '安装版 setup.exe（国内直连）',
          'kind': 'exe',
          'url': 'https://biloom.top/dl/BiLoom-01.00.43-windows-amd64-setup.exe',
          'size': '44.0 MB',
          'sha256': 'a' * 64,
        },
        {
          'label': '安装版 setup.exe（GitHub 镜像）',
          'kind': 'exe',
          'url':
              'https://github.com/uncle7chao/biloom-app/releases/download/v01.00.43/BiLoom-01.00.43-windows-amd64-setup.exe',
          'size': '44.0 MB',
          'sha256': 'a' * 64,
        },
        {
          'label': '便携版 .zip（国内直连）',
          'kind': 'zip',
          'url': 'https://biloom.top/dl/BiLoom-01.00.43-windows-amd64.zip',
          'size': '70.1 MB',
          'sha256': 'b' * 64,
        },
        {
          'label': '安卓版 APK arm64（国内直连）',
          'kind': 'apk',
          'url': 'https://biloom.top/dl/BiLoom-01.00.43-android-arm64-v8a.apk',
          'size': '64.0 MB',
          'sha256': 'c' * 64,
        },
        {
          'label': '安卓版 APK arm64（GitHub 镜像）',
          'kind': 'apk',
          'url':
              'https://github.com/uncle7chao/biloom-app/releases/download/v01.00.43/BiLoom-01.00.43-android-arm64-v8a.apk',
          'size': '64.0 MB',
          'sha256': 'c' * 64,
        },
      ];

  group('evaluateSiteVersionsJson', () {
    test('newer site version yields a GitHub-shaped update map', () {
      final result = evaluateSiteVersionsJson(
        decoded: siteJson(
          version: '01.00.43',
          files: standardFiles(),
          notes: '新版本说明',
        ),
        currentVersion: '01.00.42',
        isAndroid: false,
      );
      expect(result.reachable, isTrue);
      final update = result.update!;
      expect(update['tag_name'], 'v01.00.43');
      expect(update['body'], '新版本说明');
      expect(
        update['download_url'],
        'https://biloom.top/dl/BiLoom-01.00.43-windows-amd64-setup.exe',
      );
    });

    test('same version is reachable and up to date', () {
      final result = evaluateSiteVersionsJson(
        decoded: siteJson(version: '01.00.42', files: standardFiles()),
        currentVersion: '01.00.42',
        isAndroid: false,
      );
      expect(result.reachable, isTrue);
      expect(result.update, isNull);
    });

    test('local build ahead of the site counts as up to date', () {
      final result = evaluateSiteVersionsJson(
        decoded: siteJson(version: '01.00.41'),
        currentVersion: '01.00.42',
        isAndroid: false,
      );
      expect(result.reachable, isTrue);
      expect(result.update, isNull);
    });

    test('a v-prefixed site version is handled', () {
      final result = evaluateSiteVersionsJson(
        decoded: siteJson(version: 'v01.00.43'),
        currentVersion: '01.00.42',
        isAndroid: false,
      );
      expect(result.update?['tag_name'], 'v01.00.43');
    });

    test('broken or unrecognised payloads are treated as unreachable', () {
      for (final decoded in [
        null,
        <String, Object?>{},
        <String, Object?>{'latest': null},
        <String, Object?>{'latest': <String, Object?>{'version': ''}},
        <String, Object?>{'latest': <String, Object?>{'version': 42}},
      ]) {
        final result = evaluateSiteVersionsJson(
          decoded: decoded,
          currentVersion: '01.00.42',
          isAndroid: false,
        );
        expect(result.reachable, isFalse, reason: 'decoded=$decoded');
        expect(result.update, isNull);
      }
    });

    test('numeric comparison beats lexicographic (9 vs 42)', () {
      final result = evaluateSiteVersionsJson(
        decoded: siteJson(version: '01.00.9'),
        currentVersion: '01.00.42',
        isAndroid: false,
      );
      expect(result.reachable, isTrue);
      expect(result.update, isNull);
    });
  });

  group('pickSiteDownloadUrl', () {
    test('desktop prefers the direct exe over the zip and mirrors', () {
      expect(
        pickSiteDownloadUrl(standardFiles(), isAndroid: false),
        'https://biloom.top/dl/BiLoom-01.00.43-windows-amd64-setup.exe',
      );
    });

    test('android picks the apk entry', () {
      expect(
        pickSiteDownloadUrl(standardFiles(), isAndroid: true),
        'https://biloom.top/dl/BiLoom-01.00.43-android-arm64-v8a.apk',
      );
    });

    test('falls back to the GitHub mirror when no direct link exists', () {
      final files = [
        {
          'label': '安装版 setup.exe（GitHub 镜像）',
          'kind': 'exe',
          'url':
              'https://github.com/uncle7chao/biloom-app/releases/download/v01.00.43/BiLoom-01.00.43-windows-amd64-setup.exe',
        },
      ];
      expect(
        pickSiteDownloadUrl(files, isAndroid: false),
        files.first['url'],
      );
    });

    test('desktop skips an apk-only file list and returns null', () {
      final files = [
        {
          'label': '安卓版 APK arm64（国内直连）',
          'kind': 'apk',
          'url': 'https://biloom.top/dl/BiLoom-01.00.43-android-arm64-v8a.apk',
        },
      ];
      expect(pickSiteDownloadUrl(files, isAndroid: false), isNull);
    });

    test('handles null and empty file lists', () {
      expect(pickSiteDownloadUrl(null, isAndroid: false), isNull);
      expect(pickSiteDownloadUrl(<Object?>[], isAndroid: true), isNull);
    });
  });
}
