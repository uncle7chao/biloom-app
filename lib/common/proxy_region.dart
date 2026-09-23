/// 出口地区识别 —— 从**节点名**里认出「这个节点落在哪儿」。
///
/// 为什么需要它：订阅给的节点名几乎没有规范。实测一个真实订阅（269 个节点）分三类：
///
/// | 类型 | 数量 | 命名样例 | 地区线索 |
/// |---|---|---|---|
/// | 机场专线 | 90 | `移动-HKG-443-WS-TLS`、`电信-SIN-443-xhttp-02` | ✅ 机场三字码 |
/// | 国家码节点 | 25 | `US-443-WS-TLS`、`SG-443-Trojan-WS-TLS` | ✅ 国家码 |
/// | CF 中转 | ~110 | `bestcf.top-443-WS-TLS`、`cf.0sm.com-443-xhttp` | ❌ 只有域名 |
///
/// 用户在代理页看到的就是这一长串，光靠名字分不清谁是谁 —— 这就是这个模块要解决的。
///
/// ## ⛔ 两条硬规矩
///
/// **1. 只认名字，绝不查 IP。** CF 中转节点的域名解析出来是 Cloudflare 边缘 IP
/// （实测 `c.ali88.site → 104.21.3.153`、`bestcf.top → 104.17.30.233`），
/// 拿它查 GeoIP 只会得到「美国」—— 那是 CF 边缘节点的位置，跟节点真实落地
/// 毫无关系。**猜错了比不标更糟**：用户会照着错的标签去挑节点。
///
/// **2. 按分隔符切成 token 精确匹配，不做子串匹配。** 节点名里到处都是能撞上
/// 国家码的子串（`c.ali88.site` 含 `in`、`bestcf.top` 含 `to`），子串匹配会
/// 立刻误判成印度、汤加。地区码与机场码因此**只认全大写的独立 token** ——
/// 真实订阅里它们就是大写（`US-443`、`移动-HKG-443`），而域名部分基本全小写，
/// 天然隔开。中文地区名（`香港`）没有大小写也无词边界，只能子串匹配，
/// 所以单独放在前面按关键字走。
library;

/// 国家/地区码 → 国旗 emoji。
///
/// 原理就是两个 regional indicator：`H()`变成 U+1F1ED、`K` 变成 U+1F1F0，
/// 拼起来即 🇭🇰。仪表盘的网络检测原先自己实现了一份（`network_detection.dart`），
/// 那里已改为调用本函数 —— 同一件事写两遍，早晚会分叉。
String countryCodeToEmoji(String code) {
  final upper = code.toUpperCase();
  if (upper.length != 2) {
    return code;
  }
  final first = upper.codeUnitAt(0);
  final second = upper.codeUnitAt(1);
  const letterA = 0x41;
  const letterZ = 0x5A;
  if (first < letterA ||
      first > letterZ ||
      second < letterA ||
      second > letterZ) {
    return code;
  }
  return String.fromCharCodes([
    0x1F1E6 + first - letterA,
    0x1F1E6 + second - letterA,
  ]);
}

enum ProxyRegionKind {
  /// 认出了具体国家/地区（`HK` / `US` / `SG` …）。
  country,

  /// 认得出是 Cloudflare 中转节点，但**认不出落地** —— 名字里只有 CF 域名。
  /// 这类节点真实出口可能是任何地方，标了就是编。
  cdn,

  /// 完全没有线索（`c.ali88.site`、`原生地址-443-WS-TLS` 这种）。
  unknown,
}

/// 一个节点的出口地区。
///
/// 刻意做成不可变值对象 + 常量实例：卡片上每个节点都要算一次，
/// 而且要做相等比较以便 Riverpod family 缓存。
class ProxyRegion {
  static const cdn = ProxyRegion._(ProxyRegionKind.cdn, '');
  static const unknown = ProxyRegion._(ProxyRegionKind.unknown, '');

  final ProxyRegionKind kind;

  /// ISO 3166-1 alpha-2 码，仅 [ProxyRegionKind.country] 时有值。
  final String code;

  const ProxyRegion._(this.kind, this.code);

  /// `country` 分支只能经这里构造 —— 顺手挡掉空码，避免造出「有国家但没码」的怪东西。
  static ProxyRegion? ofCountry(String code) {
    final normalized = code.trim().toUpperCase();
    if (normalized.length != 2 || !_countryCodes.contains(normalized)) {
      return null;
    }
    return ProxyRegion._(ProxyRegionKind.country, normalized);
  }

  bool get isCountry => kind == ProxyRegionKind.country;
  bool get isCdn => kind == ProxyRegionKind.cdn;
  bool get isUnknown => kind == ProxyRegionKind.unknown;

  /// CF 中转在分桶/筛选里的固定标识。它不是国家码，但需要一个稳定的键。
  static const cdnKey = 'cdn';

  /// 稳定的身份标识：国家用 ISO 码，CF 中转固定 `cdn`，认不出为空串。
  ///
  /// **不随界面语言变化** —— 它会被存进筛选状态、用来比对「这个节点是不是
  /// 我要的那个地区」。界面语言一变就换一套键的话，用户切一次语言筛选就失效了。
  String get key => switch (kind) {
    ProxyRegionKind.country => code,
    ProxyRegionKind.cdn => cdnKey,
    ProxyRegionKind.unknown => '',
  };

  String get emoji => switch (kind) {
    ProxyRegionKind.country => countryCodeToEmoji(code),
    ProxyRegionKind.cdn => '☁️',
    ProxyRegionKind.unknown => '❔',
  };

  @override
  bool operator ==(Object other) =>
      other is ProxyRegion && other.kind == kind && other.code == code;

  @override
  int get hashCode => Object.hash(kind, code);

  @override
  String toString() => switch (kind) {
    ProxyRegionKind.country => 'ProxyRegion($code)',
    ProxyRegionKind.cdn => 'ProxyRegion(cdn)',
    ProxyRegionKind.unknown => 'ProxyRegion(unknown)',
  };
}

/// 节点名的分隔符。`.` 也在内 —— 域名要按点切开，否则 `cf.0sm.com` 整个是一个 token，
/// 里面的机场码就认不出来了。
final _tokenSeparators = RegExp(r'[-_.\s/|,;:+()[\]{}@#]+');

/// 从节点名认出地区。
///
/// 顺序是有讲究的（从最可靠到最宽松）：
/// 1. 名字里自带的国旗 emoji（正规订阅这么写，最准）；
/// 2. 中文地区名（`香港`、`台湾`）；
/// 3. 英文地区全名（`Hong Kong`、`Japan`，只收长度 ≥ 4 的，避免短词误伤）；
/// 4. 全大写 token 里的机场三字码（`HKG` / `LAX` / `SIN`）；
/// 5. 全大写 token 里的国家码（`US` / `SG`）；
/// 6. 都认不出，但看得出是 Cloudflare 中转 → [ProxyRegion.cdn]；
/// 7. 真的什么都不知道 → [ProxyRegion.unknown]。
ProxyRegion resolveProxyRegion(String proxyName) {
  if (proxyName.trim().isEmpty) {
    return ProxyRegion.unknown;
  }

  final flagCode = _findFlagCode(proxyName);
  if (flagCode != null) {
    final region = ProxyRegion.ofCountry(flagCode);
    if (region != null) {
      return region;
    }
  }

  for (final entry in _chineseRegionNames.entries) {
    if (proxyName.contains(entry.key)) {
      final region = ProxyRegion.ofCountry(entry.value);
      if (region != null) {
        return region;
      }
    }
  }

  final lower = proxyName.toLowerCase();
  for (final entry in _englishRegionNames.entries) {
    if (lower.contains(entry.key)) {
      final region = ProxyRegion.ofCountry(entry.value);
      if (region != null) {
        return region;
      }
    }
  }

  for (final token in proxyName.split(_tokenSeparators)) {
    // ⛔ 只认全大写。小写 token 基本都是域名片段（`.com`、`.site`、`.top`），
    // 放进来就会把 `to`（汤加）、`in`（印度）当地区码用。
    if (token.isEmpty || token != token.toUpperCase()) {
      continue;
    }
    if (_ignoredTokens.contains(token)) {
      continue;
    }
    final airportCode = _airportCodes[token];
    if (airportCode != null) {
      final region = ProxyRegion.ofCountry(airportCode);
      if (region != null) {
        return region;
      }
    }
    if (_countryCodes.contains(token)) {
      final region = ProxyRegion.ofCountry(token);
      if (region != null) {
        return region;
      }
    }
  }

  if (_looksLikeCloudflare(proxyName)) {
    return ProxyRegion.cdn;
  }

  return ProxyRegion.unknown;
}

/// 名字里直接带了国旗（两个 regional indicator 拼成的 emoji）。
String? _findFlagCode(String text) {
  final runes = text.runes.toList();
  for (var i = 0; i + 1 < runes.length; i++) {
    final first = runes[i];
    final second = runes[i + 1];
    const base = 0x1F1E6;
    if (first >= base &&
        first <= base + 25 &&
        second >= base &&
        second <= base + 25) {
      return String.fromCharCodes([0x41 + first - base, 0x41 + second - base]);
    }
  }
  return null;
}

/// 认得出是 Cloudflare 中转 —— 只看名字。**只是「像」，不是「确定」**：
/// 所以这里只影响「标不标 CF 中转」这个中性标签，绝不拿它当地区用。
bool _looksLikeCloudflare(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('cloudflare') ||
      lower.contains('bestcf') ||
      lower.contains('cfip') ||
      lower.contains('cfcdn')) {
    return true;
  }
  // `cf.0sm.com` / `cf.090227.xyz` 这类以 cf 作子域前缀的。
  return RegExp(r'(^|[-_.\s/])cf[-_.\s/]').hasMatch(lower);
}

/// 协议/传输/运营商词。这些**恰好也是国家码**，必须挡掉，否则：
/// `WS`（WebSocket）→ 萨摩亚、`SS`（Shadowsocks）→ 南苏丹、`CF`（Cloudflare）→ 中非。
const _ignoredTokens = {
  'WS',
  'WSS',
  'SS',
  'SSR',
  'TLS',
  'HTTP',
  'HTTPS',
  'H2',
  'H3',
  'GRPC',
  'XHTTP',
  'VMESS',
  'VLESS',
  'TROJAN',
  'REALITY',
  'XTLS',
  'SNI',
  'CDN',
  'CF',
  'IP',
  'IPV4',
  'IPV6',
  'DNS',
  'UDP',
  'TCP',
  'TFO',
  'UOT',
  'BGP',
  'IEPL',
  'IPLC',
  'GIA',
  'CN2',
  'SMTP',
  'FTP',
  'API',
  'URL',
  'UUID',
  'AND',
  'THE',
  'NEW',
  'PRO',
  'MAX',
  'VIP',
  'APP',
  'DEV',
  'NET',
  'ORG',
  'COM',
  'SITE',
  'ONLINE',
  'INFO',
  'LINK',
  'LIVE',
  'CLUB',
  'SPACE',
};

/// 机场三字码 → 国家/地区码。
///
/// 节点名里的机场码是**最可靠的城市级线索** —— 运营商专线普遍这么写
/// （`联通-LAX-443-WS-TLS`）。覆盖主流中转落地，不求穷尽：
/// 认不出会落到「其他」，不会猜错。
const _airportCodes = <String, String>{
  // 港澳台
  'HKG': 'HK', 'MFM': 'MO', 'TPE': 'TW', 'TSA': 'TW', 'KHH': 'TW', 'RMQ': 'TW',
  // 日韩
  'NRT': 'JP', 'HND': 'JP', 'KIX': 'JP', 'NGO': 'JP', 'FUK': 'JP', 'CTS': 'JP',
  'OKA': 'JP', 'ICN': 'KR', 'GMP': 'KR', 'PUS': 'KR', 'CJU': 'KR',
  // 东南亚
  'SIN': 'SG', 'BKK': 'TH', 'DMK': 'TH', 'KUL': 'MY', 'CGK': 'ID', 'DPS': 'ID',
  'MNL': 'PH', 'CEB': 'PH', 'HAN': 'VN', 'SGN': 'VN', 'PNH': 'KH', 'RGN': 'MM',
  // 南亚 / 中亚 / 中东
  'DEL': 'IN', 'BOM': 'IN', 'BLR': 'IN', 'MAA': 'IN', 'CCU': 'IN',
  'DXB': 'AE', 'AUH': 'AE', 'SHJ': 'AE', 'DOH': 'QA', 'RUH': 'SA', 'JED': 'SA',
  'KWI': 'KW', 'TLV': 'IL', 'IST': 'TR', 'SAW': 'TR', 'THR': 'IR', 'AMM': 'JO',
  'ALA': 'KZ', 'TAS': 'UZ',
  // 北美
  'LAX': 'US', 'SJC': 'US', 'SFO': 'US', 'SEA': 'US', 'PDX': 'US', 'DEN': 'US',
  'DFW': 'US', 'ORD': 'US', 'MSP': 'US', 'ATL': 'US', 'MIA': 'US', 'IAD': 'US',
  'EWR': 'US', 'JFK': 'US', 'BOS': 'US', 'PHX': 'US', 'LAS': 'US', 'SLC': 'US',
  'SAN': 'US', 'HNL': 'US', 'ANC': 'US', 'IAH': 'US', 'DTW': 'US', 'PHL': 'US',
  'YYZ': 'CA', 'YVR': 'CA', 'YUL': 'CA', 'YYC': 'CA', 'MEX': 'MX',
  // 欧洲
  'LHR': 'GB', 'LGW': 'GB', 'MAN': 'GB', 'EDI': 'GB',
  'CDG': 'FR', 'ORY': 'FR', 'MRS': 'FR',
  'FRA': 'DE', 'MUC': 'DE', 'BER': 'DE', 'DUS': 'DE', 'HAM': 'DE',
  'AMS': 'NL', 'BRU': 'BE', 'ZRH': 'CH', 'GVA': 'CH', 'VIE': 'AT',
  'MAD': 'ES', 'BCN': 'ES', 'FCO': 'IT', 'MXP': 'IT', 'MIL': 'IT',
  'ARN': 'SE', 'OSL': 'NO', 'CPH': 'DK', 'HEL': 'FI',
  'WAW': 'PL', 'PRG': 'CZ', 'BUD': 'HU', 'OTP': 'RO', 'SOF': 'BG',
  'ATH': 'GR', 'LIS': 'PT', 'DUB': 'IE', 'LUX': 'LU', 'MLA': 'MT',
  'SVO': 'RU', 'LED': 'RU', 'DME': 'RU', 'KBP': 'UA', 'MSQ': 'BY',
  'BEG': 'RS', 'ZAG': 'HR', 'TLL': 'EE', 'RIX': 'LV', 'VNO': 'LT',
  'KEF': 'IS', 'TBS': 'GE',
  // 大洋洲
  'SYD': 'AU', 'MEL': 'AU', 'BNE': 'AU', 'PER': 'AU', 'ADL': 'AU', 'AKL': 'NZ',
  // 南美
  'GRU': 'BR', 'GIG': 'BR', 'EZE': 'AR', 'SCL': 'CL', 'BOG': 'CO', 'LIM': 'PE',
  // 非洲
  'JNB': 'ZA', 'CPT': 'ZA', 'CAI': 'EG', 'LOS': 'NG', 'NBO': 'KE',
  // 中国内地
  'PEK': 'CN', 'PKX': 'CN', 'PVG': 'CN', 'SHA': 'CN', 'CAN': 'CN', 'SZX': 'CN',
  'CTU': 'CN', 'TFU': 'CN', 'HGH': 'CN', 'NKG': 'CN', 'WUH': 'CN', 'XIY': 'CN',
  'CKG': 'CN', 'TSN': 'CN', 'TAO': 'CN', 'XMN': 'CN',
};

/// 认得出的国家/地区码。与 [ProxyRegion.ofCountry] 的白名单是同一份 ——
/// 识别得出但取不到名字的码（没进 l10n 词条）不该输出，否则卡片上会出现裸码。
const _countryCodes = <String>{
  // 大中华区。港澳台一律带「中国」前缀，见 l10n 词条。
  'CN', 'HK', 'MO', 'TW',
  'US', 'CA', 'MX', 'BR', 'AR', 'CL', 'CO', 'PE',
  'GB', 'IE', 'FR', 'DE', 'NL', 'BE', 'LU', 'CH', 'AT', 'IT', 'ES', 'PT',
  'SE', 'NO', 'DK', 'FI', 'IS', 'PL', 'CZ', 'SK', 'HU', 'RO', 'BG', 'GR',
  'HR', 'SI', 'RS', 'EE', 'LV', 'LT', 'MD', 'UA', 'BY', 'RU',
  'GE', 'AM', 'AZ', 'KZ', 'UZ', 'TR', 'CY', 'MT',
  'JP', 'KR', 'SG', 'MY', 'TH', 'VN', 'PH', 'ID', 'KH', 'MM', 'LA',
  'IN', 'PK', 'BD', 'LK', 'NP',
  'AE', 'SA', 'QA', 'KW', 'BH', 'OM', 'IL', 'JO', 'IR',
  'AU', 'NZ',
  'ZA', 'EG', 'NG', 'KE', 'MA',
};

/// 中文地区名 → 地区码。中文没有词边界，只能子串匹配；表里只放**不会被
/// 别的词撞上**的名字（比如不放「中」，只放「中国」）。
const _chineseRegionNames = <String, String>{
  '香港': 'HK',
  '澳门': 'MO',
  '台湾': 'TW',
  '中國': 'CN',
  '中国': 'CN',
  '美国': 'US',
  '加拿大': 'CA',
  '墨西哥': 'MX',
  '巴西': 'BR',
  '阿根廷': 'AR',
  '英国': 'GB',
  '爱尔兰': 'IE',
  '法国': 'FR',
  '德国': 'DE',
  '荷兰': 'NL',
  '比利时': 'BE',
  '瑞士': 'CH',
  '奥地利': 'AT',
  '意大利': 'IT',
  '西班牙': 'ES',
  '葡萄牙': 'PT',
  '瑞典': 'SE',
  '挪威': 'NO',
  '丹麦': 'DK',
  '芬兰': 'FI',
  '冰岛': 'IS',
  '波兰': 'PL',
  '捷克': 'CZ',
  '匈牙利': 'HU',
  '罗马尼亚': 'RO',
  '保加利亚': 'BG',
  '希腊': 'GR',
  '俄罗斯': 'RU',
  '乌克兰': 'UA',
  '土耳其': 'TR',
  '塞浦路斯': 'CY',
  '日本': 'JP',
  '韩国': 'KR',
  '新加坡': 'SG',
  '马来西亚': 'MY',
  '泰国': 'TH',
  '越南': 'VN',
  '菲律宾': 'PH',
  '印度尼西亚': 'ID',
  '印尼': 'ID',
  '柬埔寨': 'KH',
  '缅甸': 'MM',
  '印度': 'IN',
  '巴基斯坦': 'PK',
  '孟加拉': 'BD',
  '斯里兰卡': 'LK',
  '阿联酋': 'AE',
  '迪拜': 'AE',
  '沙特': 'SA',
  '卡塔尔': 'QA',
  '科威特': 'KW',
  '以色列': 'IL',
  '约旦': 'JO',
  '伊朗': 'IR',
  '澳大利亚': 'AU',
  '澳洲': 'AU',
  '新西兰': 'NZ',
  '南非': 'ZA',
  '埃及': 'EG',
  '尼日利亚': 'NG',
  '肯尼亚': 'KE',
  '哈萨克斯坦': 'KZ',
  '格鲁吉亚': 'GE',
  '塞尔维亚': 'RS',
  '摩尔多瓦': 'MD',
};

/// 英文地区全名 → 地区码。只收 **长度 ≥ 4** 的：
/// `US` / `IN` / `TO` 这类短词在域名里满地都是，收进来就是给误判开门。
const _englishRegionNames = <String, String>{
  'hong kong': 'HK',
  'hongkong': 'HK',
  'macao': 'MO',
  'macau': 'MO',
  'taiwan': 'TW',
  'china': 'CN',
  'united states': 'US',
  'america': 'US',
  'canada': 'CA',
  'mexico': 'MX',
  'brazil': 'BR',
  'argentina': 'AR',
  'england': 'GB',
  'britain': 'GB',
  'united kingdom': 'GB',
  'ireland': 'IE',
  'france': 'FR',
  'germany': 'DE',
  'netherlands': 'NL',
  'belgium': 'BE',
  'switzerland': 'CH',
  'austria': 'AT',
  'italy': 'IT',
  'spain': 'ES',
  'portugal': 'PT',
  'sweden': 'SE',
  'norway': 'NO',
  'denmark': 'DK',
  'finland': 'FI',
  'iceland': 'IS',
  'poland': 'PL',
  'czech': 'CZ',
  'hungary': 'HU',
  'romania': 'RO',
  'bulgaria': 'BG',
  'greece': 'GR',
  'russia': 'RU',
  'ukraine': 'UA',
  'turkey': 'TR',
  'japan': 'JP',
  'korea': 'KR',
  'singapore': 'SG',
  'malaysia': 'MY',
  'thailand': 'TH',
  'vietnam': 'VN',
  'philippines': 'PH',
  'indonesia': 'ID',
  'cambodia': 'KH',
  'myanmar': 'MM',
  'india': 'IN',
  'pakistan': 'PK',
  'emirates': 'AE',
  'dubai': 'AE',
  'qatar': 'QA',
  'israel': 'IL',
  'australia': 'AU',
  'zealand': 'NZ',
  'africa': 'ZA',
  'egypt': 'EG',
  'nigeria': 'NG',
  'kenya': 'KE',
};

/// 地区码 → 四语言显示名。
///
/// **港澳台一律带「中国」前缀**（`中国香港` / `中国澳门` / `中国台湾`）——
/// 它们是中国的一部分，节点列表里也一样，不能写成独立国家。英文用
/// `Hong Kong, China` 这种属格形式。
///
/// 这份表的键必须与 [_countryCodes] 完全一致：识别得出却叫不出名字的码，
/// 会让卡片上出现一个裸码（`XX`），比不标还糟。`test/common/proxy_region_test.dart`
/// 里有一条用例专门钉这件事。
typedef RegionNames = ({String zh, String en, String ja, String ru});

const _regionNames = <String, RegionNames>{
  // 大中华区
  'CN': (zh: '中国', en: 'China', ja: '中国', ru: 'Китай'),
  'HK': (zh: '中国香港', en: 'Hong Kong, China', ja: '中国香港', ru: 'Гонконг, Китай'),
  'MO': (zh: '中国澳门', en: 'Macao, China', ja: '中国マカオ', ru: 'Макао, Китай'),
  'TW': (zh: '中国台湾', en: 'Taiwan, China', ja: '中国台湾', ru: 'Тайвань, Китай'),
  // 美洲
  'US': (zh: '美国', en: 'United States', ja: 'アメリカ', ru: 'США'),
  'CA': (zh: '加拿大', en: 'Canada', ja: 'カナダ', ru: 'Канада'),
  'MX': (zh: '墨西哥', en: 'Mexico', ja: 'メキシコ', ru: 'Мексика'),
  'BR': (zh: '巴西', en: 'Brazil', ja: 'ブラジル', ru: 'Бразилия'),
  'AR': (zh: '阿根廷', en: 'Argentina', ja: 'アルゼンチン', ru: 'Аргентина'),
  'CL': (zh: '智利', en: 'Chile', ja: 'チリ', ru: 'Чили'),
  'CO': (zh: '哥伦比亚', en: 'Colombia', ja: 'コロンビア', ru: 'Колумбия'),
  'PE': (zh: '秘鲁', en: 'Peru', ja: 'ペルー', ru: 'Перу'),
  // 西欧 / 南欧
  'GB': (zh: '英国', en: 'United Kingdom', ja: 'イギリス', ru: 'Великобритания'),
  'IE': (zh: '爱尔兰', en: 'Ireland', ja: 'アイルランド', ru: 'Ирландия'),
  'FR': (zh: '法国', en: 'France', ja: 'フランス', ru: 'Франция'),
  'DE': (zh: '德国', en: 'Germany', ja: 'ドイツ', ru: 'Германия'),
  'NL': (zh: '荷兰', en: 'Netherlands', ja: 'オランダ', ru: 'Нидерланды'),
  'BE': (zh: '比利时', en: 'Belgium', ja: 'ベルギー', ru: 'Бельгия'),
  'LU': (zh: '卢森堡', en: 'Luxembourg', ja: 'ルクセンブルク', ru: 'Люксембург'),
  'CH': (zh: '瑞士', en: 'Switzerland', ja: 'スイス', ru: 'Швейцария'),
  'AT': (zh: '奥地利', en: 'Austria', ja: 'オーストリア', ru: 'Австрия'),
  'IT': (zh: '意大利', en: 'Italy', ja: 'イタリア', ru: 'Италия'),
  'ES': (zh: '西班牙', en: 'Spain', ja: 'スペイン', ru: 'Испания'),
  'PT': (zh: '葡萄牙', en: 'Portugal', ja: 'ポルトガル', ru: 'Португалия'),
  'GR': (zh: '希腊', en: 'Greece', ja: 'ギリシャ', ru: 'Греция'),
  'CY': (zh: '塞浦路斯', en: 'Cyprus', ja: 'キプロス', ru: 'Кипр'),
  'MT': (zh: '马耳他', en: 'Malta', ja: 'マルタ', ru: 'Мальта'),
  'TR': (zh: '土耳其', en: 'Türkiye', ja: 'トルコ', ru: 'Турция'),
  // 北欧
  'SE': (zh: '瑞典', en: 'Sweden', ja: 'スウェーデン', ru: 'Швеция'),
  'NO': (zh: '挪威', en: 'Norway', ja: 'ノルウェー', ru: 'Норвегия'),
  'DK': (zh: '丹麦', en: 'Denmark', ja: 'デンマーク', ru: 'Дания'),
  'FI': (zh: '芬兰', en: 'Finland', ja: 'フィンランド', ru: 'Финляндия'),
  'IS': (zh: '冰岛', en: 'Iceland', ja: 'アイスランド', ru: 'Исландия'),
  // 中东欧
  'PL': (zh: '波兰', en: 'Poland', ja: 'ポーランド', ru: 'Польша'),
  'CZ': (zh: '捷克', en: 'Czechia', ja: 'チェコ', ru: 'Чехия'),
  'SK': (zh: '斯洛伐克', en: 'Slovakia', ja: 'スロバキア', ru: 'Словакия'),
  'HU': (zh: '匈牙利', en: 'Hungary', ja: 'ハンガリー', ru: 'Венгрия'),
  'RO': (zh: '罗马尼亚', en: 'Romania', ja: 'ルーマニア', ru: 'Румыния'),
  'BG': (zh: '保加利亚', en: 'Bulgaria', ja: 'ブルガリア', ru: 'Болгария'),
  'HR': (zh: '克罗地亚', en: 'Croatia', ja: 'クロアチア', ru: 'Хорватия'),
  'SI': (zh: '斯洛文尼亚', en: 'Slovenia', ja: 'スロベニア', ru: 'Словения'),
  'RS': (zh: '塞尔维亚', en: 'Serbia', ja: 'セルビア', ru: 'Сербия'),
  'EE': (zh: '爱沙尼亚', en: 'Estonia', ja: 'エストニア', ru: 'Эстония'),
  'LV': (zh: '拉脱维亚', en: 'Latvia', ja: 'ラトビア', ru: 'Латвия'),
  'LT': (zh: '立陶宛', en: 'Lithuania', ja: 'リトアニア', ru: 'Литва'),
  'MD': (zh: '摩尔多瓦', en: 'Moldova', ja: 'モルドバ', ru: 'Молдова'),
  // 东欧 / 高加索 / 中亚
  'UA': (zh: '乌克兰', en: 'Ukraine', ja: 'ウクライナ', ru: 'Украина'),
  'BY': (zh: '白俄罗斯', en: 'Belarus', ja: 'ベラルーシ', ru: 'Беларусь'),
  'RU': (zh: '俄罗斯', en: 'Russia', ja: 'ロシア', ru: 'Россия'),
  'GE': (zh: '格鲁吉亚', en: 'Georgia', ja: 'ジョージア', ru: 'Грузия'),
  'AM': (zh: '亚美尼亚', en: 'Armenia', ja: 'アルメニア', ru: 'Армения'),
  'AZ': (zh: '阿塞拜疆', en: 'Azerbaijan', ja: 'アゼルバイジャン', ru: 'Азербайджан'),
  'KZ': (zh: '哈萨克斯坦', en: 'Kazakhstan', ja: 'カザフスタン', ru: 'Казахстан'),
  'UZ': (zh: '乌兹别克斯坦', en: 'Uzbekistan', ja: 'ウズベキスタン', ru: 'Узбекистан'),
  // 东亚 / 东南亚
  'JP': (zh: '日本', en: 'Japan', ja: '日本', ru: 'Япония'),
  'KR': (zh: '韩国', en: 'South Korea', ja: '韓国', ru: 'Южная Корея'),
  'SG': (zh: '新加坡', en: 'Singapore', ja: 'シンガポール', ru: 'Сингапур'),
  'MY': (zh: '马来西亚', en: 'Malaysia', ja: 'マレーシア', ru: 'Малайзия'),
  'TH': (zh: '泰国', en: 'Thailand', ja: 'タイ', ru: 'Таиланд'),
  'VN': (zh: '越南', en: 'Vietnam', ja: 'ベトナム', ru: 'Вьетнам'),
  'PH': (zh: '菲律宾', en: 'Philippines', ja: 'フィリピン', ru: 'Филиппины'),
  'ID': (zh: '印度尼西亚', en: 'Indonesia', ja: 'インドネシア', ru: 'Индонезия'),
  'KH': (zh: '柬埔寨', en: 'Cambodia', ja: 'カンボジア', ru: 'Камбоджа'),
  'MM': (zh: '缅甸', en: 'Myanmar', ja: 'ミャンマー', ru: 'Мьянма'),
  'LA': (zh: '老挝', en: 'Laos', ja: 'ラオス', ru: 'Лаос'),
  // 南亚
  'IN': (zh: '印度', en: 'India', ja: 'インド', ru: 'Индия'),
  'PK': (zh: '巴基斯坦', en: 'Pakistan', ja: 'パキスタン', ru: 'Пакистан'),
  'BD': (zh: '孟加拉', en: 'Bangladesh', ja: 'バングラデシュ', ru: 'Бангладеш'),
  'LK': (zh: '斯里兰卡', en: 'Sri Lanka', ja: 'スリランカ', ru: 'Шри-Ланка'),
  'NP': (zh: '尼泊尔', en: 'Nepal', ja: 'ネパール', ru: 'Непал'),
  // 中东
  'AE': (zh: '阿联酋', en: 'United Arab Emirates', ja: 'アラブ首長国連邦', ru: 'ОАЭ'),
  'SA': (
    zh: '沙特阿拉伯',
    en: 'Saudi Arabia',
    ja: 'サウジアラビア',
    ru: 'Саудовская Аравия',
  ),
  'QA': (zh: '卡塔尔', en: 'Qatar', ja: 'カタール', ru: 'Катар'),
  'KW': (zh: '科威特', en: 'Kuwait', ja: 'クウェート', ru: 'Кувейт'),
  'BH': (zh: '巴林', en: 'Bahrain', ja: 'バーレーン', ru: 'Бахрейн'),
  'OM': (zh: '阿曼', en: 'Oman', ja: 'オマーン', ru: 'Оман'),
  'IL': (zh: '以色列', en: 'Israel', ja: 'イスラエル', ru: 'Израиль'),
  'JO': (zh: '约旦', en: 'Jordan', ja: 'ヨルダン', ru: 'Иордания'),
  'IR': (zh: '伊朗', en: 'Iran', ja: 'イラン', ru: 'Иран'),
  // 大洋洲 / 非洲
  'AU': (zh: '澳大利亚', en: 'Australia', ja: 'オーストラリア', ru: 'Австралия'),
  'NZ': (zh: '新西兰', en: 'New Zealand', ja: 'ニュージーランド', ru: 'Новая Зеландия'),
  'ZA': (zh: '南非', en: 'South Africa', ja: '南アフリカ', ru: 'ЮАР'),
  'EG': (zh: '埃及', en: 'Egypt', ja: 'エジプト', ru: 'Египет'),
  'NG': (zh: '尼日利亚', en: 'Nigeria', ja: 'ナイジェリア', ru: 'Нигерия'),
  'KE': (zh: '肯尼亚', en: 'Kenya', ja: 'ケニア', ru: 'Кения'),
  'MA': (zh: '摩洛哥', en: 'Morocco', ja: 'モロッコ', ru: 'Марокко'),
};

/// 取某个地区码在指定语言下的显示名。
///
/// 语言用 ISO 639-1 码（`zh` / `en` / `ja` / `ru`），只看**语言**不看地区
/// （`zh_CN` 与 `zh_TW` 都按中文处理）—— 地区名在这一层不需要分简繁。
/// 认不出的语言按英文兜底：英文名对哪种语言的用户都是可读的。
///
/// 刻意做成**无状态纯函数**而不是 `ProxyRegion.label` 属性：这样 `proxy_region.dart`
/// 不依赖 `AppLocalizations`（也就不拖 Flutter 进来），语言由调用方给。
/// 界面侧用它的是 `ProxyRegionL10n.label`（`lib/common/l10n_labels.dart`）。
String? localizedRegionName(String code, String languageCode) {
  final names = _regionNames[code.toUpperCase()];
  if (names == null) {
    return null;
  }
  final normalized = languageCode.toLowerCase();
  return switch (normalized) {
    final value when value.startsWith('zh') => names.zh,
    final value when value.startsWith('ja') => names.ja,
    final value when value.startsWith('ru') => names.ru,
    _ => names.en,
  };
}

/// 一个地区 + 落在它下面的节点名（保持传入顺序）。
///
/// 只装名字不装 `Proxy`：这个结构要能脱离 Flutter 单测，而 `Proxy` 属于 models
/// 层。调用方拿到名字后自己回查。
class ProxyRegionGroup {
  const ProxyRegionGroup({required this.region, required this.proxyNames});

  final ProxyRegion region;
  final List<String> proxyNames;

  int get count => proxyNames.length;
}

/// 分桶结果。**认不出地区的节点也在 [groups] 里**（`ProxyRegion.unknown` 那一桶），
/// 只是永远排在最后。
///
/// 为什么不把它们单独拎出去：界面上每一个节点都该有一个可达的入口。把认不出的
/// 那堆藏起来，用户在地区筛选里就永远看不到它们 —— 224 个真实节点里有 34 个认不出，
/// 那可不是小数目。保留一个「其他」桶，认不出也照样能点进去看。
class ProxyRegionBuckets {
  const ProxyRegionBuckets(this.groups);

  static const empty = ProxyRegionBuckets(<ProxyRegionGroup>[]);

  /// 顺序即展示顺序：节点多的地区在前，认不出地区的桶永远最后。
  final List<ProxyRegionGroup> groups;

  /// 认不出地区的那个桶，没有就是 `null`。
  ProxyRegionGroup? get unknownGroup {
    for (final group in groups) {
      if (group.region.isUnknown) {
        return group;
      }
    }
    return null;
  }

  int get total => groups.fold(0, (sum, group) => sum + group.count);

  bool get isEmpty => groups.isEmpty;

  ProxyRegionGroup? groupOf(String key) {
    for (final group in groups) {
      if (group.region.key == key) {
        return group;
      }
    }
    return null;
  }
}

/// 按地区把节点名分桶 —— 「地区筛选」与「按地区分组」共用的同一份口径。
///
/// 排序：**节点多的地区在前**，数量相同按地区码升序，**认不出地区的固定最后**。
/// 筛选栏上先出现的就应该是节点最多、最可能被点的那个；用地区码兜底是为了同数量时
/// 顺序**稳定**，否则每次重建都可能换位，芯片会自己跳。「其他」放最后是因为它不是一个
/// 地区，它只是「剩下这些」，排在具体地区之后才读得通。
///
/// 名字先按**首次出现顺序**去重：同一批节点常在多个策略组里重复出现
/// （`GLOBAL` + 自己的组），不去重会把数量夸大。
ProxyRegionBuckets groupProxyNamesByRegion(Iterable<String> proxyNames) {
  final seen = <String>{};
  final counters = <String, ProxyRegionGroup>{};
  for (final name in proxyNames) {
    if (!seen.add(name)) {
      continue;
    }
    final region = resolveProxyRegion(name);
    final group = counters[region.key] ??= ProxyRegionGroup(
      region: region,
      proxyNames: <String>[],
    );
    group.proxyNames.add(name);
  }
  final groups = counters.values.toList()
    ..sort((a, b) {
      if (a.region.isUnknown != b.region.isUnknown) {
        return a.region.isUnknown ? 1 : -1;
      }
      final byCount = b.count.compareTo(a.count);
      if (byCount != 0) {
        return byCount;
      }
      return a.region.key.compareTo(b.region.key);
    });
  return ProxyRegionBuckets(groups);
}

/// 把一个筛选键收敛到「这组节点里真有的地区」，不成立就返回 `null`（= 不筛）。
///
/// 为什么需要这一步：筛选状态比节点列表活得久。用户选过「中国香港」之后，
/// 订阅一更新、香港节点一个不剩，若还照着旧键过滤，他会看到一片空白，
/// 而筛选栏上根本没有那一项 —— 无从恢复，只能以为这一页坏了。
/// **收敛成「不筛」比「筛出空」诚实。**
String? resolveEffectiveRegionFilter({
  required ProxyRegionBuckets buckets,
  required String? key,
}) {
  if (key == null) {
    return null;
  }
  return buckets.groupOf(key) == null ? null : key;
}

/// 已有策略组的最小投影 —— 只取判断所需字段。
///
/// 不直接用 `ProxyGroup`：那是 models 层（拖 Flutter），而这一段「哪些组是
/// 我们生成的」的判定必须能脱离 Flutter 单测 —— 它决定的是会不会**删掉用户
/// 自己的分组**，是全功能里最不该靠手感的一段。
class ExistingRegionGroup {
  const ExistingRegionGroup({
    required this.name,
    required this.proxyNames,
    this.hasProviderSource = false,
  });

  final String name;
  final List<String> proxyNames;

  /// 用了 `use:`（代理集合）的分组**一律不碰**：它的节点来自 provider，
  /// 组名认不认得出地区都与我们无关。
  final bool hasProviderSource;
}

/// 这个分组像不像「按地区分组」生成出来的。
///
/// 三条同时满足才算（宁漏不误杀）：
/// 1. 组名认得出地区；
/// 2. 没有 `use:`；
/// 3. 成员非空，且**每一个**成员认出的地区都与组名一致。
///
/// 第 3 条是防误删的关键：用户自建的「🇭🇰 香港节点」如果混进了日本节点，就不算
/// 我们的，既不重写也不删除。反过来说，一个名字叫香港、成员全是香港节点的组 ——
/// 哪怕当初是手建的，把它刷成「当前所有香港节点」也正是他要的。
bool looksLikeGeneratedRegionGroup(ExistingRegionGroup group) {
  if (group.hasProviderSource) {
    return false;
  }
  final region = resolveProxyRegion(group.name);
  if (region.isUnknown) {
    return false;
  }
  if (group.proxyNames.isEmpty) {
    return false;
  }
  for (final name in group.proxyNames) {
    if (resolveProxyRegion(name).key != region.key) {
      return false;
    }
  }
  return true;
}

/// 计划里的一条：这个地区要写成哪个组、装哪些节点。
class RegionGroupDraft {
  const RegionGroupDraft({
    required this.region,
    required this.name,
    required this.proxyNames,
    this.existingName,
  });

  final ProxyRegion region;

  /// 目标组名（由调用方按当前界面语言给出）。
  final String name;

  final List<String> proxyNames;

  /// 命中的现有组名。非空表示**已有这个地区的组**，要复用它（可能同时是改名 ——
  /// 用户换过界面语言时组名会变，`ProxyGroups.put` 会连带把引用它的规则一起改名）。
  final String? existingName;

  bool get isUpdate => existingName != null;
}

/// 「按地区生成分组」的预演结果。
///
/// 先算出**会发生什么**再让用户点确认：这个动作会动到用户配置里真正生效的那份
/// 策略组，不能点下去才知道。
class RegionGroupPlan {
  const RegionGroupPlan({
    required this.upserts,
    required this.removals,
    required this.unknownCount,
  });

  static const empty = RegionGroupPlan(
    upserts: <RegionGroupDraft>[],
    removals: <String>[],
    unknownCount: 0,
  );

  /// 要创建/更新的组。
  final List<RegionGroupDraft> upserts;

  /// 要移除的旧组名 —— 它们引用的节点已经不在配置里，留着会让**整份配置加载失败**。
  final List<String> removals;

  /// 认不出地区、不会归组的节点数。
  final int unknownCount;

  int get createdCount => upserts.where((draft) => !draft.isUpdate).length;

  int get updatedCount => upserts.where((draft) => draft.isUpdate).length;

  int get groupedNodeCount =>
      upserts.fold(0, (sum, draft) => sum + draft.proxyNames.length);

  bool get isEmpty => upserts.isEmpty && removals.isEmpty;
}

/// 算出「按地区生成分组」要做什么。**纯函数**：不落盘、不碰数据库。
///
/// - [nodeNames]：这份配置里真实存在的节点名（从配置解析，不是从运行中的内核）；
/// - [existingGroups]：当前自定义分组（覆写数据里的那份）；
/// - [nameOf]：地区 → 组名。语言相关，由调用方注入，本文件保持无语言状态。
///
/// 「其他」桶**不生成分组**：认不出地区的那一堆不是一个地区，给它在配置里造一个
/// `其他` 组只会让规则里多一个语义不清的目标（界面上的「其他」芯片照样能筛到它们）。
RegionGroupPlan buildRegionGroupPlan({
  required Iterable<String> nodeNames,
  required List<ExistingRegionGroup> existingGroups,
  required String Function(ProxyRegion region) nameOf,
}) {
  final buckets = groupProxyNamesByRegion(nodeNames);
  final claimed = <String>{};
  final upserts = <RegionGroupDraft>[];
  for (final bucket in buckets.groups) {
    if (bucket.region.isUnknown) {
      continue;
    }
    final name = nameOf(bucket.region);
    ExistingRegionGroup? hit = _matchByName(existingGroups, name, claimed);
    hit ??= _matchByRegion(existingGroups, bucket.region.key, claimed);
    if (hit != null) {
      claimed.add(hit.name);
    }
    upserts.add(
      RegionGroupDraft(
        region: bucket.region,
        name: name,
        proxyNames: bucket.proxyNames,
        existingName: hit?.name,
      ),
    );
  }
  final currentKeys = <String>{
    for (final bucket in buckets.groups)
      if (!bucket.region.isUnknown) bucket.region.key,
  };
  final removals = <String>[];
  for (final group in existingGroups) {
    if (claimed.contains(group.name) || !looksLikeGeneratedRegionGroup(group)) {
      continue;
    }
    if (currentKeys.contains(resolveProxyRegion(group.name).key)) {
      continue;
    }
    removals.add(group.name);
  }
  return RegionGroupPlan(
    upserts: upserts,
    removals: removals,
    unknownCount: buckets.unknownGroup?.count ?? 0,
  );
}

ExistingRegionGroup? _matchByName(
  List<ExistingRegionGroup> groups,
  String name,
  Set<String> claimed,
) {
  for (final group in groups) {
    if (group.name == name &&
        !claimed.contains(group.name) &&
        looksLikeGeneratedRegionGroup(group)) {
      return group;
    }
  }
  return null;
}

/// 名字对不上时退一步按**地区**找：用户换过界面语言的话，组名会停在旧语言，
/// 只按名字找就会另建一个组、把旧的留成孤儿。
ExistingRegionGroup? _matchByRegion(
  List<ExistingRegionGroup> groups,
  String key,
  Set<String> claimed,
) {
  for (final group in groups) {
    if (claimed.contains(group.name) || !looksLikeGeneratedRegionGroup(group)) {
      continue;
    }
    if (resolveProxyRegion(group.name).key == key) {
      return group;
    }
  }
  return null;
}

/// 供测试遍历：[_countryCodes] 与 [_regionNames] 的键必须一一对应。
const knownRegionCodes = _countryCodes;
