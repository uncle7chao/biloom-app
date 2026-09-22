import 'dart:io';

import 'package:fl_clash/common/dns_leak.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    lookupHosts = (host) => InternetAddress.lookup(host);
  });

  void answering(Map<String, List<String>> table) {
    lookupHosts = (host) async {
      final addresses = table[host];
      if (addresses == null) {
        throw const SocketException('no such host');
      }
      return addresses.map(InternetAddress.new).toList();
    };
  }

  group('probeSystemDnsTakeover', () {
    test('reports no takeover when the answer is a real address', () async {
      // 这就是「仅系统代理」模式下的预期结果：系统解析器把真实地址还了回来，
      // 说明这次查询根本没有经过内核。
      answering({
        'example.com': ['93.184.216.34'],
        'example.org': ['93.184.216.35'],
      });

      final result = await probeSystemDnsTakeover(
        enhancedMode: DnsMode.fakeIp,
        fakeIpRange: '198.18.0.1/16',
        hosts: ['example.com', 'example.org'],
      );

      expect(result.outcome, DnsTakeoverOutcome.notTakenOver);
      expect(result.addresses, contains('93.184.216.34'));
    });

    test('reports takeover when the answer comes from the fake-ip range', () async {
      answering({
        'example.com': ['198.18.0.5'],
        'example.org': ['198.18.0.6'],
      });

      final result = await probeSystemDnsTakeover(
        enhancedMode: DnsMode.fakeIp,
        fakeIpRange: '198.18.0.1/16',
        hosts: ['example.com', 'example.org'],
      );

      expect(result.outcome, DnsTakeoverOutcome.takenOver);
      expect(result.addresses, contains('198.18.0.5'));
    });

    test('one fake-ip answer is enough to prove the core saw the query', () async {
      // 真实上游不可能返回运营商手里根本不存在的地址段，所以单个命中就是铁证。
      // 反过来，只有一个域名没命中可能只是它被缓存了 —— 所以判定只取「命中即成立」。
      answering({
        'example.com': ['198.18.0.5'],
        'example.org': ['93.184.216.35'],
      });

      final result = await probeSystemDnsTakeover(
        enhancedMode: DnsMode.fakeIp,
        fakeIpRange: '198.18.0.1/16',
        hosts: ['example.com', 'example.org'],
      );

      expect(result.outcome, DnsTakeoverOutcome.takenOver);
    });

    test('honours a custom fake-ip range', () async {
      answering({
        'example.com': ['10.99.0.2'],
      });

      final result = await probeSystemDnsTakeover(
        enhancedMode: DnsMode.fakeIp,
        fakeIpRange: '10.99.0.0/16',
        hosts: ['example.com'],
      );

      expect(result.outcome, DnsTakeoverOutcome.takenOver);
    });

    test('refuses to judge in redir-host mode', () async {
      // redir-host 下内核自己把域名解析成真实 IP 再返回，和「没接管」长得一模一样。
      // 这里必须说「判不了」，而不是给出一个会误导的结论 —— 顺带也不该发起任何查询。
      var lookedUp = false;
      lookupHosts = (host) async {
        lookedUp = true;
        return [InternetAddress('93.184.216.34')];
      };

      final result = await probeSystemDnsTakeover(
        enhancedMode: DnsMode.redirHost,
        fakeIpRange: '198.18.0.1/16',
        hosts: ['example.com'],
      );

      expect(result.outcome, DnsTakeoverOutcome.notApplicable);
      expect(lookedUp, isFalse);
      expect(result.addresses, isEmpty);
    });

    test('separates "ask failed" from "asked and got a real answer"', () async {
      answering(const {});

      final result = await probeSystemDnsTakeover(
        enhancedMode: DnsMode.fakeIp,
        fakeIpRange: '198.18.0.1/16',
        hosts: ['example.com', 'example.org'],
      );

      expect(result.outcome, DnsTakeoverOutcome.failed);
    });

    test('survives one host failing as long as another answers', () async {
      answering({
        'example.org': ['198.18.0.9'],
      });

      final result = await probeSystemDnsTakeover(
        enhancedMode: DnsMode.fakeIp,
        fakeIpRange: '198.18.0.1/16',
        hosts: ['example.com', 'example.org'],
      );

      expect(result.outcome, DnsTakeoverOutcome.takenOver);
    });

    test('always probes more than one pool host so DNS cache cannot fake a result', () async {
      // 固定一个域名的话：用户先在系统代理下测（缓存了真实 IP），再切 TUN 重测，
      // 系统会把缓存里的真实 IP 还回来，于是「已接管」被误报成「没接管」。
      answering({
        for (final host in dnsProbeHostPool) host: ['198.18.0.7'],
      });

      final result = await probeSystemDnsTakeover(
        enhancedMode: DnsMode.fakeIp,
        fakeIpRange: '198.18.0.1/16',
      );

      expect(result.hosts, hasLength(2));
      expect(result.hosts.toSet(), hasLength(2));
      expect(result.hosts.every(dnsProbeHostPool.contains), isTrue);
    });
  });
}
