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

// RemoveProxyNodesParams 是 removeProxyNodes 的入参。Names 是要删除的节点名列表。
type RemoveProxyNodesParams struct {
	YAML  string   `json:"yaml"`
	Names []string `json:"names"`
}

// RemoveProxyNodesResult 回传删除结果：Removed 是真删掉的，Missing 是配置里
// 找不到的（多半是面板数据已过期）。引用清理（组员/规则/listeners）在内核同步做，
// 调用方拿到的 YAML 一定是加载得动的。
type RemoveProxyNodesResult struct {
	YAML    string   `json:"yaml"`
	Removed []string `json:"removed"`
	Missing []string `json:"missing"`
}

// UpdateProxyNodeParams 是 updateProxyNodes 的入参。Name 是被编辑节点的
// 当前名字（定位锚点），Node 是编辑后的单节点片段（JSON 或 YAML）。
type UpdateProxyNodeParams struct {
	YAML string `json:"yaml"`
	Name string `json:"name"`
	Node string `json:"node"`
}

// UpdateProxyNodeResult 回传更新结果。名字是策略组成员、规则出口、链式引用的
// 共同锚点，本方法不允许改名 —— 想改名走「删除 + 重新添加」。
type UpdateProxyNodeResult struct {
	YAML    string `json:"yaml"`
	Updated string `json:"updated"`
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
	// Nodes 是 proxies 段的**完整参数**（与 Proxies 同序同名）。编辑节点要
	// 预填表单，光有名字/类型不够 —— 把原样参数带回给界面。
	Nodes []map[string]any `json:"nodes,omitempty"`
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

// CopyProxyNodeParams 是 copyProxyNode 的入参：把来源配置里的一个节点**原样复制**
// 进目标配置。链式代理的「跨配置挑选」靠它兜底 —— 链是名字引用，只在同一份配置
// 内成立，所以从别的配置挑了出口/前置后，得先把那个节点搬进链所在的那份配置。
type CopyProxyNodeParams struct {
	From string `json:"from"` // 来源配置全文
	To   string `json:"to"`   // 目标配置全文
	Name string `json:"name"` // 要复制的节点名（必须在来源配置的 proxies 里）
}

// CopyProxyNodeResult 回传复制结果。
//
// Name 是节点在目标配置里的**最终名字**：目标配置已有同名时自动追加 -2、-3，
// 链必须引用这个名字而不是请求里的原名。Reused 为 true 表示目标配置里已存在
// 同一节点（协议|地址|端口|凭据 相同），此时一个字节都没动、直接复用那个已有
// 名字 —— 跨配置复制同一个节点两次不该产出两条一模一样的记录。
type CopyProxyNodeResult struct {
	YAML   string `json:"yaml"`
	Name   string `json:"name"`
	Reused bool   `json:"reused"`
}

// AddProxyChainParams 是 addProxyChain 的入参：**新建一条独立的链式代理节点**。
//
// 与 setProxyChain（把 dialer-proxy 写到出口节点身上）不同，这条路线生成的是
// 一个新 proxy 条目：参数复制自出口、dialer-proxy 指向前置、名字由调用方给。
// 所有链式代理节点统一收进 Group 指定的策略组（不存在就创建 select 组），
// 代理页里就是一个独立页签。
//
// AutoNumber 决定重名时的策略：true（界面用默认名「链式代理」）→ 按 名称1、
// 名称2 递增找空位；false（用户自定义名）→ 先用原名，被占用才追加 -2、-3。
type AddProxyChainParams struct {
	YAML       string `json:"yaml"`
	Exit       string `json:"exit"`   // 出口节点名（参数复制自它）
	Dialer     string `json:"dialer"` // 前置名（节点或策略组）
	Name       string `json:"name"`   // 期望的链式代理名（基础名）
	AutoNumber bool   `json:"autoNumber"`
	Group      string `json:"group"` // 收纳所有链式代理的分组名
}

// AddProxyChainResult 回传创建结果。Name 是链式代理节点的**最终名字**
// （重名时可能带数字后缀），界面提示与后续引用都用它。
type AddProxyChainResult struct {
	YAML  string `json:"yaml"`
	Name  string `json:"name"`
	Group string `json:"group"`
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

// RequestProxyIPParams / RequestProxyIPResult 的语义说明在 proxy_ip.go ——
// 参数结构放在这里是为了和 TestDelayParams 等其余入参保持一处。
type RequestProxyIPParams struct {
	Name    string `json:"name"`
	Url     string `json:"url"`
	Timeout int64  `json:"timeout"`
}

// IP 是节点真实出口的地址，Country 是本地 geoip 数据认出的两位国家码
//（认不出为空串 —— 认不出就交回「未知」，不硬猜）。
type RequestProxyIPResult struct {
	IP      string `json:"ip"`
	Country string `json:"country"`
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
	requestProxyIPMethod           CoreMethod = "requestProxyIP"
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
	removeProxyNodesMethod         CoreMethod = "removeProxyNodes"
	updateProxyNodeMethod          CoreMethod = "updateProxyNode"
	readProfileTargetsMethod       CoreMethod = "readProfileTargets"
	setProxyChainMethod            CoreMethod = "setProxyChain"
	copyProxyNodeMethod            CoreMethod = "copyProxyNode"
	addProxyChainMethod            CoreMethod = "addProxyChain"
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
