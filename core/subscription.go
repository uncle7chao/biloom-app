package main

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"

	"github.com/metacubex/mihomo/common/convert"
	"github.com/metacubex/mihomo/common/yaml"
	"github.com/metacubex/mihomo/config"
)

// BiLoom: 订阅兼容层。
//
// mihomo 的主配置路径只接受 Clash YAML —— config/config.go 的 UnmarshalRawConfig
// 一旦 YAML 解不动就直接返回错误，而 base64/明文的 v2ray 分享链接列表、ssd:// 订阅
// 都不满足这个前提。于是「添加配置 → 填订阅 URL」这个最常见的动作，对绝大多数国内
// 机场的默认订阅链接会直接以
//     yaml: unmarshal errors: line 1: cannot unmarshal !!str 'dmxlc3M...' into config.RawConfig
// 失败 —— 报错是英文的、且完全没告诉用户发生了什么。
//
// 内核其实已经有现成的转换器，只是没接到主配置路径上：convert.ConvertsV2Ray 就用在
// adapter/provider/provider.go 的 proxy-provider 解析路径上（YAML 解失败后的回退），
// 而它本身已经覆盖 vless / vmess / trojan / ss / ssr / hysteria(2) / tuic / anytls /
// mieru / socks / http 以及 ws / grpc / h2 / xhttp / httpupgrade 等传输，还自带
// base64 解码。所以这里不重复造轮子，只做三件事：
//
//  1. 嗅探订阅格式；
//  2. 把非 Clash 格式转成 Clash proxies；
//  3. 交给 Dart 在存盘前调用（convertSubscription），让 profile 文件本身始终是标准
//     Clash 配置 —— 这样覆写/模板、节点页、延迟测试、编辑配置等既有链路全部不受影响。

type subscriptionFormat string

const (
	subscriptionFormatClash   subscriptionFormat = "clash"
	subscriptionFormatV2Ray   subscriptionFormat = "v2ray"
	subscriptionFormatSSD     subscriptionFormat = "ssd"
	subscriptionFormatSingBox subscriptionFormat = "sing-box"
	subscriptionFormatUnknown subscriptionFormat = "unknown"
)

// knownShareSchemes 是「分享链接订阅」的 scheme 白名单。
// 只用来嗅探，真正的转换由内核 convert 包完成 —— 这里多列一些无妨，
// 漏列只会让格式退化成 unknown。
var knownShareSchemes = map[string]bool{
	"vless": true, "vmess": true, "trojan": true,
	"ss": true, "ssr": true, "ssd": true,
	"hysteria": true, "hysteria2": true, "hy2": true,
	"tuic": true, "juicity": true, "anytls": true,
	"socks": true, "socks5": true, "http": true, "https": true,
	"mieru": true, "mierus": true, "snell": true, "ssh": true,
	"wireguard": true, "wg": true, "brook": true, "mieru-http": true,
}

func stripBOM(s string) string {
	return strings.TrimPrefix(s, "\ufeff")
}

// decodeSubscriptionBase64 按订阅侧最常见的几种变体解码。
// 与内核 convert.DecodeBase64 不同的是：这里解码失败就如实返回错误，
// 不做「原样返回」的兜底 —— 嗅探阶段需要区分「解出来了」和「没解出来」。
func decodeSubscriptionBase64(text string) (string, error) {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return "", errors.New("empty input")
	}
	// base64 里不该出现这些字符，出现就说明本来就是明文
	if strings.ContainsAny(trimmed, " \r\n\t{}[]:") {
		return "", errors.New("not base64")
	}
	candidates := []*base64.Encoding{
		base64.StdEncoding,
		base64.RawStdEncoding,
		base64.URLEncoding,
		base64.RawURLEncoding,
	}
	for _, encoding := range candidates {
		decoded, err := encoding.DecodeString(trimmed)
		if err != nil || len(decoded) == 0 {
			continue
		}
		if !utf8.Valid(decoded) {
			continue
		}
		return string(decoded), nil
	}
	return "", errors.New("not base64")
}

// containsShareLink 判断文本里是否含至少一条受支持的分享链接。
// depth 用来防止 base64 自指时的无限递归。
func containsShareLink(text string, depth int) bool {
	if depth > 2 {
		return false
	}
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, "//") {
			continue
		}
		scheme, _, found := strings.Cut(line, "://")
		if !found {
			continue
		}
		if knownShareSchemes[strings.ToLower(strings.TrimSpace(scheme))] {
			return true
		}
	}
	decoded, err := decodeSubscriptionBase64(text)
	if err != nil || decoded == text {
		return false
	}
	return containsShareLink(decoded, depth+1)
}

// sniffSubscriptionFormat 判定 buf 属于哪种订阅格式。
//
// 顺序有讲究，两条都不能动：
//  1. **JSON 必须在 Clash YAML 之前判**。JSON 是 YAML 的子集，一份 sing-box 配置
//     能被 config.UnmarshalRawConfig 成功解成一个「没有任何 proxies 的 Clash 配置」，
//     于是被当成 Clash 配置原样放行，最终用户拿到一个节点列表为空的配置 ——
//     比报错更难查。同理，服务端返回的 JSON 错误体（`{"code":1,...}`）也会被
//     误判成合法配置。
//  2. 分享链接列表在 Clash 探测之后，因为它一定解不过 YAML。
func sniffSubscriptionFormat(buf []byte) subscriptionFormat {
	text := strings.TrimSpace(stripBOM(string(buf)))
	if text == "" {
		return subscriptionFormatUnknown
	}
	if strings.HasPrefix(text, "{") {
		switch {
		case isSingBoxConfig(text):
			return subscriptionFormatSingBox
		case strings.Contains(text, `"proxies"`):
			// 少数工具会导出 JSON 形态的 Clash 配置，落到下面按 YAML 走
		default:
			return subscriptionFormatUnknown
		}
	}
	if _, err := config.UnmarshalRawConfig(buf); err == nil {
		return subscriptionFormatClash
	}
	if strings.HasPrefix(strings.ToLower(text), "ssd://") {
		return subscriptionFormatSSD
	}
	if containsShareLink(text, 0) {
		return subscriptionFormatV2Ray
	}
	return subscriptionFormatUnknown
}

func isSingBoxConfig(text string) bool {
	if !strings.HasPrefix(text, "{") {
		return false
	}
	var probe struct {
		Outbounds json.RawMessage `json:"outbounds"`
		Log       json.RawMessage `json:"log"`
		Inbounds  json.RawMessage `json:"inbounds"`
	}
	if err := json.Unmarshal([]byte(text), &probe); err != nil {
		return false
	}
	// sing-box 配置的判别特征：有 outbounds；或者既没有 clash 的 proxies 也没有
	// 我们认得的其它形态，但带着 log/inbounds 这类 sing-box 专有段。
	if len(probe.Outbounds) > 0 {
		return true
	}
	return len(probe.Log) > 0 || len(probe.Inbounds) > 0
}

// looksLikeYAMLConfig 判断内容看起来是否本来就是一份 YAML 配置。
//
// 目的是把「YAML 写错了」和「根本不是 YAML」区分开:前者的原始报错(行号、字段名)
// 对正在编辑配置的人有用，不能吞掉换成一句「无法识别订阅格式」。
// 判据放宽到「首行是顶层键」或「正文里出现任何已知的 Clash 顶层键」——
// 宁可多判成 YAML(退化成原始报错，与改动前一致)，也不要误判成未知格式。
func looksLikeYAMLConfig(buf []byte) bool {
	text := stripBOM(string(buf))
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") || line == "---" {
			continue
		}
		key, _, found := strings.Cut(line, ":")
		if found {
			key = strings.TrimSpace(key)
			if key != "" && !strings.ContainsAny(key, " \t\"'") {
				return true
			}
		}
		break
	}
	for _, key := range []string{
		"proxies:", "proxy-groups:", "proxy-providers:", "rules:",
		"rule-providers:", "mixed-port:", "port:", "socks-port:",
		"allow-lan:", "mode:", "log-level:", "external-controller:",
		"dns:", "tun:", "script:", "listeners:",
	} {
		if strings.Contains(text, "\n"+key) || strings.HasPrefix(text, key) {
			return true
		}
	}
	return false
}

// subscriptionProxies 把受支持的订阅内容转成 Clash proxies 列表。
// 已判定为 Clash YAML 时返回 (nil, nil)，调用方应原样使用输入。
func subscriptionProxies(buf []byte) ([]map[string]any, subscriptionFormat, error) {
	if blankSubscription(buf) {
		return nil, subscriptionFormatUnknown, errEmptySubscription
	}
	format := sniffSubscriptionFormat(buf)
	switch format {
	case subscriptionFormatClash:
		return nil, format, nil
	case subscriptionFormatUnknown:
		// 本来就长着一张 YAML 脸的话，把内核的原始报错透出去，
		// 比统一换成「无法识别订阅格式」对编辑配置的人有用得多。
		if _, err := config.UnmarshalRawConfig(buf); err != nil && looksLikeYAMLConfig(buf) {
			return nil, format, err
		}
		return nil, format, unsupportedSubscriptionError(buf)
	case subscriptionFormatV2Ray:
		proxies, err := convert.ConvertsV2Ray(buf)
		if err != nil {
			return nil, format, fmt.Errorf(
				"订阅内容无法解析: %w", err,
			)
		}
		if len(proxies) == 0 {
			return nil, format, errors.New(
				"订阅里没有解析出任何可用节点,请确认链接是否已失效",
			)
		}
		return proxies, format, nil
	case subscriptionFormatSSD:
		proxies, err := convertSSDSubscription(buf)
		if err != nil {
			return nil, format, err
		}
		return proxies, format, nil
	case subscriptionFormatSingBox:
		proxies, err := convertSingBoxSubscription(buf)
		if err != nil {
			return nil, format, err
		}
		return proxies, format, nil
	}
	return nil, format, errUnsupportedSubscription
}

var errUnsupportedSubscription = errors.New(
	"无法识别该订阅格式:内核支持 Clash 配置、v2ray/SS/SSR 分享链接订阅(base64 或明文)、" +
		"sing-box 配置与 ssd 订阅。如果你拿到的是别家的客户端订阅,请向服务商索取 Clash 订阅链接",
)

// errEmptySubscription 专指「服务端响应了、但内容为空」。
// 与「无法识别该订阅格式」分开是有意的：前者要查链接是否过期/是否需要换域名，
// 后者要查是不是拿了别家客户端的订阅格式，排查方向完全不同。
var errEmptySubscription = errors.New(
	"订阅内容为空:服务端返回了响应但没有任何内容,请确认订阅链接是否已过期或需要重新获取",
)

// blankSubscription 判断内容是否为空白 —— 只有空格、换行、BOM、注释与 YAML 文档分隔符。
//
// 需要区分「空」和「不认识」：空的 profile 是合法状态（新建的配置、被清空的配置），
// 内核会按默认值跑；把它当成「无法识别的订阅」拒掉，会让这些配置突然加载失败。
func blankSubscription(buf []byte) bool {
	for _, line := range strings.Split(stripBOM(string(buf)), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || line == "---" || strings.HasPrefix(line, "#") {
			continue
		}
		return false
	}
	return true
}

// unsupportedSubscriptionError 在兜底报错里附上服务端实际返回的一小段内容。
// 订阅过期、被限流、域名被墙时服务端常常回一个 JSON 或 HTML 错误体 ——
// 把「无法识别该订阅格式」换成像样的原文引用，用户和客服都能一眼看出问题。
// 只在内容很短时才附，避免把一整页 HTML 塞进弹窗。
func unsupportedSubscriptionError(buf []byte) error {
	excerpt := strings.Join(strings.Fields(stripBOM(string(buf))), " ")
	if excerpt == "" {
		return errUnsupportedSubscription
	}
	runes := []rune(excerpt)
	if len(runes) > 300 {
		return errUnsupportedSubscription
	}
	if len(runes) > 120 {
		excerpt = string(runes[:120]) + "…"
	}
	return fmt.Errorf("%s。服务端返回的内容是「%s」", errUnsupportedSubscription, excerpt)
}

// convertedSubscription 是一次订阅转换的完整结果。
type convertedSubscription struct {
	YAML      []byte
	Format    subscriptionFormat
	NodeCount int
	Changed   bool
}

// subscriptionToProfileYAML 产出「profile 形态」的 Clash YAML —— proxies 加上一套
// 默认 proxy-groups 与 rules，其余字段（端口/DNS/日志/认证…）交给 FlClash 的
// makeRealProfile 去注入。该形态与 FlClash 自己导出 profile 的形状一致，也是内核
// handleGetConfig 期望的形状。
//
// 为什么要带上分组与规则而不是只给 proxies：见 subscription_defaults.go 的说明 ——
// 只给 proxies 会让「代理」页签消失、且所有流量走直连。
func subscriptionToProfileYAML(buf []byte) (convertedSubscription, error) {
	// 空 profile 是合法状态：新建的配置、被清空的配置都长这样，内核按默认值跑。
	// 与 subscriptionToFullConfigYAML 同理，必须在嗅探之前短路 —— 否则
	// 在编辑页保存一份空配置会被判成「订阅内容为空」，把「下载回来的响应体是空的」
	// 和「磁盘上的配置是空的」两件事混为一谈。
	if blankSubscription(buf) {
		return convertedSubscription{
			YAML:   buf,
			Format: subscriptionFormatClash,
		}, nil
	}
	proxies, format, err := subscriptionProxies(buf)
	if err != nil {
		return convertedSubscription{Format: format}, err
	}
	if format == subscriptionFormatClash {
		// 已经是 Clash 配置：它自带服务商设计好的分组与规则，原样放行。
		return convertedSubscription{YAML: buf, Format: format}, nil
	}
	groups, rules := defaultSubscriptionGroups(proxies)
	profile := map[string]any{
		"proxies":      proxies,
		"proxy-groups": groups,
		"rules":        rules,
	}
	out, err := yaml.Marshal(profile)
	if err != nil {
		return convertedSubscription{Format: format}, fmt.Errorf("生成 Clash 配置失败: %w", err)
	}
	return convertedSubscription{
		YAML:      out,
		Format:    format,
		NodeCount: len(proxies),
		Changed:   true,
	}, nil
}

// subscriptionToFullConfigYAML 产出「完整配置形态」的 YAML —— 在 proxies 之外补齐
// 内核默认值。用于 loadConfig 的兜底路径:那里输入本该是 FlClash 生成的完整配置，
// 只有被手工替换成订阅原文时才会走到转换分支，而完整配置必须自带端口等字段。
// 分组与规则同 subscriptionToProfileYAML 一样要补，否则兜底回来的配置连不上网。
func subscriptionToFullConfigYAML(buf []byte) ([]byte, subscriptionFormat, error) {
	// 空 profile 是合法状态：新建的配置、被清空的配置都长这样，内核按默认值跑即可。
	// 必须在嗅探之前短路 —— 否则它们会被归成「无法识别的订阅」而加载失败。
	if blankSubscription(buf) {
		return buf, subscriptionFormatClash, nil
	}
	proxies, format, err := subscriptionProxies(buf)
	if err != nil {
		return nil, format, err
	}
	if format == subscriptionFormatClash {
		return buf, format, nil
	}
	groups, rules := defaultSubscriptionGroups(proxies)
	rawConfig := config.DefaultRawConfig()
	rawConfig.Proxy = proxies
	rawConfig.ProxyGroup = groups
	rawConfig.Rule = rules
	out, err := yaml.Marshal(rawConfig)
	if err != nil {
		return nil, format, fmt.Errorf("生成 Clash 配置失败: %w", err)
	}
	return out, format, nil
}

// convertSSDSubscription 解析 ssd:// 订阅。
// 格式为 ssd://<base64(JSON)>，JSON 形如
// {"airport":"x","port":443,"encryption":"aes-256-gcm","password":"p",
//  "servers":[{"server":"1.2.3.4","port":8443,"encryption":"...","password":"...","remarks":"HK"}]}
// 其中 servers 里的字段缺省时回退到顶层同名字段。
func convertSSDSubscription(buf []byte) ([]map[string]any, error) {
	text := strings.TrimSpace(stripBOM(string(buf)))
	payload := text[len("ssd://"):]
	decoded, err := decodeSubscriptionBase64(payload)
	if err != nil {
		return nil, fmt.Errorf("ssd 订阅解码失败: %w", err)
	}
	var ssd struct {
		Airport     string `json:"airport"`
		Port        int    `json:"port"`
		Encryption  string `json:"encryption"`
		Password    string `json:"password"`
		Plugin      string `json:"plugin"`
		PluginOpts  string `json:"plugin_options"`
		Obfs        string `json:"obfs"`
		Protocol    string `json:"protocol"`
		ServerCount int    `json:"server_count"`
		Servers     []struct {
			Server     string `json:"server"`
			Port       int    `json:"port"`
			Encryption string `json:"encryption"`
			Password   string `json:"password"`
			Plugin     string `json:"plugin"`
			PluginOpts string `json:"plugin_options"`
			Remarks    string `json:"remarks"`
			ID         any    `json:"id"`
		} `json:"servers"`
	}
	if err := json.Unmarshal([]byte(decoded), &ssd); err != nil {
		return nil, fmt.Errorf("ssd 订阅内容不是合法 JSON: %w", err)
	}
	if len(ssd.Servers) == 0 {
		return nil, errors.New("ssd 订阅里没有节点")
	}

	names := make(map[string]int, len(ssd.Servers))
	proxies := make([]map[string]any, 0, len(ssd.Servers))
	for index, server := range ssd.Servers {
		host := strings.TrimSpace(server.Server)
		if host == "" {
			continue
		}
		port := server.Port
		if port == 0 {
			port = ssd.Port
		}
		if port == 0 {
			port = 443
		}
		cipher := server.Encryption
		if cipher == "" {
			cipher = ssd.Encryption
		}
		if cipher == "" {
			cipher = "aes-256-gcm"
		}
		password := server.Password
		if password == "" {
			password = ssd.Password
		}
		name := strings.TrimSpace(server.Remarks)
		if name == "" {
			name = fmt.Sprintf("%s:%d", host, port)
		}
		proxy := map[string]any{
			"name":     uniqueShareName(names, name),
			"type":     "ss",
			"server":   host,
			"port":     port,
			"cipher":   cipher,
			"password": password,
			"udp":      true,
		}
		plugin := server.Plugin
		if plugin == "" {
			plugin = ssd.Plugin
		}
		pluginOpts := server.PluginOpts
		if pluginOpts == "" {
			pluginOpts = ssd.PluginOpts
		}
		if plugin != "" {
			proxy["plugin"] = plugin
			if pluginOpts != "" {
				proxy["plugin-opts"] = parseSSDPluginOpts(plugin, pluginOpts)
			}
		}
		_ = index
		proxies = append(proxies, proxy)
	}
	if len(proxies) == 0 {
		return nil, errors.New("ssd 订阅里没有解析出任何可用节点")
	}
	return proxies, nil
}

// parseSSDPluginOpts 把 ssd 的 `plugin_options` 字符串("key=value;key2=value2")
// 转成 Clash 的 plugin-opts 映射。Clash 侧除了 mode/host/path 之类还要求 tls 等
// 布尔项，这里只做字符串搬运，交给内核自己校验。
func parseSSDPluginOpts(plugin, options string) map[string]any {
	opts := make(map[string]any, 8)
	for _, pair := range strings.Split(options, ";") {
		pair = strings.TrimSpace(pair)
		if pair == "" {
			continue
		}
		key, value, found := strings.Cut(pair, "=")
		if !found {
			continue
		}
		key = strings.TrimSpace(key)
		value = strings.TrimSpace(value)
		if key == "" {
			continue
		}
		switch strings.ToLower(value) {
		case "true":
			opts[key] = true
		case "false":
			opts[key] = false
		default:
			opts[key] = value
		}
	}
	if strings.Contains(strings.ToLower(plugin), "tls") {
		if _, ok := opts["tls"]; !ok {
			opts["tls"] = true
		}
	}
	return opts
}

// uniqueShareName 复刻内核 convert 包的去重命名规则(重名追加 -2、-3…)，
// 让同一次导入里的节点名稳定且唯一 —— Clash 的节点名必须唯一。
func uniqueShareName(names map[string]int, name string) string {
	count, exists := names[name]
	if !exists {
		names[name] = 1
		return name
	}
	count++
	names[name] = count
	return fmt.Sprintf("%s-%d", name, count)
}

// ConvertSubscriptionResult 是 convertSubscription 方法的返回体。
type ConvertSubscriptionResult struct {
	Format    string `json:"format"`
	Changed   bool   `json:"changed"`
	NodeCount int    `json:"nodeCount"`
	YAML      string `json:"yaml"`
}

// handleConvertSubscription 供 Dart 在把订阅写盘之前调用。
//
// 让 Dart 主动调一次、拿转换后的 YAML 去存盘，而不是只在读取时兜底，是有意的:
// profile 文件本身保持标准 Clash 配置，编辑配置页、覆写/模板、节点页、延迟测试
// 这些既有链路就全都不必改。
//
// 「服务端响应了、正文却是空的」只在这里判定：只有这条路径处理的是「刚下载回来的
// 内容」。同样走 subscriptionToProfileYAML 的另外两处是读磁盘上的 profile，
// 那里的空文件必须放行 —— 混在一起判会让存量用户的空配置突然加载失败。
func handleConvertSubscription(data string) (ConvertSubscriptionResult, error) {
	if blankSubscription([]byte(data)) {
		return ConvertSubscriptionResult{}, errEmptySubscription
	}
	converted, err := subscriptionToProfileYAML([]byte(data))
	if err != nil {
		return ConvertSubscriptionResult{}, err
	}
	return ConvertSubscriptionResult{
		Format:    string(converted.Format),
		Changed:   converted.Changed,
		NodeCount: converted.NodeCount,
		YAML:      string(converted.YAML),
	}, nil
}
