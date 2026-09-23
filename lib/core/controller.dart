import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/core/interface.dart';
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

  Future<String> validateConfigWithData(String data) async {
    final path = await appPath.tempFilePath;
    final file = File(path);
    await file.safeWriteAsString(data);
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

  FutureOr<String> changeProxy(ChangeProxyParams changeProxyParams) async {
    return await _interface.changeProxy(changeProxyParams);
  }

  Future<List<TrackerInfo>> getConnections() async {
    return _interface.getConnections();
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

  Future<String> updateExternalProvider({required String providerName}) async {
    return _interface.updateExternalProvider(providerName);
  }

  Future<bool> startListener() async {
    return _interface.startListener();
  }

  Future<bool> stopListener() async {
    return _interface.stopListener();
  }

  Future<Delay?> getDelay(String url, String proxyName) async {
    return _interface.asyncTestDelay(url, proxyName);
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

  Future<Map<String, dynamic>> getConfig(int id) async {
    final profilePath = await appPath.getProfilePath(id.toString());
    final data = Map<String, dynamic>.from(
      await _interface.getConfig(profilePath),
    );
    data['rules'] = data['rule'];
    data.remove('rule');
    return data;
  }

  Future<Traffic> getTraffic(bool onlyStatisticsProxy) async {
    return _interface.getTraffic(onlyStatisticsProxy);
  }

  Future<Traffic> getTotalTraffic(bool onlyStatisticsProxy) async {
    return _interface.getTotalTraffic(onlyStatisticsProxy);
  }

  Future<int> getMemory() async {
    return _interface.getMemory();
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
