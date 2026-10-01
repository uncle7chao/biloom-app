import 'dart:convert';

import 'package:fl_clash/common/proxy_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('proxyToShareLink ss', () {
    test('SIP002 userinfo is url-safe base64 without padding', () {
      final link = proxyToShareLink({
        'name': '香港 01',
        'type': 'ss',
        'server': '1.2.3.4',
        'port': 8388,
        'cipher': 'aes-128-gcm',
        'password': 'pass/word+1',
      });
      expect(link, isNotNull);
      final uri = Uri.parse(link!);
      expect(uri.scheme, 'ss');
      expect(uri.host, '1.2.3.4');
      expect(uri.port, 8388);
      // SIP002：userinfo = base64url(method:password)，无填充。
      final decoded =
          utf8.decode(base64Url.decode(base64Url.normalize(uri.userInfo)));
      expect(decoded, 'aes-128-gcm:pass/word+1');
      // Dart 的 uri.fragment 返回 percent-encoded 原文，解码后比较。
      expect(Uri.decodeComponent(uri.fragment), '香港 01');
    });

    test('simple-obfs plugin lands in the query', () {
      final link = proxyToShareLink({
        'name': 'node',
        'type': 'ss',
        'server': 'a.com',
        'port': 443,
        'cipher': 'aes-256-gcm',
        'password': 'p',
        'plugin': 'obfs-local',
        'plugin-opts': {'mode': 'http', 'host': 'bing.com'},
      });
      final uri = Uri.parse(link!);
      expect(
        uri.queryParameters['plugin'],
        'obfs-local;obfs=http;obfs-host=bing.com',
      );
    });
  });

  group('proxyToShareLink vmess', () {
    test('payload decodes to the v2 json with ws transport', () {
      final link = proxyToShareLink({
        'name': '美国 02',
        'type': 'vmess',
        'server': '5.6.7.8',
        'port': 1234,
        'uuid': 'b831381d-6324-4d53-ad4f-8cda48b30811',
        'alterId': 0,
        'cipher': 'auto',
        'udp': true,
        'tls': true,
        'servername': 'example.com',
        'network': 'ws',
        'ws-opts': {
          'path': '/ray',
          'headers': {'Host': 'ws.example.com'},
        },
      });
      expect(link!.startsWith('vmess://'), isTrue);
      final payload =
          utf8.decode(base64.decode(link.substring('vmess://'.length)));
      final json = jsonDecode(payload) as Map<String, dynamic>;
      expect(json['ps'], '美国 02');
      expect(json['add'], '5.6.7.8');
      expect(json['port'], '1234');
      expect(json['id'], 'b831381d-6324-4d53-ad4f-8cda48b30811');
      expect(json['aid'], '0');
      expect(json['net'], 'ws');
      expect(json['host'], 'ws.example.com');
      expect(json['path'], '/ray');
      expect(json['tls'], 'tls');
      expect(json['sni'], 'example.com');
    });

    test('defaults to tcp when network is absent', () {
      final link = proxyToShareLink({
        'name': 'n',
        'type': 'vmess',
        'server': 'a.com',
        'port': 1,
        'uuid': 'u',
      });
      final payload =
          utf8.decode(base64.decode(link!.substring('vmess://'.length)));
      expect((jsonDecode(payload) as Map)['net'], 'tcp');
    });
  });

  group('proxyToShareLink vless', () {
    test('reality over tcp carries pbk/sid/fp', () {
      final link = proxyToShareLink({
        'name': 'reality',
        'type': 'vless',
        'server': '9.9.9.9',
        'port': 443,
        'uuid': 'uuid-1',
        'flow': 'xtls-rprx-vision',
        'tls': true,
        'servername': 'www.microsoft.com',
        'client-fingerprint': 'chrome',
        'reality-opts': {'public-key': 'pbk-value', 'short-id': 'abcd'},
      });
      final uri = Uri.parse(link!);
      expect(uri.scheme, 'vless');
      expect(uri.userInfo, 'uuid-1');
      expect(uri.host, '9.9.9.9');
      expect(uri.port, 443);
      expect(uri.queryParameters['encryption'], 'none');
      expect(uri.queryParameters['security'], 'reality');
      expect(uri.queryParameters['flow'], 'xtls-rprx-vision');
      expect(uri.queryParameters['sni'], 'www.microsoft.com');
      expect(uri.queryParameters['pbk'], 'pbk-value');
      expect(uri.queryParameters['sid'], 'abcd');
      expect(uri.queryParameters['fp'], 'chrome');
      expect(uri.queryParameters['type'], 'tcp');
    });

    test('plain ws without tls', () {
      final link = proxyToShareLink({
        'name': 'ws',
        'type': 'vless',
        'server': 'a.com',
        'port': 80,
        'uuid': 'u',
        'network': 'ws',
        'ws-opts': {
          'path': '/vless',
          'headers': {'Host': 'h.com'},
        },
      });
      final uri = Uri.parse(link!);
      expect(uri.queryParameters['security'], 'none');
      expect(uri.queryParameters['type'], 'ws');
      expect(uri.queryParameters['host'], 'h.com');
      expect(uri.queryParameters['path'], '/vless');
    });
  });

  test('trojan keeps password in userinfo and tls in query', () {
    final link = proxyToShareLink({
      'name': 'trojan node',
      'type': 'trojan',
      'server': 't.com',
      'port': 443,
      'password': 'secret@pass',
      'sni': 'sni.com',
      'skip-cert-verify': true,
    });
    final uri = Uri.parse(link!);
    expect(uri.scheme, 'trojan');
    // Dart 的 uri.userInfo 返回 percent-encoded 原文，解码后比较。
    expect(Uri.decodeComponent(uri.userInfo), 'secret@pass');
    expect(uri.host, 't.com');
    expect(uri.queryParameters['security'], 'tls');
    expect(uri.queryParameters['sni'], 'sni.com');
    expect(uri.queryParameters['allowInsecure'], '1');
    expect(Uri.decodeComponent(uri.fragment), 'trojan node');
  });

  test('hysteria2 carries obfs params', () {
    final link = proxyToShareLink({
      'name': 'hy2',
      'type': 'hysteria2',
      'server': 'h.com',
      'port': 8443,
      'password': 'auth',
      'obfs': 'salamander',
      'obfs-password': 'obfsp',
      'sni': 's.com',
    });
    final uri = Uri.parse(link!);
    expect(uri.scheme, 'hysteria2');
    expect(uri.userInfo, 'auth');
    expect(uri.queryParameters['obfs'], 'salamander');
    expect(uri.queryParameters['obfs-password'], 'obfsp');
    expect(uri.queryParameters['sni'], 's.com');
  });

  test('hysteria2 userinfo survives @ and colon in password', () {
    // Dart 的 Uri 构造器对 userInfo 里的 @ 直接抛 FormatException，
    // 这里验证编码器走的是先编码后拼接的通道。
    final link = proxyToShareLink({
      'name': 'hy2',
      'type': 'hysteria2',
      'server': 'h.com',
      'port': 8443,
      'password': 'p@ss:word',
    });
    final uri = Uri.parse(link!);
    expect(uri.userInfo, 'p%40ss:word');
    expect(Uri.decodeComponent(uri.userInfo), 'p@ss:word');
    // 无参数时不残留空 query。
    expect(link.contains('?'), isFalse);
  });

  test('socks5 with credentials', () {
    final link = proxyToShareLink({
      'name': 'socks',
      'type': 'socks5',
      'server': '10.0.0.1',
      'port': 1080,
      'username': 'user',
      'password': 'pass',
    });
    final uri = Uri.parse(link!);
    expect(uri.scheme, 'socks5');
    expect(uri.userInfo, 'user:pass');
  });

  group('unsupported or broken nodes return null', () {
    for (final type in ['tuic', 'wireguard', 'ssr', 'anytls']) {
      test(type, () {
        expect(
          proxyToShareLink({
            'name': 'n',
            'type': type,
            'server': 'a.com',
            'port': 1,
          }),
          isNull,
        );
      });
    }
    test('missing server', () {
      expect(
        proxyToShareLink({'name': 'n', 'type': 'ss', 'port': 1}),
        isNull,
      );
    });
    test('missing port', () {
      expect(
        proxyToShareLink({'name': 'n', 'type': 'ss', 'server': 'a.com'}),
        isNull,
      );
    });
  });
}
