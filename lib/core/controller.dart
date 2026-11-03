import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/core/spill.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path/path.dart';

class CoreController {
  static CoreController? _instance;
  late CoreHandlerInterface _interface;

  CoreController._internal() {
    if (system.isAndroid) {
      _interface = coreLib!;
    } else {
      _interface = coreService!;
    }
  }

  @visibleForTesting
  CoreController.test(this._interface) {
    _instance = this;
  }

  @visibleForTesting
  CoreController.scoped(this._interface);

  @visibleForTesting
  static void resetInstance() {
    _instance = null;
  }

  factory CoreController() {
    _instance ??= CoreController._internal();
    return _instance!;
  }

  Future<CoreLifecycleResult> start() => _interface.start();

  Future<CoreLifecycleResult> restart() => _interface.restart();

  Future<CoreLifecycleResult> stop() => _interface.stop();

  Future<CoreLifecycleResult> close() => _interface.close();

  static Future<void> ensureHomeDir() async {
    final homePath = await appPath.homeDirPath;
    final homeDir = Directory(homePath);
    final isExists = await homeDir.exists();
    if (!isExists) {
      await homeDir.create(recursive: true);
    }
    await system.grantHomeDirAccess(homePath);
  }

  static Future<void> initGeo() async {
    final homePath = await appPath.homeDirPath;
    const geoFileNameList = [MMDB, GEOIP, GEOSITE, ASN];
    try {
      for (final geoFileName in geoFileNameList) {
        final geoFile = File(join(homePath, geoFileName));
        final isExists = await geoFile.exists();
        if (isExists) {
          continue;
        }
        final data = await rootBundle.load('assets/data/$geoFileName');
        final List<int> bytes = data.buffer.asUint8List();
        await geoFile.writeAsBytes(bytes, flush: true);
      }
    } catch (e) {
      commonPrint.log(
        'Failed to initialize geo data: $e',
        logLevel: LogLevel.error,
      );
      rethrow;
    }
  }

  Future<bool> init(int version) async {
    await ensureHomeDir();
    await initGeo();
    final homeDirPath = await appPath.homeDirPath;
    return _interface.init(InitParams(homeDir: homeDirPath, version: version));
  }

  FutureOr<bool> get isInit => _interface.isInit;

  Future<String> validateConfig(String path) async {
    final res = await _interface.validateConfig(path);
    return res;
  }

  /// An age-encrypted config is rewritten in place into its plaintext, and a
  /// share-link list into a config of its proxies.
  Future<String> validateProfile(
    String path, [
    String ageSecretKey = '',
  ]) async {
    final file = File(path);
    if (await file.isAgeEncrypted) {
      if (ageSecretKey.isEmpty) {
        throw const AgeSecretKeyRequiredException();
      }
      await file.safeWriteAsString(
        await _interface.decryptConfig(path, ageSecretKey),
      );
    }
    final message = await validateConfig(path);
    if (message.isEmpty) {
      return message;
    }
    final List<Map<String, dynamic>> proxies;
    try {
      proxies = await _interface.convertProxies(path);
    } on Exception {
      return message;
    }
    if (proxies.isEmpty) {
      return message;
    }
    await file.safeWriteAsString(await encodeYamlTask({'proxies': proxies}));
    return validateConfig(path);
  }

  Future<List<String>> validateProxies(List<Map<String, dynamic>> proxies) {
    if (proxies.isEmpty) {
      return Future.value(const []);
    }
    return _interface.validateProxies(proxies);
  }

  Future<List<String>> validateFilters(List<String> filters) {
    if (filters.isEmpty) {
      return Future.value(const []);
    }
    return _interface.validateFilters(filters);
  }

  Future<List<String>> encodeShareLinks(List<Map<String, dynamic>> proxies) {
    if (proxies.isEmpty) {
      return Future.value(const []);
    }
    return _interface.encodeShareLinks(proxies);
  }

  Future<List<List<Map<String, dynamic>>>> decodeShareLinks(
    List<String> lines,
  ) {
    if (lines.isEmpty) {
      return Future.value(const []);
    }
    return _interface.decodeShareLinks(lines);
  }

  Future<String> validateConfigWithData(List<int> data) async {
    final path = await appPath.tempFilePath;
    final file = File(path);
    await file.safeWriteAsBytes(data);
    final res = await _interface.validateConfig(path);
    await File(path).safeDelete();
    return res;
  }

  /// 把任意受支持的订阅内容转换成标准 Clash 配置。
  ///
  /// 转换放在内核里做：内核自带 convert 包（proxy-provider 路径上就在用它），
  /// 已经覆盖 vless/vmess/trojan/ss/ssr/hysteria2/tuic/anytls 以及 ws/grpc/h2/
  /// xhttp/httpupgrade 等传输，自己再写一遍只会跟着内核漂移。
  Future<ConvertSubscriptionResult> convertSubscription(String data) async {
    return _interface.convertSubscription(data);
  }

  /// 往配置里追加节点。
  ///
  /// 分享链接与 YAML 片段共用这一个入口 —— 内核自己判断输入是哪一种，所以调用方
  /// 不需要先让用户选「你要加哪种」，粘贴框只有一个。
  Future<AddProxyNodesResult> addProxyNodes({
    required String yaml,
    required String nodes,
  }) async {
    return _interface.addProxyNodes(yaml: yaml, nodes: nodes);
  }

  /// 从配置里删除节点。引用清理（组员/规则/listeners）在内核同步完成。
  Future<RemoveProxyNodesResult> removeProxyNodes({
    required String yaml,
    required List<String> names,
  }) async {
    return _interface.removeProxyNodes(yaml: yaml, names: names);
  }

  /// 原地更新一个节点的参数。名字是组员/规则/链式引用的锚点，内核不允许
  /// 编辑改名；实现是整体替换 proxies 里那一个条目。
  Future<UpdateProxyNodeResult> updateProxyNode({
    required String yaml,
    required String name,
    required String node,
  }) async {
    return _interface.updateProxyNode(yaml: yaml, name: name, node: node);
  }

  /// 列出这份配置里可以做链式代理的节点与策略组。
  Future<ProfileTargets> readProfileTargets({required String yaml}) async {
    return _interface.readProfileTargets(yaml: yaml);
  }

  /// 给某个节点挂上（[dialer] 非空）或解除（[dialer] 为空）前置代理。
  Future<SetProxyChainResult> setProxyChain({
    required String yaml,
    required String target,
    required String dialer,
  }) async {
    return _interface.setProxyChain(yaml: yaml, target: target, dialer: dialer);
  }

  Future<String> updateConfig(UpdateParams updateParams) async {
    return _interface.updateConfig(updateParams);
  }

  Future<String> setupConfig({
    required SetupParams params,
    Future<void> Function()? preloadInvoke,
  }) async {
    if (preloadInvoke == null) {
      return _interface.setupConfig(params);
    }
    final (result, _) = await (
      _interface.setupConfig(params),
      preloadInvoke(),
    ).wait;
    return result;
  }

  Future<List<Group>> getProxiesGroups({
    required ProxiesSortType sortType,
    required DelayMap delayMap,
    required Map<String, String> selectedMap,
    required String defaultTestUrl,
  }) async {
    final proxiesData = await _interface.getProxies();
    return toGroupsTask(
      ComputeGroupsState(
        proxiesData: proxiesData,
        sortType: sortType,
        delayMap: delayMap,
        selectedMap: selectedMap,
        defaultTestUrl: defaultTestUrl,
      ),
    );
  }

  Future<ChangeProxyResult> changeProxy(ChangeProxyParams changeProxyParams) {
    return _interface.changeProxy(changeProxyParams);
  }

  Future<RouteSnapshot?> watchRoute(bool watch) {
    return _interface.watchRoute(watch);
  }

  Future<RouteCheck?> checkRoutes(CheckRoutesParams params) {
    return _interface.checkRoutes(params);
  }

  Future<List<TrackerInfo>> getConnections() async {
    return _interface.getConnections();
  }

  Future<int> getConnectionCount() async {
    return _interface.getConnectionCount();
  }

  Future<void> closeConnection(String id) async {
    await _interface.closeConnection(id);
  }

  Future<void> closeConnections() async {
    await _interface.closeConnections();
  }

  Future<void> resetConnections() async {
    await _interface.resetConnections();
  }

  Future<bool> clearDnsCache() async {
    return _interface.clearDnsCache();
  }

  Future<List<ExternalProvider>> getExternalProviders() async {
    return _interface.getExternalProviders();
  }

  Future<ExternalProvider?> getExternalProvider(
    String externalProviderName,
  ) async {
    return _interface.getExternalProvider(externalProviderName);
  }

  Future<String> updateGeoData(String type) {
    return _interface.updateGeoData(type);
  }

  Future<String> sideLoadExternalProvider({
    required String providerName,
    required String data,
  }) {
    return _interface.sideLoadExternalProvider(
      providerName: providerName,
      data: data,
    );
  }

  Future<String> dumpRuleSet(String path) {
    return _interface.dumpRuleSet(path);
  }

  Future<RuleSetInfo> compileRuleSet(String name, {String url = ''}) {
    return _interface.compileRuleSet(name, url: url);
  }

  Future<String> updateExternalProvider({required String providerName}) async {
    return _interface.updateExternalProvider(providerName);
  }

  Future<bool> startListener() async {
    return _interface.startListener();
  }

  Future<bool> stopListener() async {
    return _interface.stopListener();
  }

  Future<Delay?> getDelay(
    String url,
    String proxyName,
    Duration timeout,
  ) async {
    return _interface.asyncTestDelay(url, proxyName, timeout);
  }

  /// 「测落地」：见 [CoreInterface.requestProxyIP]。
  Future<({String ip, String country})> requestProxyIP({
    required String proxyName,
    required int timeoutMs,
  }) {
    return _interface.requestProxyIP(
      proxyName: proxyName,
      timeoutMs: timeoutMs,
    );
  }
  Future<ProbeResult?> probe(ProbeParams params) => _interface.probe(params);

  Future<OutboundIpResult?> outboundIp(OutboundIpParams params) =>
      _interface.outboundIp(params);

  Future<List<ServiceCheckItem>> serviceCheck(ServiceCheckParams params) =>
      _interface.serviceCheck(params);

  Future<Map<String, dynamic>> getConfig(int id) async {
    return _readConfig(await appPath.getProfilePath(id.toString()));
  }

  Future<Map<String, dynamic>> _readConfig(String path) async {
    final data = Map<String, dynamic>.from(await _interface.getConfig(path));
    data['rules'] = data['rule'];
    data.remove('rule');
    return data;
  }

  Future<Map<String, dynamic>> getProfileOutbounds(int id) async {
    return _interface.getProfileOutbounds(
      await appPath.getProfilePath(id.toString()),
    );
  }

  Future<Map<String, dynamic>?> getProxyDefinition(String name) {
    return _interface.getProxyDefinition(name);
  }

  Future<String> buildProfile(SetupBase base) async {
    return readSpilledText(await _interface.buildProfile(base));
  }

  Future<({ProfileBase base, String path})> getProfileBase(int id) async {
    final path = await appPath.getProfilePath(id.toString());
    final base = await _interface.getProfileBase(path);
    final config = Map<String, dynamic>.from(base.config)..remove('rule');
    return (base: base.copyWith(config: config), path: path);
  }

  Future<Traffic> getTraffic(bool onlyStatisticsProxy) async {
    return _interface.getTraffic(onlyStatisticsProxy);
  }

  Future<Traffic> getTotalTraffic(bool onlyStatisticsProxy) async {
    return _interface.getTotalTraffic(onlyStatisticsProxy);
  }

  Future<CoreMemoryStats?> getMemoryStats() async {
    return _interface.getMemoryStats();
  }

  void resetTraffic() {
    _interface.resetTraffic();
  }

  void startLog() {
    _interface.startLog();
  }

  void stopLog() {
    _interface.stopLog();
  }

  Future<void> requestGc() async {
    await _interface.forceGc();
  }

  Future<void> crash() async {
    await _interface.crash();
  }

  Future<String> clearEffect(int profileId) async {
    return _interface.clearEffect(profileId);
  }
}

final coreController = CoreController();
