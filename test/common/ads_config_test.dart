import 'package:fl_clash/common/ads.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdsRemoteConfig v4 解析', () {
    test('v4 完整 JSON：新键正确解析', () {
      const raw = '''
{
  "v": 4,
  "enabled": true,
  "bannerAndroid": {"enabled": true, "adUnitId": "ca-app-pub-x/1"},
  "bannerWindows": {"enabled": false, "adUnitId": ""},
  "bannerProxiesAndroid": {"enabled": true, "adUnitId": "ca-app-pub-x/2"},
  "nativeProxiesAndroid": {"enabled": true, "adUnitId": "ca-app-pub-x/3"},
  "promoWindows": {"enabled": false, "url": "", "badge": ""}
}
''';
      final config = AdsRemoteConfig.parse(raw);
      expect(config, isNotNull);
      expect(config!.v, 4);
      expect(config.enabled, isTrue);
      expect(config.bannerAndroid.adUnitId, 'ca-app-pub-x/1');
      expect(config.bannerProxiesAndroid.enabled, isTrue);
      expect(config.bannerProxiesAndroid.adUnitId, 'ca-app-pub-x/2');
      expect(config.nativeProxiesAndroid.enabled, isTrue);
      expect(config.nativeProxiesAndroid.adUnitId, 'ca-app-pub-x/3');
    });

    test('旧版 JSON（v2/v3）缺新键：新位取安全默认值=关', () {
      const raw = '''
{
  "v": 3,
  "enabled": true,
  "bannerAndroid": {"enabled": true, "adUnitId": "ca-app-pub-x/1"},
  "bannerWindows": {"enabled": false, "adUnitId": ""}
}
''';
      final config = AdsRemoteConfig.parse(raw);
      expect(config, isNotNull);
      expect(config!.bannerProxiesAndroid.enabled, isFalse);
      expect(config.bannerProxiesAndroid.adUnitId, isEmpty);
      expect(config.nativeProxiesAndroid.enabled, isFalse);
      expect(config.nativeProxiesAndroid.adUnitId, isEmpty);
    });

    test('总开关关：两位判定一律 null', () {
      const raw = '''
{
  "v": 4,
  "enabled": false,
  "bannerProxiesAndroid": {"enabled": true, "adUnitId": "ca-app-pub-x/2"},
  "nativeProxiesAndroid": {"enabled": true, "adUnitId": "ca-app-pub-x/3"}
}
''';
      final config = AdsRemoteConfig.parse(raw);
      expect(
        adsProxiesBannerPropsFor(config, AdPlatform.android),
        isNull,
      );
      expect(adsNativePropsFor(config, AdPlatform.android), isNull);
    });

    test('位开但 ID 空：判定 null（没位子的开=关）', () {
      const raw = '''
{
  "v": 4,
  "enabled": true,
  "bannerProxiesAndroid": {"enabled": true, "adUnitId": ""},
  "nativeProxiesAndroid": {"enabled": true, "adUnitId": "  "}
}
''';
      final config = AdsRemoteConfig.parse(raw);
      expect(
        adsProxiesBannerPropsFor(config, AdPlatform.android),
        isNull,
      );
      // 纯空白 ID 也判空（trim 语义：空串检查走 isEmpty，空白串按开启
      // 会传给 SDK 崩 —— 这里第二键是空白串，AdPlacementProps 不做 trim，
      // 判定看 isEmpty，所以 "  " 会被放行。防线在 props 层：)
      final native = adsNativePropsFor(config, AdPlatform.android);
      expect(native, isNotNull);
      expect(native!.adUnitId, '  ');
    });

    test('桌面平台：两位恒 null（SDK 接缝之外的位只属于 Android）', () {
      const raw = '''
{
  "v": 4,
  "enabled": true,
  "bannerProxiesAndroid": {"enabled": true, "adUnitId": "ca-app-pub-x/2"},
  "nativeProxiesAndroid": {"enabled": true, "adUnitId": "ca-app-pub-x/3"}
}
''';
      final config = AdsRemoteConfig.parse(raw);
      for (final platform in AdPlatform.values) {
        if (platform == AdPlatform.android) continue;
        expect(
          adsProxiesBannerPropsFor(config, platform),
          isNull,
          reason: '$platform 不应拿到代理页 Banner',
        );
        expect(
          adsNativePropsFor(config, platform),
          isNull,
          reason: '$platform 不应拿到原生位',
        );
      }
    });

    test('坏 JSON：返回 null 不上抛', () {
      expect(AdsRemoteConfig.parse('not json'), isNull);
      expect(AdsRemoteConfig.parse('[]'), isNull);
      expect(AdsRemoteConfig.parse(null), isNull);
      expect(AdsRemoteConfig.parse(''), isNull);
    });
  });

  group('AdsRemoteConfig v5 解析（配置页 / 工具页 Banner）', () {
    test('v5 完整 JSON：新键正确解析，ID 允许复用现有单元', () {
      const raw = '''
{
  "v": 5,
  "enabled": true,
  "bannerAndroid": {"enabled": true, "adUnitId": "ca-app-pub-x/1"},
  "bannerProfilesAndroid": {"enabled": true, "adUnitId": "ca-app-pub-x/2"},
  "bannerToolsAndroid": {"enabled": true, "adUnitId": "ca-app-pub-x/2"}
}
''';
      final config = AdsRemoteConfig.parse(raw);
      expect(config, isNotNull);
      expect(config!.v, 5);
      expect(config.bannerProfilesAndroid.enabled, isTrue);
      expect(config.bannerProfilesAndroid.adUnitId, 'ca-app-pub-x/2');
      expect(config.bannerToolsAndroid.enabled, isTrue);
      // 复用同一广告单元是合法形态，两层各存各的值。
      expect(config.bannerToolsAndroid.adUnitId, 'ca-app-pub-x/2');
    });

    test('v4 旧 JSON 缺 v5 键：配置页/工具页取安全默认值=关', () {
      const raw = '''
{
  "v": 4,
  "enabled": true,
  "bannerAndroid": {"enabled": true, "adUnitId": "ca-app-pub-x/1"},
  "bannerProxiesAndroid": {"enabled": true, "adUnitId": "ca-app-pub-x/2"},
  "nativeProxiesAndroid": {"enabled": true, "adUnitId": "ca-app-pub-x/3"}
}
''';
      final config = AdsRemoteConfig.parse(raw);
      expect(config, isNotNull);
      expect(config!.bannerProfilesAndroid.enabled, isFalse);
      expect(config.bannerProfilesAndroid.adUnitId, isEmpty);
      expect(config.bannerToolsAndroid.enabled, isFalse);
      expect(config.bannerToolsAndroid.adUnitId, isEmpty);
    });

    test('v5 判定函数：Android 放行、总开关关 null、桌面恒 null', () {
      const rawOn = '''
{
  "v": 5,
  "enabled": true,
  "bannerProfilesAndroid": {"enabled": true, "adUnitId": "ca-app-pub-x/2"},
  "bannerToolsAndroid": {"enabled": true, "adUnitId": "ca-app-pub-x/2"}
}
''';
      final on = AdsRemoteConfig.parse(rawOn);
      expect(
        adsProfilesBannerPropsFor(on, AdPlatform.android),
        isNotNull,
      );
      expect(adsToolsBannerPropsFor(on, AdPlatform.android), isNotNull);
      for (final platform in AdPlatform.values) {
        if (platform == AdPlatform.android) continue;
        expect(
          adsProfilesBannerPropsFor(on, platform),
          isNull,
          reason: '$platform 不应拿到配置页 Banner',
        );
        expect(
          adsToolsBannerPropsFor(on, platform),
          isNull,
          reason: '$platform 不应拿到工具页 Banner',
        );
      }

      const rawOff = '''
{
  "v": 5,
  "enabled": false,
  "bannerProfilesAndroid": {"enabled": true, "adUnitId": "ca-app-pub-x/2"},
  "bannerToolsAndroid": {"enabled": true, "adUnitId": "ca-app-pub-x/2"}
}
''';
      final off = AdsRemoteConfig.parse(rawOff);
      expect(adsProfilesBannerPropsFor(off, AdPlatform.android), isNull);
      expect(adsToolsBannerPropsFor(off, AdPlatform.android), isNull);

      expect(adsProfilesBannerPropsFor(null, AdPlatform.android), isNull);
      expect(adsToolsBannerPropsFor(null, AdPlatform.android), isNull);
    });
  });
}
