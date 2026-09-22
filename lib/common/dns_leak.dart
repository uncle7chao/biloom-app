import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:fl_clash/common/network.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter/foundation.dart';

typedef HostLookup = Future<List<InternetAddress>> Function(String host);

/// 走**操作系统解析器**的域名查询。
///
/// 这里刻意用 `InternetAddress.lookup`（底层是 `getaddrinfo`）：它问的就是系统配的那个
/// DNS 服务器，也就是「不认系统代理的程序」实际会走的那条路 —— 正是 DNS 泄露要测的路径。
/// 抽成可替换的变量是为了能在测试里注入假结果，不必依赖真实网络。
///
/// 这个 seam 放在本文件而不是 `network.dart`：`@visibleForTesting` 只允许**同一个库**
/// 内使用，放别处会让本文件读它就是一条警告。
@visibleForTesting
HostLookup lookupHosts = (host) => InternetAddress.lookup(host);

/// 用于「系统解析路径有没有经过内核」探测的域名池。
///
/// 两个约束决定了这个池子：
/// 1. 必须**肯定不在** `fake-ip-filter` 里 —— 那些域名本来就会被内核放行成真实地址，
///    拿它们探测会把「内核接管正常」测成「没接管」。`example.com` 这类保留域名不会
///    出现在任何一份 filter 里。
/// 2. 必须**每次随机挑、且挑两个** —— Windows 的 DNS 客户端会缓存结果。若固定用一个
///    域名，用户先在系统代理模式下测一次（缓存了真实 IP），再切到 TUN 重测，
///    系统会直接把缓存里的真实 IP 还回来，于是「已经接管了」被误报成「没接管」。
///    每次换域名、且要求两个域名的结论一致，就把这个假阴性压掉了：缓存不可能刚好
///    覆盖到本次随机挑中的那两个。
const dnsProbeHostPool = <String>[
  'example.com',
  'example.org',
  'example.net',
  'www.iana.org',
];

/// 探测本身必须有上界。系统解析器在 DNS 服务器无响应时可能**永久挂起**，
/// 没有这个超时，界面就会一直停在「检测中」上。
const dnsProbeTimeout = Duration(seconds: 8);

enum DnsTakeoverOutcome {
  /// 返回了 fake-ip 段里的地址 —— 这次查询是内核答的。
  takenOver,

  /// 返回了真实地址 —— 这次查询没经过内核。
  notTakenOver,

  /// 判定条件不成立：只有 fake-ip 模式才谈得上「用返回地址判断是否被接管」。
  /// `redir-host` 模式下内核自己把域名解析成真实 IP 再返回，和「没接管」长得一模一样，
  /// 所以这里必须老实说「测不了」，而不是给一个会误导的结论。
  notApplicable,

  /// 查询失败。区别于 notTakenOver：一个是「问到了，答的人不是内核」，
  /// 一个是「根本没问到」，两句不能混为一谈。
  failed,
}

class DnsTakeoverProbeResult {
  const DnsTakeoverProbeResult({
    required this.outcome,
    required this.hosts,
    required this.addresses,
  });

  final DnsTakeoverOutcome outcome;
  final List<String> hosts;

  /// 命中的地址。取「首个判为 fake-ip 的地址」，否则取第一个真实地址。
  final List<String> addresses;

  String? get sampleAddress => addresses.isEmpty ? null : addresses.first;
}

/// 走系统解析器问几个域名，看回答来自内核还是来自真实上游。
///
/// 判定依据只有一条：**内核在 fake-ip 模式下回答任何域名都会给 fake-ip 段里的地址**。
/// 所以「拿到真实公网 IP」就等于「这次查询没有到内核手上」。
Future<DnsTakeoverProbeResult> probeSystemDnsTakeover({
  required DnsMode enhancedMode,
  required String fakeIpRange,
  List<String>? hosts,
  Random? random,
}) async {
  final probeHosts = hosts ?? _pickProbeHosts(random ?? Random());
  if (enhancedMode != DnsMode.fakeIp) {
    return DnsTakeoverProbeResult(
      outcome: DnsTakeoverOutcome.notApplicable,
      hosts: probeHosts,
      addresses: const [],
    );
  }
  final fakeIpAddresses = <String>[];
  final realAddresses = <String>[];
  var answered = false;
  for (final host in probeHosts) {
    final addresses = await _lookup(host);
    if (addresses.isEmpty) {
      continue;
    }
    answered = true;
    for (final address in addresses) {
      if (isIPv4InCidr(address, fakeIpRange)) {
        fakeIpAddresses.add(address);
      } else {
        realAddresses.add(address);
      }
    }
  }
  if (!answered) {
    return DnsTakeoverProbeResult(
      outcome: DnsTakeoverOutcome.failed,
      hosts: probeHosts,
      addresses: const [],
    );
  }
  // 只要有任何一个地址落在 fake-ip 段，就足以证明查询到过内核 ——
  // 真实上游不可能返回运营商手里根本不存在的地址段。
  if (fakeIpAddresses.isNotEmpty) {
    return DnsTakeoverProbeResult(
      outcome: DnsTakeoverOutcome.takenOver,
      hosts: probeHosts,
      addresses: fakeIpAddresses,
    );
  }
  return DnsTakeoverProbeResult(
    outcome: DnsTakeoverOutcome.notTakenOver,
    hosts: probeHosts,
    addresses: realAddresses,
  );
}

Future<List<String>> _lookup(String host) async {
  try {
    final addresses = await lookupHosts(host).timeout(dnsProbeTimeout);
    return addresses.map((address) => address.address).toList();
  } catch (_) {
    // 单个域名失败不算失败 —— 换下一个。整个池子都问不到才算 failed。
    return const [];
  }
}

List<String> _pickProbeHosts(Random random) {
  final pool = List<String>.from(dnsProbeHostPool);
  pool.shuffle(random);
  final count = pool.length < 2 ? pool.length : 2;
  return pool.take(count).toList();
}
