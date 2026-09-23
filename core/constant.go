package main

import (
	"github.com/metacubex/mihomo/adapter/provider"
	P "github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"net/netip"
	"time"
)

type InitParams struct {
	HomeDir string `json:"home-dir"`
	Version int    `json:"version"`
}

type SetupParams struct {
	SelectedMap map[string]string `json:"selected-map"`
	TestURL     string            `json:"test-url"`
}

type UpdateParams struct {
	Tun                *tunSchema         `json:"tun"`
	AllowLan           *bool              `json:"allow-lan"`
	MixedPort          *int               `json:"mixed-port"`
	FindProcessMode    *P.FindProcessMode `json:"find-process-mode"`
	Mode               *tunnel.TunnelMode `json:"mode"`
	LogLevel           *log.LogLevel      `json:"log-level"`
	IPv6               *bool              `json:"ipv6"`
	TCPConcurrent      *bool              `json:"tcp-concurrent"`
	ExternalController *string            `json:"external-controller"`
	UnifiedDelay       *bool              `json:"unified-delay"`
	Authentication     *[]string          `json:"authentication"`
	GeoAutoUpdate      *bool              `json:"geo-auto-update"`
	GeoUpdateInterval  *int               `json:"geo-update-interval"`
}

type tunSchema struct {
	Enable       bool               `yaml:"enable" json:"enable"`
	Device       *string            `yaml:"device" json:"device"`
	Stack        *constant.TUNStack `yaml:"stack" json:"stack"`
	DNSHijack    *[]string          `yaml:"dns-hijack" json:"dns-hijack"`
	AutoRoute    *bool              `yaml:"auto-route" json:"auto-route"`
	RouteAddress *[]netip.Prefix    `yaml:"route-address" json:"route-address,omitempty"`
}

type SideLoadParams struct {
	ProviderName string `json:"providerName"`
	Data         string `json:"data"`
}

// AddProxyNodesParams 是 addProxyNodes 的入参。
//
// Nodes 接受两种写法、由内核自行判断，用户不必先选类型：
//   - 分享链接（vmess:// / vless:// / ss:// …），可多行批量粘贴；
//   - 直接的 YAML 片段（`- name: …` 形式的代理条目列表）。
type AddProxyNodesParams struct {
	YAML  string `json:"yaml"`
	Nodes string `json:"nodes"`
}

// AddProxyNodesResult 回传追加结果，供 Dart 提示「新增 3 个、跳过 1 个重名」——
// 重名节点如果在 Clash 里同时存在，整份配置会直接加载失败，所以必须去重并如实告知。
type AddProxyNodesResult struct {
	YAML    string   `json:"yaml"`
	Added   []string `json:"added"`
	Skipped []string `json:"skipped"`
}

// ReadProfileTargetsParams 是 readProfileTargets 的入参。
//
// 链式代理的候选名单只能从**配置本身**读：节点名与策略组名共用 Clash 的命名空间，
// 而覆写数据里并没有完整名单（它只有用户自定义的那几个组）。运行时那份 ClashConfig
// 也不行 —— 它反映的是「当前已生效的配置」，用户正在编辑的这份未必是它。
type ReadProfileTargetsParams struct {
	YAML string `json:"yaml"`
}

// ProfileTarget 是链式代理能引用的一项：一个节点，或者一个策略组。
//
// Type 是给界面显示用的（ss / vmess / Selector …）；Dialer 仅对节点有意义 ——
// 链是挂在**节点**上的（`dialer-proxy` 是 proxy 级选项，写在组上内核只记一条日志
// 就忽略），所以组的 Dialer 恒为空。
type ProfileTarget struct {
	Name   string `json:"name"`
	Type   string `json:"type"`
	Dialer string `json:"dialer"`
}

type ProfileTargets struct {
	Proxies []ProfileTarget `json:"proxies"`
	Groups  []ProfileTarget `json:"groups"`
}

// SetProxyChainParams 是 setProxyChain 的入参。
//
// BiLoom: 链式代理的正确形态。Clash 早期的做法是 `type: relay` 的分组，但本内核
// 已经把它删掉了 —— 写出来是**致命错误**（`adapter/outboundgroup/parser.go:216`，
// 整份配置加载失败），改成代理级的 `dialer-proxy`。
//
// Dialer 为空表示**解除**链（把 dialer-proxy 从该节点上删掉），不是「退回直连」——
// 删除字段与写明 DIRECT 是两件事，后者会让内核真去解析一个叫 DIRECT 的前跳。
type SetProxyChainParams struct {
	YAML   string `json:"yaml"`
	Target string `json:"target"`
	Dialer string `json:"dialer"`
}

type SetProxyChainResult struct {
	YAML string `json:"yaml"`
}

type ChangeProxyParams struct {
	GroupName string `json:"group-name"`
	ProxyName string `json:"proxy-name"`
}

type TestDelayParams struct {
	ProxyName string `json:"proxy-name"`
	TestUrl   string `json:"test-url"`
	Timeout   int64  `json:"timeout"`
}

type Traffic struct {
	Up   int64 `json:"up"`
	Down int64 `json:"down"`
}

type ExternalProvider struct {
	Name             string                     `json:"name"`
	Type             string                     `json:"type"`
	VehicleType      string                     `json:"vehicle-type"`
	Count            int                        `json:"count"`
	Path             string                     `json:"path"`
	UpdateAt         time.Time                  `json:"update-at"`
	SubscriptionInfo *provider.SubscriptionInfo `json:"subscription-info"`
}

type ProxiesData struct {
	Proxies map[string]constant.Proxy `json:"proxies"`
	All     []string                  `json:"all"`
}

const (
	messageMethod                  CoreMethod = "message"
	initClashMethod                CoreMethod = "initClash"
	getIsInitMethod                CoreMethod = "getIsInit"
	forceGcMethod                  CoreMethod = "forceGc"
	shutdownMethod                 CoreMethod = "shutdown"
	validateConfigMethod           CoreMethod = "validateConfig"
	updateConfigMethod             CoreMethod = "updateConfig"
	getProxiesMethod               CoreMethod = "getProxies"
	changeProxyMethod              CoreMethod = "changeProxy"
	getTrafficMethod               CoreMethod = "getTraffic"
	getTotalTrafficMethod          CoreMethod = "getTotalTraffic"
	resetTrafficMethod             CoreMethod = "resetTraffic"
	asyncTestDelayMethod           CoreMethod = "asyncTestDelay"
	getConnectionsMethod           CoreMethod = "getConnections"
	closeConnectionsMethod         CoreMethod = "closeConnections"
	resetConnectionsMethod         CoreMethod = "resetConnections"
	closeConnectionMethod          CoreMethod = "closeConnection"
	getExternalProvidersMethod     CoreMethod = "getExternalProviders"
	getExternalProviderMethod      CoreMethod = "getExternalProvider"
	getMemoryMethod                CoreMethod = "getMemory"
	updateGeoDataMethod            CoreMethod = "updateGeoData"
	updateExternalProviderMethod   CoreMethod = "updateExternalProvider"
	sideLoadExternalProviderMethod CoreMethod = "sideLoadExternalProvider"
	startLogMethod                 CoreMethod = "startLog"
	stopLogMethod                  CoreMethod = "stopLog"
	startListenerMethod            CoreMethod = "startListener"
	stopListenerMethod             CoreMethod = "stopListener"
	updateDnsMethod                CoreMethod = "updateDns"
	crashMethod                    CoreMethod = "crash"
	setupConfigMethod              CoreMethod = "setupConfig"
	getConfigMethod                CoreMethod = "getConfig"
	clearEffectMethod              CoreMethod = "clearEffect"
	convertSubscriptionMethod      CoreMethod = "convertSubscription"
	addProxyNodesMethod            CoreMethod = "addProxyNodes"
	readProfileTargetsMethod       CoreMethod = "readProfileTargets"
	setProxyChainMethod            CoreMethod = "setProxyChain"
)

type CoreMethod string

type MessageType string

type Delay struct {
	Url   string `json:"url"`
	Name  string `json:"name"`
	Value int32  `json:"value"`
}

type Message struct {
	Type MessageType `json:"type"`
	Data any         `json:"data"`
}

const (
	LogMessage       MessageType = "log"
	DelayMessage     MessageType = "delay"
	RequestMessage   MessageType = "request"
	LoadedMessage    MessageType = "loaded"
	GeoUpdateMessage MessageType = "geoUpdate"
)

type GeoUpdateStatus struct {
	Type     string `json:"type"`
	Updating bool   `json:"updating"`
	Skipped  bool   `json:"skipped,omitempty"`
	Error    string `json:"error,omitempty"`
}
