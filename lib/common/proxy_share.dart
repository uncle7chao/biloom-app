/// 节点分享：把配置里的一个节点条目编码成标准分享链接。
///
/// 方向与内核的 convert 包相反 —— 内核只管「链接 → 节点」，这里做
/// 「节点 → 链接」，各协议的字段映射按 mihomo 的配置键与 V2rayN 的
/// 分享链接约定逐一对照。不认识的协议返回 null，调用方退回「复制
/// 节点内容」（JSON 是 YAML 1.2 的子集，「添加节点」的粘贴框直接认）。
///
/// 数据来源是 `readProfileTargets` 的 nodes（profile YAML 里 proxies 段的
/// 完整参数），不是内核运行时 API —— 后者只有 name/type，编码不出链接。
library;

import 'dart:convert';

/// 支持生成分享链接的协议。其它（tuic/wireguard/ssr/ssh/anytls/…）暂不支持。
const kShareableProxyTypes = {
  'ss',
  'vmess',
  'vless',
  'trojan',
  'hysteria2',
  'socks5',
  'http',
};

bool isShareableProxyType(String type) =>
    kShareableProxyTypes.contains(type.toLowerCase());

/// 把节点条目编码成分享链接。不支持的协议（或缺 server/port 这类必要字段）
/// 返回 null。
String? proxyToShareLink(Map<String, dynamic> node) {
  final type = _str(node['type']).toLowerCase();
  final server = _str(node['server']);
  final port = _int(node['port']);
  if (server.isEmpty || port == null || port <= 0) {
    return null;
  }
  switch (type) {
    case 'ss':
      return _encodeSs(node, server, port);
    case 'vmess':
      return _encodeVmess(node, server, port);
    case 'vless':
      return _encodeVless(node, server, port);
    case 'trojan':
      return _encodeTrojan(node, server, port);
    case 'hysteria2':
      return _encodeHysteria2(node, server, port);
    case 'socks5':
    case 'http':
      return _encodePlainHttp(node, server, port, type);
    default:
      return null;
  }
}

// ---------------------------------------------------------------------------
// 各协议编码
// ---------------------------------------------------------------------------

/// ss：SIP002 —— `ss://base64url(method:password)@host:port?plugin=…#name`。
String _encodeSs(Map<String, dynamic> node, String server, int port) {
  final userinfo = _b64UrlNoPad(
    '${_str(node['cipher'])}:${_str(node['password'])}',
  );
  final query = <String, String>{};
  final pluginOpts = _map(node['plugin-opts']);
  if (pluginOpts.isNotEmpty) {
    final parts = <String>[
      _str(node['plugin']),
      'obfs=${_str(pluginOpts['mode'])}',
      if (pluginOpts['host'] != null) 'obfs-host=${_str(pluginOpts['host'])}',
      if (pluginOpts['path'] != null) 'obfs-uri=${_str(pluginOpts['path'])}',
    ];
    query['plugin'] = parts.where((part) => part.isNotEmpty).join(';');
  }
  return _composeUri(
    scheme: 'ss',
    userInfo: userinfo,
    host: server,
    port: port,
    queryParameters: query.isEmpty ? null : query,
    fragment: _str(node['name']),
  );
}

/// vmess：`vmess://base64(json)`，V2rayN v2 载荷。
String _encodeVmess(Map<String, dynamic> node, String server, int port) {
  final network = _networkOf(node);
  final wsOpts = _map(node['ws-opts']);
  final grpcOpts = _map(node['grpc-opts']);
  final h2Opts = _map(node['h2-opts']);
  final alpn = _stringList(node['alpn']);
  final payload = jsonEncode({
    'v': '2',
    'ps': _str(node['name']),
    'add': server,
    'port': port.toString(),
    'id': _str(node['uuid']),
    'aid': (_int(node['alterId']) ?? 0).toString(),
    'scy': _str(node['cipher']),
    'net': network,
    'type': 'none',
    'host': switch (network) {
      'ws' => _str(_map(wsOpts['headers'])['Host']),
      'h2' => _stringList(h2Opts['host']).join(','),
      _ => '',
    },
    'path': switch (network) {
      'ws' => _str(wsOpts['path']),
      'h2' => _str(h2Opts['path']),
      'grpc' => _str(grpcOpts['grpc-service-name']),
      _ => '',
    },
    'tls': node['tls'] == true ? 'tls' : '',
    'sni': _str(node['servername']),
    'alpn': alpn.join(','),
    'fp': _str(node['client-fingerprint']),
  });
  return 'vmess://${base64.encode(utf8.encode(payload))}';
}

/// vless：`vless://uuid@host:port?…#name`。
String _encodeVless(Map<String, dynamic> node, String server, int port) {
  final realityOpts = _map(node['reality-opts']);
  final hasReality = realityOpts.isNotEmpty;
  final hasTls = node['tls'] == true || hasReality;
  final query = <String, String>{
    'encryption': 'none',
    if (_str(node['flow']).isNotEmpty) 'flow': _str(node['flow']),
    'security': hasReality ? 'reality' : (hasTls ? 'tls' : 'none'),
    if (_str(node['servername']).isNotEmpty)
      'sni': _str(node['servername']),
    if (hasReality) ...{
      'pbk': _str(realityOpts['public-key']),
      'sid': _str(realityOpts['short-id']),
    },
    if (_str(node['client-fingerprint']).isNotEmpty)
      'fp': _str(node['client-fingerprint']),
    ..._transportParams(node),
    if (_stringList(node['alpn']).isNotEmpty)
      'alpn': _stringList(node['alpn']).join(','),
  };
  return _composeUri(
    scheme: 'vless',
    userInfo: _str(node['uuid']),
    host: server,
    port: port,
    queryParameters: query,
    fragment: _str(node['name']),
  );
}

/// trojan：`trojan://password@host:port?…#name`。
String _encodeTrojan(Map<String, dynamic> node, String server, int port) {
  final query = <String, String>{
    'security': 'tls',
    if (_str(node['sni']).isNotEmpty) 'sni': _str(node['sni']),
    ..._transportParams(node),
    if (_stringList(node['alpn']).isNotEmpty)
      'alpn': _stringList(node['alpn']).join(','),
    if (_str(node['client-fingerprint']).isNotEmpty)
      'fp': _str(node['client-fingerprint']),
    if (node['skip-cert-verify'] == true) 'allowInsecure': '1',
  };
  return _composeUri(
    scheme: 'trojan',
    userInfo: _str(node['password']),
    host: server,
    port: port,
    queryParameters: query,
    fragment: _str(node['name']),
  );
}

/// hysteria2：`hysteria2://auth@host:port?…#name`。
String _encodeHysteria2(Map<String, dynamic> node, String server, int port) {
  final query = <String, String>{
    if (_str(node['sni']).isNotEmpty) 'sni': _str(node['sni']),
    if (_stringList(node['alpn']).isNotEmpty)
      'alpn': _stringList(node['alpn']).join(','),
    if (_str(node['obfs']).isNotEmpty) ...{
      'obfs': _str(node['obfs']),
      if (_str(node['obfs-password']).isNotEmpty)
        'obfs-password': _str(node['obfs-password']),
    },
    if (node['skip-cert-verify'] == true) 'insecure': '1',
  };
  return _composeUri(
    scheme: 'hysteria2',
    userInfo: _str(node['password']),
    host: server,
    port: port,
    queryParameters: query.isEmpty ? null : query,
    fragment: _str(node['name']),
  );
}

/// socks5 / http：`scheme://[user:pass@]host:port#name`。
String _encodePlainHttp(
  Map<String, dynamic> node,
  String server,
  int port,
  String type,
) {
  final user = _str(node['username']);
  final password = _str(node['password']);
  return _composeUri(
    scheme: type,
    userInfo: user.isEmpty ? null : '$user:$password',
    host: server,
    port: port,
    fragment: _str(node['name']),
  );
}

/// 传输层参数（type/host/path/serviceName），vless 与 trojan 共用。
Map<String, String> _transportParams(Map<String, dynamic> node) {
  final network = _networkOf(node);
  final wsOpts = _map(node['ws-opts']);
  final grpcOpts = _map(node['grpc-opts']);
  return {
    'type': network,
    if (network == 'ws') ...{
      'host': _str(_map(wsOpts['headers'])['Host']),
      'path': _str(wsOpts['path']),
    },
    if (network == 'grpc')
      'serviceName': _str(grpcOpts['grpc-service-name']),
    if (network == 'httpupgrade') ...{
      'host': _str(_map(node['httpupgrade-opts'])['host']),
      'path': _str(_map(node['httpupgrade-opts'])['path']),
    },
  };
}

// ---------------------------------------------------------------------------
// 小工具
// ---------------------------------------------------------------------------

/// 带 userinfo 的 URI 统一入口。
///
/// Dart 的 [Uri] 构造器对 userInfo 里的 `@` 直接抛 FormatException（`@` 是
/// userinfo 的分隔符），而 trojan/hysteria2 的密码、socks 的口令恰好经常
/// 含 `@`。这里先用构造器生成不带 userinfo 的部分，再把最小化编码后的
/// userinfo 手动拼回去 —— parse 回来即得原文。
String _composeUri({
  required String scheme,
  String? userInfo,
  required String host,
  int? port,
  Map<String, String>? queryParameters,
  String? fragment,
}) {
  final rest = Uri(
    scheme: scheme,
    host: host,
    port: port,
    queryParameters: queryParameters,
    fragment: fragment,
  ).toString();
  if (userInfo == null || userInfo.isEmpty) {
    return rest;
  }
  final marker = '$scheme://';
  assert(rest.startsWith(marker));
  return rest.replaceFirst(marker, '$marker${_encodeUserInfo(userInfo)}@');
}

/// userinfo 的 RFC 3986 最小化 percent-encoding。
///
/// 合法集合 = unreserved + sub-delims + `:`，命中原样保留；其余（`@`、`/`、
/// `%`、空格、非 ASCII……）编码。不能用 [Uri.encodeComponent] 全量编码 ——
/// 它会把合法的 `:` 也编成 `%3A`，链接可读性差且部分客户端解析行为不一。
String _encodeUserInfo(String raw) {
  const subDelims = {
    '!', r'$', '&', "'", '(', ')', '*', '+', ',', ';', '=',
  };
  final sb = StringBuffer();
  for (final rune in raw.runes) {
    final ch = String.fromCharCode(rune);
    final code = rune;
    final isUnreserved =
        (code >= 0x41 && code <= 0x5A) || // A-Z
        (code >= 0x61 && code <= 0x7A) || // a-z
        (code >= 0x30 && code <= 0x39) || // 0-9
        ch == '-' ||
        ch == '.' ||
        ch == '_' ||
        ch == '~';
    if (isUnreserved || subDelims.contains(ch) || ch == ':') {
      sb.write(ch);
    } else {
      sb.write(Uri.encodeComponent(ch));
    }
  }
  return sb.toString();
}

String _str(Object? v) => v == null ? '' : v.toString();

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

Map<String, dynamic> _map(Object? v) => v is Map
    ? v.map((key, value) => MapEntry(key.toString(), value))
    : const {};

List<String> _stringList(Object? v) =>
    v is List ? v.map(_str).where((s) => s.isNotEmpty).toList() : const [];

/// mihomo 的 network 字段缺省即 tcp。
String _networkOf(Map<String, dynamic> node) {
  final network = _str(node['network']);
  return network.isEmpty ? 'tcp' : network;
}

String _b64UrlNoPad(String s) =>
    base64Url.encode(utf8.encode(s)).replaceAll('=', '');
