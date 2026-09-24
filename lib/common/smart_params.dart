/// 智能抗检测参数层 —— 纯逻辑部分（零依赖，可独立测试）。
///
/// 面向小白用户：抗检测相关参数由系统代填，用户零操作。三条原则：
/// 1. **只补缺省，绝不覆盖显式值** —— 订阅/分享链接/手填里写了
///    client-fingerprint 的节点原样保留；
/// 2. **只碰客户端侧参数** —— uTLS 指纹服务器端不校验具体值，填错最多没
///    效果、不会连不上；服务端约定参数（SNI/Reality 公钥/ws path/obfs 密码）
///    是和服务器对暗号，一律不碰、不猜；
/// 3. **池化轮换只对被本层补过默认值的节点生效**，订阅给的指纹不动。
///
/// 指纹可用值全集见内核 component/tls/utls.go（uTLSMap + 扩展指纹表）。
/// 持久化与轮换触发见 smart_params_store.dart；接入点：
/// providers/actions/setup.dart 的 getProfile（configMap → 最终 yaml 的
/// 必经之路，订阅/粘贴/链接/手填全来源覆盖）。

const kSmartAntidetectionKey = 'smartAntidetectionEnabled';
const kFingerprintOverridesKey = 'fingerprintOverrides';

/// 轮换池。第一项是默认填充值，之后依次是失败重试的候选。
/// chrome 在统计上最不易引起注意，作为起点；randomized/chrome120 放最后兜底。
const kFingerprintPool = <String>[
  'chrome',
  'firefox',
  'safari',
  'ios',
  'edge',
  'qq',
  'randomized',
  'chrome120',
];

/// 支持智能补指纹的协议。hy2 的 fingerprint 字段语义不同（证书固定），
/// socks5/http 没有 uTLS 握手，都不在列。
const _smartFingerprintTypes = <String>{'vmess', 'vless', 'trojan'};

/// 本层补过默认指纹的节点名。轮换只对这些名字生效；
/// 进程内易失，每次 setup 时由 [smartFillProxies] 重建。陈旧条目无害：
/// 池内任何指纹对服务器都是功能等价的合法客户端问候。
final Set<String> smartFilledProxyNames = {};

/// 一个节点的指纹覆盖记录。
class FingerprintRecord {
  final String fingerprint;

  /// 上次轮换时间（毫秒时间戳），用于冷却判断。
  final int rotatedAt;

  const FingerprintRecord({required this.fingerprint, required this.rotatedAt});

  Map<String, dynamic> toJson() =>
      {'fingerprint': fingerprint, 'rotatedAt': rotatedAt};

  static FingerprintRecord? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    final fingerprint = json['fingerprint'];
    final rotatedAt = json['rotatedAt'];
    if (fingerprint is! String || fingerprint.isEmpty) {
      return null;
    }
    return FingerprintRecord(
      fingerprint: fingerprint,
      rotatedAt: rotatedAt is num ? rotatedAt.toInt() : 0,
    );
  }
}

/// 给 configMap['proxies'] 里缺省指纹的节点补默认值/轮换覆盖值。
///
/// configMap 来自内核 getConfig（JSON 解码，proxies 内联），直接原地修改。
/// 返回是否发生了改动（调用方据此判断 yaml md5 是否会变）。
bool smartFillProxies(
  Map<String, dynamic> configMap, {
  Map<String, FingerprintRecord> overrides = const {},
}) {
  final proxies = configMap['proxies'];
  if (proxies is! List) {
    return false;
  }
  var changed = false;
  for (final item in proxies) {
    if (item is! Map) {
      continue;
    }
    final type = item['type'];
    if (type is! String || !_smartFingerprintTypes.contains(type)) {
      continue;
    }
    final name = item['name'];
    if (name is! String || name.isEmpty) {
      continue;
    }
    final current = item['client-fingerprint'];
    if (current is String && current.isNotEmpty) {
      continue;
    }
    final record = overrides[name];
    item['client-fingerprint'] = record?.fingerprint ?? kFingerprintPool.first;
    smartFilledProxyNames.add(name);
    changed = true;
  }
  return changed;
}

/// 指纹覆盖记录的持久化与轮换触发、开关的存取 —— 见 smart_params_store.dart
/// （需要 shared_preferences，与纯逻辑分开，逻辑层保持零依赖可独立测试）。

