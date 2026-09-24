import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// 手动添加节点的表单。
///
/// 表单只负责「把用户填的字段变成一个节点 JSON」：内核（core/profile_edit.go 的
/// parseProxyNodes）把 JSON 当 YAML 片段解析 —— YAML 1.2 是 JSON 的超集，所以
/// 直接 jsonEncode 即可，Dart 侧不必引入 YAML 写出器。这样重名跳过、自动补默认
/// 分组、名称冲突校验这些既有安全逻辑全部原样生效。
///
/// 字段清单刻意收敛到「V2rayN 表单上真正会出现的那些」：每种协议只放 mihomo
/// 实际读取的字段，传输层相关字段（ws/grpc）只在选了对应传输层时出现，Reality
/// 三件套只在勾了 Reality 时出现 —— 否则表单会长到让用户找不到重点。
class ProxyNodeForm extends StatefulWidget {
  const ProxyNodeForm({super.key});

  @override
  State<ProxyNodeForm> createState() => ProxyNodeFormState();
}

enum _FieldType {
  text,
  password,
  int_,
  bool_,
  dropdown,
}

class _Field {
  final String key;
  final String label;
  final _FieldType type;
  final bool required;

  /// 条件必填（如 hysteria2 的 obfs-password：选了 obfs 就必须填）。
  final bool Function(_FormValues values)? requiredIf;
  final bool advanced;

  /// 伪字段：只作为 UI 输入，不直接写进节点 map（如 ws-path 要折叠进 ws-opts）。
  final bool pseudo;
  final List<String> options;
  final String? initial;
  final bool Function(_FormValues values)? visible;

  const _Field(
    this.key,
    this.label, {
    this.type = _FieldType.text,
    this.required = false,
    this.requiredIf,
    this.advanced = false,
    this.pseudo = false,
    this.options = const [],
    this.initial,
    this.visible,
  });
}

class _Protocol {
  final String type;
  final List<_Field> fields;

  const _Protocol(this.type, this.fields);
}

/// 各输入框当前值的快照，供字段级可见性判断。
class _FormValues {
  final Map<String, String> text;
  final Map<String, bool> bools;

  const _FormValues(this.text, this.bools);

  String textOf(String key) => text[key]?.trim() ?? '';

  bool boolOf(String key) => bools[key] ?? false;
}

class ProxyNodeFormState extends State<ProxyNodeForm> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _bools = {};
  String _type = 'socks5';
  bool _advancedOpen = false;

  static const _ssCiphers = [
    'aes-128-gcm',
    'aes-256-gcm',
    'chacha20-ietf-poly1305',
    'xchacha20-ietf-poly1305',
    '2022-blake3-aes-128-gcm',
    '2022-blake3-aes-256-gcm',
    '2022-blake3-chacha20-poly1305',
  ];

  static const _vmessCiphers = [
    'auto',
    'aes-128-gcm',
    'chacha20-poly1305',
    'none',
  ];

  static const _networks = ['tcp', 'ws', 'grpc'];

  static const _fingerprints = [
    'chrome',
    'firefox',
    'safari',
    'ios',
    'android',
    'edge',
    'random',
  ];

  List<_Protocol> _protocols(AppLocalizations l10n) {
    String l(String key) => _label(l10n, key);
    final common = [
      _Field('name', l('proxyFieldName'), required: true),
      _Field('server', l('proxyFieldServer'), required: true),
      _Field(
        'port',
        l('proxyFieldPort'),
        type: _FieldType.int_,
        required: true,
      ),
    ];
    return [
      _Protocol('socks5', [
        ...common,
        _Field('username', l('proxyFieldUsername')),
        _Field('password', l('proxyFieldPassword'), type: _FieldType.password),
        _Field(
          'tls',
          l('proxyFieldTls'),
          type: _FieldType.bool_,
          advanced: true,
        ),
        _Field(
          'skip-cert-verify',
          l('proxyFieldSkipCertVerify'),
          type: _FieldType.bool_,
          advanced: true,
          visible: (v) => v.boolOf('tls'),
        ),
        _Field('udp', l('proxyFieldUdp'), type: _FieldType.bool_),
      ]),
      _Protocol('http', [
        ...common,
        _Field('username', l('proxyFieldUsername')),
        _Field('password', l('proxyFieldPassword'), type: _FieldType.password),
        _Field('tls', l('proxyFieldTls'), type: _FieldType.bool_),
        _Field(
          'sni',
          l('proxyFieldSni'),
          visible: (v) => v.boolOf('tls'),
        ),
        _Field(
          'skip-cert-verify',
          l('proxyFieldSkipCertVerify'),
          type: _FieldType.bool_,
          advanced: true,
          visible: (v) => v.boolOf('tls'),
        ),
      ]),
      _Protocol('ss', [
        ...common,
        _Field(
          'cipher',
          l('proxyFieldCipher'),
          type: _FieldType.dropdown,
          required: true,
          options: _ssCiphers,
          initial: _ssCiphers.first,
        ),
        _Field('password', l('proxyFieldPassword'), type: _FieldType.password,
            required: true),
        _Field('udp', l('proxyFieldUdp'), type: _FieldType.bool_),
      ]),
      _Protocol('vmess', [
        ...common,
        _Field('uuid', l('proxyFieldUuid'), required: true),
        _Field(
          'alterId',
          l('proxyFieldAlterId'),
          type: _FieldType.int_,
          initial: '0',
        ),
        _Field(
          'cipher',
          l('proxyFieldCipher'),
          type: _FieldType.dropdown,
          options: _vmessCiphers,
          initial: _vmessCiphers.first,
        ),
        _Field('udp', l('proxyFieldUdp'), type: _FieldType.bool_),
        _Field('tls', l('proxyFieldTls'), type: _FieldType.bool_),
        _Field(
          'servername',
          l('proxyFieldSni'),
          visible: (v) => v.boolOf('tls'),
        ),
        _Field(
          'network',
          l('proxyFieldNetwork'),
          type: _FieldType.dropdown,
          options: _networks,
          initial: 'tcp',
        ),
        _Field(
          'ws-path',
          l('proxyFieldWsPath'),
          pseudo: true,
          visible: (v) => v.textOf('network') == 'ws',
        ),
        _Field(
          'ws-host',
          l('proxyFieldWsHost'),
          pseudo: true,
          visible: (v) => v.textOf('network') == 'ws',
        ),
        _Field(
          'grpc-service',
          l('proxyFieldGrpcService'),
          pseudo: true,
          visible: (v) => v.textOf('network') == 'grpc',
        ),
        _Field(
          'skip-cert-verify',
          l('proxyFieldSkipCertVerify'),
          type: _FieldType.bool_,
          advanced: true,
          visible: (v) => v.boolOf('tls'),
        ),
      ]),
      _Protocol('vless', [
        ...common,
        _Field('uuid', l('proxyFieldUuid'), required: true),
        _Field(
          'flow',
          l('proxyFieldFlow'),
          type: _FieldType.dropdown,
          options: ['', 'xtls-rprx-vision'],
          initial: '',
        ),
        _Field('udp', l('proxyFieldUdp'), type: _FieldType.bool_),
        _Field('tls', l('proxyFieldTls'), type: _FieldType.bool_),
        _Field(
          'servername',
          l('proxyFieldSni'),
          visible: (v) => v.boolOf('tls') || v.boolOf('reality'),
        ),
        _Field(
          'reality',
          l('proxyFieldReality'),
          type: _FieldType.bool_,
          advanced: true,
        ),
        _Field(
          'reality-public-key',
          l('proxyFieldPublicKey'),
          pseudo: true,
          advanced: true,
          visible: (v) => v.boolOf('reality'),
        ),
        _Field(
          'reality-short-id',
          l('proxyFieldShortId'),
          pseudo: true,
          advanced: true,
          visible: (v) => v.boolOf('reality'),
        ),
        _Field(
          'client-fingerprint',
          l('proxyFieldFingerprint'),
          type: _FieldType.dropdown,
          options: _fingerprints,
          initial: 'chrome',
          advanced: true,
          visible: (v) => v.boolOf('reality'),
        ),
        _Field(
          'network',
          l('proxyFieldNetwork'),
          type: _FieldType.dropdown,
          options: _networks,
          initial: 'tcp',
        ),
        _Field(
          'ws-path',
          l('proxyFieldWsPath'),
          pseudo: true,
          visible: (v) => v.textOf('network') == 'ws',
        ),
        _Field(
          'ws-host',
          l('proxyFieldWsHost'),
          pseudo: true,
          visible: (v) => v.textOf('network') == 'ws',
        ),
        _Field(
          'grpc-service',
          l('proxyFieldGrpcService'),
          pseudo: true,
          visible: (v) => v.textOf('network') == 'grpc',
        ),
        _Field(
          'skip-cert-verify',
          l('proxyFieldSkipCertVerify'),
          type: _FieldType.bool_,
          advanced: true,
          visible: (v) => v.boolOf('tls') && !v.boolOf('reality'),
        ),
      ]),
      _Protocol('trojan', [
        ...common,
        _Field(
          'password',
          l('proxyFieldPassword'),
          type: _FieldType.password,
          required: true,
        ),
        // ⛔ 内核 TrojanOption/Hysteria2Option 的 SNI 键是 `sni`（vmess/vless 才叫
        // servername）；键名写错会被 structure decoder 静默忽略，填了等于没填。
        _Field('sni', l('proxyFieldSni')),
        _Field('udp', l('proxyFieldUdp'), type: _FieldType.bool_),
        _Field(
          'network',
          l('proxyFieldNetwork'),
          type: _FieldType.dropdown,
          options: _networks,
          initial: 'tcp',
        ),
        _Field(
          'ws-path',
          l('proxyFieldWsPath'),
          pseudo: true,
          visible: (v) => v.textOf('network') == 'ws',
        ),
        _Field(
          'ws-host',
          l('proxyFieldWsHost'),
          pseudo: true,
          visible: (v) => v.textOf('network') == 'ws',
        ),
        _Field(
          'grpc-service',
          l('proxyFieldGrpcService'),
          pseudo: true,
          visible: (v) => v.textOf('network') == 'grpc',
        ),
        _Field(
          'skip-cert-verify',
          l('proxyFieldSkipCertVerify'),
          type: _FieldType.bool_,
          advanced: true,
        ),
      ]),
      _Protocol('hysteria2', [
        ...common,
        _Field(
          'password',
          l('proxyFieldPassword'),
          type: _FieldType.password,
          required: true,
        ),
        // ⛔ 内核 TrojanOption/Hysteria2Option 的 SNI 键是 `sni`（vmess/vless 才叫
        // servername）；键名写错会被 structure decoder 静默忽略，填了等于没填。
        _Field('sni', l('proxyFieldSni')),
        _Field(
          'obfs',
          l('proxyFieldObfs'),
          type: _FieldType.dropdown,
          options: ['', 'salamander'],
          initial: '',
        ),
        _Field(
          'obfs-password',
          l('proxyFieldObfsPassword'),
          // 内核对「选了 obfs 却没给密码」直接报 missing obfs password，
          // 这里提前拦住并给出表单级红字，而不是让内核报错弹窗。
          requiredIf: (v) => v.textOf('obfs').isNotEmpty,
          visible: (v) => v.textOf('obfs').isNotEmpty,
        ),
        _Field(
          'up',
          l('proxyFieldUp'),
          advanced: true,
        ),
        _Field(
          'down',
          l('proxyFieldDown'),
          advanced: true,
        ),
        _Field(
          'skip-cert-verify',
          l('proxyFieldSkipCertVerify'),
          type: _FieldType.bool_,
          advanced: true,
        ),
      ]),
    ];
  }

  static String _label(AppLocalizations l10n, String key) {
    // Dart 的 getter 不能按名字反射取，逐个映射一遍。
    switch (key) {
      case 'proxyFieldName':
        return l10n.proxyFieldName;
      case 'proxyFieldServer':
        return l10n.proxyFieldServer;
      case 'proxyFieldPort':
        return l10n.proxyFieldPort;
      case 'proxyFieldUsername':
        return l10n.proxyFieldUsername;
      case 'proxyFieldPassword':
        return l10n.proxyFieldPassword;
      case 'proxyFieldUuid':
        return l10n.proxyFieldUuid;
      case 'proxyFieldAlterId':
        return l10n.proxyFieldAlterId;
      case 'proxyFieldCipher':
        return l10n.proxyFieldCipher;
      case 'proxyFieldUdp':
        return l10n.proxyFieldUdp;
      case 'proxyFieldTls':
        return l10n.proxyFieldTls;
      case 'proxyFieldSkipCertVerify':
        return l10n.proxyFieldSkipCertVerify;
      case 'proxyFieldNetwork':
        return l10n.proxyFieldNetwork;
      case 'proxyFieldWsPath':
        return l10n.proxyFieldWsPath;
      case 'proxyFieldWsHost':
        return l10n.proxyFieldWsHost;
      case 'proxyFieldGrpcService':
        return l10n.proxyFieldGrpcService;
      case 'proxyFieldSni':
        return l10n.proxyFieldSni;
      case 'proxyFieldFlow':
        return l10n.proxyFieldFlow;
      case 'proxyFieldReality':
        return l10n.proxyFieldReality;
      case 'proxyFieldPublicKey':
        return l10n.proxyFieldPublicKey;
      case 'proxyFieldShortId':
        return l10n.proxyFieldShortId;
      case 'proxyFieldFingerprint':
        return l10n.proxyFieldFingerprint;
      case 'proxyFieldObfs':
        return l10n.proxyFieldObfs;
      case 'proxyFieldObfsPassword':
        return l10n.proxyFieldObfsPassword;
      case 'proxyFieldUp':
        return l10n.proxyFieldUp;
      case 'proxyFieldDown':
        return l10n.proxyFieldDown;
      default:
        return key;
    }
  }

  _Protocol get _current =>
      _protocols(context.appLocalizations).firstWhere((p) => p.type == _type);

  TextEditingController _controller(String key, [_Field? field]) {
    return _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: field?.initial ?? ''),
    );
  }

  bool _boolOf(String key) => _bools.putIfAbsent(key, () => key == 'udp');

  void _switchProtocol(String type) {
    setState(() {
      _type = type;
      _advancedOpen = false;
    });
  }

  /// 校验并生成节点 JSON；校验不过时返回 null（表单内已标红）。
  String? buildNodesJson() {
    if (!_formKey.currentState!.validate()) {
      return null;
    }
    final text = {
      for (final entry in _controllers.entries) entry.key: entry.value.text.trim(),
    };
    final values = _FormValues(text, _bools);
    final protocol = _current;
    final visibleFields = protocol.fields
        .where((field) => field.visible?.call(values) ?? true)
        .toList();

    final node = <String, dynamic>{
      'name': text['name'],
      'type': protocol.type,
      'server': text['server'],
      'port': int.parse(text['port']!),
    };

    void putText(String yamlKey, String key) {
      final value = text[key];
      if (value != null && value.isNotEmpty) {
        node[yamlKey] = value;
      }
    }

    void putBool(String yamlKey, String key) {
      node[yamlKey] = _bools[key] ?? false;
    }

    for (final field in visibleFields) {
      if (field.pseudo) {
        continue;
      }
      switch (field.type) {
        case _FieldType.bool_:
          putBool(field.key, field.key);
          break;
        case _FieldType.int_:
          final value = text[field.key];
          if (value != null && value.isNotEmpty) {
            node[field.key] = int.tryParse(value) ?? value;
          }
          break;
        case _FieldType.dropdown:
          final value = text[field.key] ?? field.initial ?? '';
          if (value.isNotEmpty) {
            node[field.key] = value;
          }
          break;
        default:
          putText(field.key, field.key);
      }
    }

    // 传输层选项是独立的伪字段，要折叠进内核读取的嵌套结构里。
    // 注意 network 只要选了 ws/grpc 就必须写进节点 —— 即使用户没填路径/服务名，
    // 否则节点会静默退回 tcp，用户的选择被无声忽略。
    final network = text['network'] ?? 'tcp';
    if (protocol.type == 'vmess' || protocol.type == 'vless' ||
        protocol.type == 'trojan') {
      if (network == 'ws') {
        node['network'] = 'ws';
        final wsOpts = <String, dynamic>{};
        if (text['ws-path']?.isNotEmpty == true) {
          wsOpts['path'] = text['ws-path'];
        }
        if (text['ws-host']?.isNotEmpty == true) {
          wsOpts['headers'] = {'Host': text['ws-host']};
        }
        if (wsOpts.isNotEmpty) {
          node['ws-opts'] = wsOpts;
        }
      } else if (network == 'grpc') {
        node['network'] = 'grpc';
        if (text['grpc-service']?.isNotEmpty == true) {
          node['grpc-opts'] = {'grpc-service-name': text['grpc-service']};
        }
      }
    }

    if (protocol.type == 'vless') {
      if (_bools['reality'] == true) {
        final realityOpts = <String, dynamic>{};
        if (text['reality-public-key']?.isNotEmpty == true) {
          realityOpts['public-key'] = text['reality-public-key'];
        }
        if (text['reality-short-id']?.isNotEmpty == true) {
          realityOpts['short-id'] = text['reality-short-id'];
        }
        node['reality-opts'] = realityOpts;
        node['tls'] = true;
        if (text['client-fingerprint']?.isNotEmpty == true) {
          node['client-fingerprint'] = text['client-fingerprint'];
        }
      }
    }

    return jsonEncode(node);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final protocol = _current;
    final text = {
      for (final entry in _controllers.entries) entry.key: entry.value.text.trim(),
    };
    final values = _FormValues(text, _bools);
    final visibleFields = protocol.fields
        .where((field) => field.visible?.call(values) ?? true)
        .toList();
    final normal = visibleFields.where((f) => !f.advanced).toList();
    final advanced = visibleFields.where((f) => f.advanced).toList();

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: InputDecoration(
              labelText: l10n.addNodeProtocol,
              border: const OutlineInputBorder(),
            ),
            items: _protocols(l10n)
                .map(
                  (p) => DropdownMenuItem(
                    value: p.type,
                    child: Text(_protocolLabel(p.type)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null && value != _type) {
                _switchProtocol(value);
              }
            },
          ),
          const SizedBox(height: 12),
          ...normal.map((field) => _buildField(field, values)),
          if (advanced.isNotEmpty)
            ExpansionTile(
              initiallyExpanded: _advancedOpen,
              onExpansionChanged: (open) => setState(() => _advancedOpen = open),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                l10n.proxyFormAdvanced,
                style: context.textTheme.bodyMedium,
              ),
              children:
                  advanced.map((field) => _buildField(field, values)).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildField(_Field field, _FormValues values) {
    final l10n = context.appLocalizations;
    switch (field.type) {
      case _FieldType.bool_:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(field.label, style: context.textTheme.bodyMedium),
          value: _boolOf(field.key),
          onChanged: (value) => setState(() => _bools[field.key] = value),
        );
      case _FieldType.dropdown:
        return DropdownButtonFormField<String>(
          initialValue: _controller(field.key, field).text.isEmpty &&
                  (field.initial?.isNotEmpty ?? false)
              ? field.initial
              : _controller(field.key, field).text,
          decoration: InputDecoration(labelText: field.label),
          items: field.options
              .map(
                (option) => DropdownMenuItem(
                  value: option,
                  child: Text(option.isEmpty ? l10n.proxyFormOptionNone : option),
                ),
              )
              .toList(),
          onChanged: (value) =>
              setState(() => _controller(field.key, field).text = value ?? ''),
        );
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
            controller: _controller(field.key, field),
            obscureText: field.type == _FieldType.password,
            keyboardType: field.type == _FieldType.int_
                ? TextInputType.number
                : TextInputType.text,
            inputFormatters: field.type == _FieldType.int_
                ? [FilteringTextInputFormatter.digitsOnly]
                : null,
            decoration: InputDecoration(
              labelText: field.label +
                  ((field.required || field.requiredIf != null) ? ' *' : ''),
              border: const OutlineInputBorder(),
            ),
            validator: (value) {
              final required =
                  field.required || (field.requiredIf?.call(values) ?? false);
              if (required && (value == null || value.trim().isEmpty)) {
                return l10n.proxyFormMissingRequired;
              }
              if (field.type == _FieldType.int_ &&
                  value != null &&
                  value.trim().isNotEmpty &&
                  int.tryParse(value.trim()) == null) {
                return l10n.proxyFormMissingRequired;
              }
              return null;
            },
          ),
        );
    }
  }
}

String _protocolLabel(String type) {
  switch (type) {
    case 'ss':
      return 'Shadowsocks';
    default:
      return type.toUpperCase();
  }
}
