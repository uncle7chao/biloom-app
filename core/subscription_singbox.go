package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
)

// BiLoom: sing-box 配置 → Clash 节点。
//
// 只处理 outbounds 里真正的「出口节点」类型。selector / urltest 是分组，
// direct / block / dns 不是节点，tor / ssh / wireguard 在 Clash 侧语义差异过大，
// 一律跳过 —— 但会按类型计数，节点全被跳过时报错会把类型列出来，
// 免得用户对着一个空节点列表猜。

// singBoxSkippedTypes 记录 as-is 跳过的出站类型，用于报错时说明原因。
var singBoxUnsupportedTypes = map[string]string{
	"selector": "分组(selector),请用外层 tag 引用具体节点",
	"urltest":  "自动选择分组(urltest)",
	"direct":   "直连出站(direct)",
	"block":    "拦截出站(block)",
	"dns":      "DNS 出站(dns)",
	"tor":      "Tor 出站(内核无对应实现)",
	"ssh":      "SSH 出站(内核无对应实现)",
	"wireguard": "WireGuard 出站(需要额外密钥与网段配置,无法自动转换)",
}

func convertSingBoxSubscription(buf []byte) ([]map[string]any, error) {
	var root map[string]any
	if err := json.Unmarshal(buf, &root); err != nil {
		return nil, fmt.Errorf("sing-box 配置不是合法 JSON: %w", err)
	}
	rawOutbounds, _ := root["outbounds"].([]any)
	if len(rawOutbounds) == 0 {
		return nil, errors.New("sing-box 配置里没有 outbounds")
	}

	names := make(map[string]int, len(rawOutbounds))
	proxies := make([]map[string]any, 0, len(rawOutbounds))
	skipped := make(map[string]int, 4)

	for _, item := range rawOutbounds {
		outbound, ok := item.(map[string]any)
		if !ok {
			continue
		}
		proxy, err := singBoxOutboundToProxy(outbound, names)
		if err != nil {
			skipped[asString(outbound["type"])]++
			continue
		}
		proxies = append(proxies, proxy)
	}

	if len(proxies) == 0 {
		reasons := make([]string, 0, len(skipped))
		for kind, count := range skipped {
			reason, known := singBoxUnsupportedTypes[kind]
			if !known {
				reason = "不支持的出站类型"
			}
			reasons = append(reasons, fmt.Sprintf("%s ×%d:%s", kind, count, reason))
		}
		if len(reasons) == 0 {
			return nil, errors.New("sing-box 配置里没有可转换的出口节点")
		}
		return nil, fmt.Errorf(
			"sing-box 配置里没有可转换的出口节点(%s)", strings.Join(reasons, "; "),
		)
	}
	return proxies, nil
}

func singBoxOutboundToProxy(
	outbound map[string]any,
	names map[string]int,
) (map[string]any, error) {
	kind := strings.ToLower(strings.TrimSpace(asString(outbound["type"])))
	server := strings.TrimSpace(asString(outbound["server"]))
	port := asInt(outbound["server_port"])
	if server == "" || port <= 0 {
		return nil, errors.New("missing server")
	}

	proxy := map[string]any{
		"server": server,
		"port":   port,
		"udp":    true,
	}
	name := strings.TrimSpace(asString(outbound["tag"]))
	if name == "" {
		name = fmt.Sprintf("%s:%d", server, port)
	}
	proxy["name"] = uniqueShareName(names, name)

	tlsBlock := asMap(outbound["tls"])
	tlsEnabled := asBool(tlsBlock["enabled"])
	serverName := asString(tlsBlock["server_name"])

	switch kind {
	case "vless":
		proxy["type"] = "vless"
		proxy["uuid"] = asString(outbound["uuid"])
		if flow := asString(outbound["flow"]); flow != "" {
			proxy["flow"] = flow
		}
		applySingBoxPacketEncoding(proxy, asString(outbound["packet_encoding"]))
		applySingBoxTLS(proxy, tlsBlock, tlsEnabled, serverName)

	case "vmess":
		proxy["type"] = "vmess"
		proxy["uuid"] = asString(outbound["uuid"])
		proxy["alterId"] = asInt(outbound["alter_id"])
		proxy["cipher"] = firstNonEmpty(asString(outbound["security"]), "auto")
		applySingBoxPacketEncoding(proxy, asString(outbound["packet_encoding"]))
		applySingBoxTLS(proxy, tlsBlock, tlsEnabled, serverName)

	case "trojan":
		proxy["type"] = "trojan"
		proxy["password"] = asString(outbound["password"])
		applySingBoxTLS(proxy, tlsBlock, tlsEnabled, serverName)

	case "shadowsocks":
		proxy["type"] = "ss"
		proxy["cipher"] = firstNonEmpty(asString(outbound["method"]), "aes-256-gcm")
		proxy["password"] = asString(outbound["password"])
		if plugin := asString(outbound["plugin"]); plugin != "" {
			proxy["plugin"] = plugin
			if opts := asString(outbound["plugin_opts"]); opts != "" {
				proxy["plugin-opts"] = parseSSDPluginOpts(plugin, opts)
			}
		}

	case "hysteria2", "hysteria":
		if kind == "hysteria" {
			proxy["type"] = "hysteria"
			proxy["auth-str"] = asString(outbound["auth_str"])
			applySingBoxTLS(proxy, tlsBlock, true, serverName)
			if up := asInt(outbound["up_mbps"]); up > 0 {
				proxy["up"] = fmt.Sprintf("%d Mbps", up)
			}
			if down := asInt(outbound["down_mbps"]); down > 0 {
				proxy["down"] = fmt.Sprintf("%d Mbps", down)
			}
			break
		}
		proxy["type"] = "hysteria2"
		proxy["password"] = asString(outbound["password"])
		if obfs := asMap(outbound["obfs"]); len(obfs) > 0 {
			proxy["obfs"] = asString(obfs["type"])
			proxy["obfs-password"] = asString(obfs["password"])
		}
		if up := asInt(outbound["up_mbps"]); up > 0 {
			proxy["up"] = fmt.Sprintf("%d Mbps", up)
		}
		if down := asInt(outbound["down_mbps"]); down > 0 {
			proxy["down"] = fmt.Sprintf("%d Mbps", down)
		}
		applySingBoxTLS(proxy, tlsBlock, true, serverName)

	case "tuic":
		proxy["type"] = "tuic"
		proxy["uuid"] = asString(outbound["uuid"])
		proxy["password"] = asString(outbound["password"])
		if controller := asString(outbound["congestion_control"]); controller != "" {
			proxy["congestion-controller"] = controller
		}
		if mode := asString(outbound["udp_relay_mode"]); mode != "" {
			proxy["udp-relay-mode"] = mode
		}
		applySingBoxTLS(proxy, tlsBlock, true, serverName)

	case "anytls":
		proxy["type"] = "anytls"
		proxy["password"] = asString(outbound["password"])
		applySingBoxTLS(proxy, tlsBlock, true, serverName)

	case "socks", "socks5":
		proxy["type"] = "socks5"
		if user := asString(outbound["username"]); user != "" {
			proxy["username"] = user
			proxy["password"] = asString(outbound["password"])
		}

	case "http":
		proxy["type"] = "http"
		if user := asString(outbound["username"]); user != "" {
			proxy["username"] = user
			proxy["password"] = asString(outbound["password"])
		}
		if tlsEnabled {
			proxy["tls"] = true
			if serverName != "" {
				proxy["sni"] = serverName
			}
		}

	default:
		return nil, fmt.Errorf("unsupported outbound type: %s", kind)
	}

	applySingBoxTransport(proxy, asMap(outbound["transport"]))
	return proxy, nil
}

// applySingBoxTLS 把 sing-box 的 tls 段映射成 Clash 字段。
// 注意各协议的字段名不统一:vless/vmess 用 servername,trojan/hysteria2/tuic 用 sni。
func applySingBoxTLS(proxy map[string]any, tlsBlock map[string]any, enabled bool, serverName string) {
	if !enabled {
		return
	}
	proxy["tls"] = true
	kind := asString(proxy["type"])
	if serverName != "" {
		switch kind {
		case "trojan", "hysteria2", "tuic", "anytls":
			proxy["sni"] = serverName
		default:
			proxy["servername"] = serverName
		}
	}
	if asBool(tlsBlock["insecure"]) {
		proxy["skip-cert-verify"] = true
	}
	if alpn := asStringSlice(tlsBlock["alpn"]); len(alpn) > 0 {
		proxy["alpn"] = alpn
	}
	if utls := asMap(tlsBlock["utls"]); asBool(utls["enabled"]) {
		if fingerprint := asString(utls["fingerprint"]); fingerprint != "" {
			proxy["client-fingerprint"] = fingerprint
		}
	}
	if reality := asMap(tlsBlock["reality"]); asBool(reality["enabled"]) {
		proxy["reality-opts"] = map[string]any{
			"public-key": asString(reality["public_key"]),
			"short-id":   asString(reality["short_id"]),
		}
	}
}

// applySingBoxPacketEncoding 对齐内核 convert 包的写法:
// 显式 none 不写字段,packet 写 packet-addr,其余(默认 xudp)写 xudp。
func applySingBoxPacketEncoding(proxy map[string]any, encoding string) {
	switch strings.ToLower(encoding) {
	case "none":
	case "packet":
		proxy["packet-addr"] = true
	default:
		proxy["xudp"] = true
	}
}

// applySingBoxTransport 映射 sing-box 的 transport 段。
// 字段名与结构完全对齐内核 common/convert 的输出,避免两套写法互相打架。
func applySingBoxTransport(proxy map[string]any, transport map[string]any) {
	if len(transport) == 0 {
		return
	}
	kind := strings.ToLower(asString(transport["type"]))
	switch kind {
	case "ws":
		proxy["network"] = "ws"
		wsOpts := map[string]any{
			"path": firstNonEmpty(asString(transport["path"]), "/"),
		}
		if host := singBoxTransportHost(transport); host != "" {
			wsOpts["headers"] = map[string]any{"Host": host}
		}
		if maxEarlyData := asInt(transport["max_early_data"]); maxEarlyData > 0 {
			wsOpts["max-early-data"] = maxEarlyData
			wsOpts["early-data-header-name"] = firstNonEmpty(
				asString(transport["early_data_header_name"]),
				"Sec-WebSocket-Protocol",
			)
		}
		proxy["ws-opts"] = wsOpts

	case "httpupgrade":
		proxy["network"] = "httpupgrade"
		wsOpts := map[string]any{
			"path": firstNonEmpty(asString(transport["path"]), "/"),
		}
		if host := singBoxTransportHost(transport); host != "" {
			wsOpts["headers"] = map[string]any{"Host": host}
		}
		proxy["ws-opts"] = wsOpts

	case "grpc":
		proxy["network"] = "grpc"
		proxy["grpc-opts"] = map[string]any{
			"grpc-service-name": asString(transport["service_name"]),
		}

	case "http":
		proxy["network"] = "http"
		headers := map[string]any{}
		if host := singBoxTransportHost(transport); host != "" {
			headers["Host"] = []string{host}
		}
		proxy["http-opts"] = map[string]any{
			"path":    []string{firstNonEmpty(asString(transport["path"]), "/")},
			"headers": headers,
		}

	case "h2":
		proxy["network"] = "h2"
		h2Opts := map[string]any{
			"path": firstNonEmpty(asString(transport["path"]), "/"),
		}
		if host := singBoxTransportHost(transport); host != "" {
			h2Opts["host"] = []string{host}
		}
		proxy["h2-opts"] = h2Opts
	}
}

// singBoxTransportHost 取 transport.headers 里的 Host。
// sing-box 的 headers 是 map[string]string 或 map[string][]string,两种都要认。
func singBoxTransportHost(transport map[string]any) string {
	headers := asMap(transport["headers"])
	if len(headers) == 0 {
		return ""
	}
	for key, value := range headers {
		if !strings.EqualFold(key, "host") {
			continue
		}
		if text := asString(value); text != "" {
			return text
		}
		if list := asStringSlice(value); len(list) > 0 {
			return list[0]
		}
	}
	return ""
}

func asString(value any) string {
	switch typed := value.(type) {
	case string:
		return typed
	case json.Number:
		return typed.String()
	case float64:
		return strconv.FormatFloat(typed, 'f', -1, 64)
	}
	return ""
}

func asInt(value any) int {
	switch typed := value.(type) {
	case float64:
		return int(typed)
	case json.Number:
		if parsed, err := typed.Int64(); err == nil {
			return int(parsed)
		}
	case int:
		return typed
	case string:
		if parsed, err := strconv.Atoi(strings.TrimSpace(typed)); err == nil {
			return parsed
		}
	}
	return 0
}

func asBool(value any) bool {
	switch typed := value.(type) {
	case bool:
		return typed
	case string:
		parsed, err := strconv.ParseBool(strings.TrimSpace(typed))
		return err == nil && parsed
	}
	return false
}

func asMap(value any) map[string]any {
	if typed, ok := value.(map[string]any); ok {
		return typed
	}
	return nil
}

func asStringSlice(value any) []string {
	raw, ok := value.([]any)
	if !ok {
		return nil
	}
	out := make([]string, 0, len(raw))
	for _, item := range raw {
		if text := asString(item); text != "" {
			out = append(out, text)
		}
	}
	return out
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}
