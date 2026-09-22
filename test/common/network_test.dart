import 'dart:io';

import 'package:fl_clash/common/network.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAddress implements InterfaceAddress {
  _FakeAddress(this.address, this.type);

  @override
  final String address;

  @override
  final InternetAddressType type;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInterface implements NetworkInterface {
  _FakeInterface(this.name, this.addresses);

  @override
  final String name;

  @override
  final List<InterfaceAddress> addresses;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

InterfaceAddress _v4(String address) =>
    _FakeAddress(address, InternetAddressType.IPv4);

InterfaceAddress _v6(String address) =>
    _FakeAddress(address, InternetAddressType.IPv6);

void main() {
  tearDown(() {
    listNetworkInterfaces = ({bool includeLoopback = false}) =>
        NetworkInterface.list(includeLoopback: includeLoopback);
  });

  void listing(List<NetworkInterface> interfaces) {
    listNetworkInterfaces = ({bool includeLoopback = false}) async =>
        interfaces;
  }

  group('isWifi', () {
    test('recognises the usual wireless interface names', () {
      for (final name in ['wlan0', 'Wi-Fi', 'WLAN1', 'en0', 'eth0', 'ETH0']) {
        expect(_FakeInterface(name, const []).isWifi, isTrue, reason: name);
      }
    });

    test('does not match an unrelated or suffixed interface', () {
      for (final name in ['en1', 'eth1', 'utun3', 'lo0', '']) {
        expect(_FakeInterface(name, const []).isWifi, isFalse, reason: name);
      }
    });
  });

  test('includesIPv4 only counts IPv4 addresses', () {
    expect(_FakeInterface('en1', [_v4('10.0.0.2')]).includesIPv4, isTrue);
    expect(_FakeInterface('en1', [_v6('fe80::1')]).includesIPv4, isFalse);
    expect(_FakeInterface('en1', const []).includesIPv4, isFalse);
  });

  test('isIPv4 reads the address type', () {
    expect(_v4('10.0.0.2').isIPv4, isTrue);
    expect(_v6('fe80::1').isIPv4, isFalse);
  });

  group('getLocalIpAddress', () {
    test('prefers a wireless interface over a wired one', () async {
      listing([
        _FakeInterface('utun0', [_v4('10.9.0.1')]),
        _FakeInterface('wlan0', [_v4('192.168.1.20')]),
      ]);

      expect(await getLocalIpAddress(), '192.168.1.20');
    });

    test(
      'prefers an IPv4-carrying interface when neither is wireless',
      () async {
        listing([
          _FakeInterface('utun0', [_v6('fe80::1')]),
          _FakeInterface('utun1', [_v4('10.9.0.1')]),
        ]);

        expect(await getLocalIpAddress(), '10.9.0.1');
      },
    );

    test('prefers the IPv4 address inside the chosen interface', () async {
      listing([
        _FakeInterface('wlan0', [_v6('fe80::1'), _v4('192.168.1.20')]),
      ]);

      expect(await getLocalIpAddress(), '192.168.1.20');
    });

    test('skips an interface that carries no address at all', () async {
      listing([
        _FakeInterface('wlan0', const []),
        _FakeInterface('utun0', [_v4('10.9.0.1')]),
      ]);

      expect(await getLocalIpAddress(), '10.9.0.1');
    });

    test('returns an empty string when nothing is listed', () async {
      listing([]);

      expect(await getLocalIpAddress(), '');
    });

    test('never asks for the loopback interface', () async {
      bool? asked;
      listNetworkInterfaces = ({bool includeLoopback = false}) async {
        asked = includeLoopback;
        return [];
      };

      await getLocalIpAddress();

      expect(asked, isFalse);
    });
  });

  group('isIPv4InCidr', () {
    test('matches inside the fake-ip range and rejects just outside it', () {
      // 这一组边界值是整个 DNS 自检的判定依据所在：内核返回 fake-ip 段的地址
      // 就说明查询到过内核。边界算错会把两类结论刚好写反。
      // 注意 198.18.0.1/16 覆盖的是 198.18.0.0–198.18.255.255，隔壁的 198.19.x.x 不在其中。
      for (final address in ['198.18.0.1', '198.18.0.5', '198.18.255.255']) {
        expect(isIPv4InCidr(address, '198.18.0.1/16'), isTrue, reason: address);
      }
      for (final address in ['198.17.255.255', '198.19.0.0', '1.1.1.1']) {
        expect(isIPv4InCidr(address, '198.18.0.1/16'), isFalse, reason: address);
      }
    });

    test('the network address of the range need not be aligned', () {
      // `198.18.0.1/16` 里的主机位必须被掩掉，否则 198.18.x 会被判成不在段内。
      expect(isIPv4InCidr('198.18.200.7', '198.18.0.1/16'), isTrue);
    });

    test('handles other prefix lengths', () {
      expect(isIPv4InCidr('10.1.2.3', '10.0.0.0/8'), isTrue);
      expect(isIPv4InCidr('11.1.2.3', '10.0.0.0/8'), isFalse);
      expect(isIPv4InCidr('223.5.5.5', '223.5.5.5/32'), isTrue);
      expect(isIPv4InCidr('223.5.5.6', '223.5.5.5/32'), isFalse);
      expect(isIPv4InCidr('223.5.5.6', '0.0.0.0/0'), isTrue);
    });

    test('rejects anything that is not a plain IPv4/CIDR pair', () {
      expect(isIPv4InCidr('fe80::1', '198.18.0.1/16'), isFalse);
      expect(isIPv4InCidr('198.18.0.5', '198.18.0.1'), isFalse);
      expect(isIPv4InCidr('198.18.0.5', '198.18.0.1/33'), isFalse);
      expect(isIPv4InCidr('198.18.0.5', '198.18.0.1/x'), isFalse);
      expect(isIPv4InCidr('not-an-address', '198.18.0.1/16'), isFalse);
      expect(isIPv4InCidr('198.18.0.999', '198.18.0.1/16'), isFalse);
      expect(isIPv4InCidr('198.18.0', '198.18.0.1/16'), isFalse);
    });
  });
}
