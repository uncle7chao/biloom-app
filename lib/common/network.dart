import 'dart:io';

import 'package:flutter/foundation.dart';

typedef NetworkInterfaceLister =
    Future<List<NetworkInterface>> Function({bool includeLoopback});

@visibleForTesting
NetworkInterfaceLister listNetworkInterfaces =
    ({bool includeLoopback = false}) =>
        NetworkInterface.list(includeLoopback: includeLoopback);

extension NetworkInterfaceExt on NetworkInterface {
  bool get isWifi {
    final nameLowCase = name.toLowerCase();
    if (nameLowCase.contains('wlan') ||
        nameLowCase.contains('wi-fi') ||
        nameLowCase == 'en0' ||
        nameLowCase == 'eth0') {
      return true;
    }

    return false;
  }

  bool get includesIPv4 {
    return addresses.any((addr) => addr.isIPv4);
  }
}

extension InternetAddressExt on InternetAddress {
  bool get isIPv4 {
    return type == InternetAddressType.IPv4;
  }
}

/// 判断一个 IPv4 字面量是否落在 CIDR 里，例如 `('198.18.0.5', '198.18.0.1/16')`。
///
/// 只处理 IPv4：调用方（fake-ip 段判定）面对的就是 IPv4 段，IPv6 一律返回 false，
/// 免得把一个 AAAA 地址误判成命中了 fake-ip 段。
bool isIPv4InCidr(String address, String cidr) {
  final parts = cidr.split('/');
  if (parts.length != 2) {
    return false;
  }
  final prefixLength = int.tryParse(parts[1].trim());
  if (prefixLength == null || prefixLength < 0 || prefixLength > 32) {
    return false;
  }
  final addressValue = _ipv4ToInt(address);
  final networkValue = _ipv4ToInt(parts[0].trim());
  if (addressValue == null || networkValue == null) {
    return false;
  }
  if (prefixLength == 0) {
    return true;
  }
  final mask = (0xFFFFFFFF << (32 - prefixLength)) & 0xFFFFFFFF;
  return (addressValue & mask) == (networkValue & mask);
}

int? _ipv4ToInt(String address) {
  final parts = address.split('.');
  if (parts.length != 4) {
    return null;
  }
  var value = 0;
  for (final part in parts) {
    final octet = int.tryParse(part);
    if (octet == null || octet < 0 || octet > 255) {
      return null;
    }
    value = (value << 8) | octet;
  }
  return value & 0xFFFFFFFF;
}

Future<String?> getLocalIpAddress() async {
  final List<NetworkInterface> interfaces =
      await listNetworkInterfaces(includeLoopback: false)
        ..sort((a, b) {
          if (a.isWifi && !b.isWifi) return -1;
          if (!a.isWifi && b.isWifi) return 1;
          if (a.includesIPv4 && !b.includesIPv4) return -1;
          if (!a.includesIPv4 && b.includesIPv4) return 1;
          return 0;
        });
  for (final interface in interfaces) {
    final addresses = interface.addresses;
    if (addresses.isEmpty) {
      continue;
    }
    addresses.sort((a, b) {
      if (a.isIPv4 && !b.isIPv4) return -1;
      if (!a.isIPv4 && b.isIPv4) return 1;
      return 0;
    });
    return addresses.first.address;
  }
  return '';
}
