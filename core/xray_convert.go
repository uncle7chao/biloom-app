package main

// BiLoom: V2rayN / Xray 导出配置 → mihomo 节点 的自动转化。
//
// 用户最常用的「从别处拷节点」来源是 V2rayN 导出的 JSON，它和 mihomo 是两套完全
// 不同的词汇表：
//
//   - 顶层容器：Xray 是完整配置（log/dns/inbounds/**outbounds**/routing），
//     节点住在 outbounds 数组里；mihomo 只认 proxies / 单节点 map。
//   - 字段命名：Xray 用 vnext[].address / users[].id / streamSettings.security
//     这种长路径；mihomo 用 server / uuid / reality-opts 这种扁平键。
//   - 取值枚举：Xray 的传输层叫 raw（新）/tcp（旧），mihomo 里都是 tcp。
//
// 不做转化的后果不是报错就能兜住的 —— 内核对不认识的键是**静默忽略**，就算把
// outbound 原样塞进 proxies，节点也只会以「全是空字段」的形态存在，用户根本
// 看不出哪里错了。所以这里显式做一层映射，转不动的字段宁可丢掉也不乱猜。
//
// 覆盖协议：vless / vmess / trojan / shadowsocks / socks / http。
// freedom（直连）、blackhole（阻断）、dns、wireguard 等 outbound 不是「节点」，
// 一律跳过；一个可导入的都没有时给出明确报错，而不是静默成功。

import (
	"errors"
	"fmt"
	"strings"
)

// xrayStyleOutbounds 判定 outbounds 数组是 Xray 风格（成员用 protocol 键标类型）
// 还是 sing-box 风格（成员用 type 键）。判别依据取第一个能看的成员 —— 两种生态
// 的配置里所有 outbound 都用同一个判别键，不会混。
func xrayStyleOutbounds(raw any) bool {
	items, ok := raw.([]any)
	if !ok {
		return false
	}
	for _, item := range items {
		outbound, ok := item.(map[string]any)
		if !ok {
			continue
		}
		if _, ok := outbound["protocol"]; ok {
			return true
		}
		return false
	}
	return false
}

// isGenericOutboundTag 判定 tag 是否为客户端导出的通用内部标识。
// V2rayN 导出完整配置时 outbound 的 tag 恒为 proxy（freedom/blackhole 是
// direct/block），sing-box 默认同样是 proxy —— 这些不是给人看的节点名，直接
// 拿来当 mihomo 节点名会让不同协议/不同服务器的节点全部撞名，触发内核
// 「重名跳过」后表现为「粘贴了但节点没出现」。有意义的自定义 tag 不受影响。
func isGenericOutboundTag(tag string) bool {
	switch strings.ToLower(strings.TrimSpace(tag)) {
	case "", "proxy", "out", "outbound", "direct", "block":
		return true
	}
	return false
}

// convertXrayConfig 把整份 Xray 配置（或单个 outbound）转成 mihomo 节点列表。
func convertXrayConfig(doc map[string]any) ([]map[string]any, error) {
	raw, ok := doc["outbounds"]
	if !ok {
		return nil, errors.New("不是 Xray/V2 配置：找不到 outbounds")
	}
	items, ok := raw.([]any)
	if !ok {
		return nil, errors.New("Xray/V2 配置的 outbounds 不是一个列表")
	}

	nodes := make([]map[string]any, 0, len(items))
	skipped := make([]string, 0)
	for index, item := range items {
		outbound, ok := item.(map[string]any)
		if !ok {
			skipped = append(skipped, fmt.Sprintf("#%d", index+1))
			continue
		}
		node, err := convertXrayOutbound(outbound, index+1)
		if err != nil {
			skipped = append(skipped, fmt.Sprintf("#%d(%v)", index+1, err))
			continue
		}
		nodes = append(nodes, node)
	}
	if len(nodes) == 0 {
		if len(skipped) == 0 {
			return nil, errors.New("Xray/V2 配置里没有 outbound")
		}
		return nil, fmt.Errorf(
			"Xray/V2 配置里没有可导入的节点（跳过: %s）；支持 vless/vmess/trojan/shadowsocks/socks/http",
			strings.Join(skipped, ", "),
		)
	}
	return nodes, nil
}

// convertXrayOutbound 转换单个 outbound；不支持协议返回错误（由上层跳过并汇报）。
func convertXrayOutbound(outbound map[string]any, index int) (map[string]any, error) {
	protocol, _ := outbound["protocol"].(string)
	settings, _ := outbound["settings"].(map[string]any)
	stream, _ := outbound["streamSettings"].(map[string]any)

	var entries []map[string]any
	nodeType := protocol
	if protocol == "shadowsocks" {
		// mihomo 的类型名是 ss，Xray 叫 shadowsocks。
		nodeType = "ss"
	}
	if protocol == "socks" {
		// mihomo 的类型名是 socks5，Xray 叫 socks。
		nodeType = "socks5"
	}
	switch protocol {
	case "vless":
		entries = xrayServerEntries(settings, "vnext")
	case "vmess":
		entries = xrayServerEntries(settings, "vnext")
	case "trojan":
		entries = xrayServerEntries(settings, "servers")
	case "shadowsocks":
		entries = xrayServerEntries(settings, "servers")
	case "socks":
		entries = xrayServerEntries(settings, "servers")
	case "http":
		entries = xrayServerEntries(settings, "servers")
	default:
		return nil, fmt.Errorf("%s 不支持", protocol)
	}
	if len(entries) == 0 {
		return nil, fmt.Errorf("%s 没有服务器条目", protocol)
	}

	tag, _ := outbound["tag"].(string)
	nodes := make([]map[string]any, 0, len(entries))
	for i, entry := range entries {
		node := buildNodeFromXrayEntry(nodeType, entry, stream)
		if node == nil {
			continue
		}
		name := strings.TrimSpace(tag)
		if isGenericOutboundTag(name) {
			// V2rayN 导出完整配置时 tag 恒为 proxy —— 不是给人看的节点名。
			// 用 协议-地址-端口 生成有区分度的名字，否则不同协议/服务器的
			// 配置粘贴进来全部撞名，被内核「重名跳过」表现为「粘贴没反应」。
			server := xrayString(entry["address"])
			port, _ := xrayInt(entry["port"])
			name = fmt.Sprintf("%s-%s-%d", nodeType, server, port)
		} else if len(entries) > 1 {
			name = fmt.Sprintf("%s-%d", name, i+1)
		}
		node["name"] = name
		nodes = append(nodes, node)
	}
	if len(nodes) == 0 {
		return nil, fmt.Errorf("%s 条目缺少地址或端口", protocol)
	}
	return nodes[0], nil
}

// xrayServerEntries 取 settings.<key> 列表；Xray 各协议的服务器条目都挂在
// settings 下的某一个键里（vless/vmess 是 vnext，其余是 servers）。
func xrayServerEntries(settings map[string]any, key string) []map[string]any {
	if settings == nil {
		return nil
	}
	raw, ok := settings[key].([]any)
	if !ok {
		return nil
	}
	entries := make([]map[string]any, 0, len(raw))
	for _, item := range raw {
		if entry, ok := item.(map[string]any); ok {
			entries = append(entries, entry)
		}
	}
	return entries
}

// buildNodeFromXrayEntry 把一条服务器条目 + 共享的 streamSettings 拼成 mihomo 节点。
func buildNodeFromXrayEntry(nodeType string, entry map[string]any, stream map[string]any) map[string]any {
	address := xrayString(entry["address"])
	if address == "" {
		return nil
	}
	port, ok := xrayInt(entry["port"])
	if !ok {
		return nil
	}
	node := map[string]any{
		"type":   nodeType,
		"server": address,
		"port":   port,
	}

	users, _ := entry["users"].([]any)
	var user map[string]any
	if len(users) > 0 {
		user, _ = users[0].(map[string]any)
	}

	switch nodeType {
	case "vless":
		if user == nil {
			return nil
		}
		if id := xrayString(user["id"]); id != "" {
			node["uuid"] = id
		}
		if flow := xrayString(user["flow"]); flow != "" {
			node["flow"] = flow
		}
	case "vmess":
		if user == nil {
			return nil
		}
		if id := xrayString(user["id"]); id != "" {
			node["uuid"] = id
		}
		if alter, ok := xrayInt(user["alterId"]); ok {
			node["alterId"] = alter
		}
		// Xray 的 users[].security 就是 mihomo 的 cipher（auto/aes-128-gcm/...）。
		if cipher := xrayString(user["security"]); cipher != "" {
			node["cipher"] = cipher
		} else {
			node["cipher"] = "auto"
		}
	case "trojan":
		if password := xrayString(entry["password"]); password != "" {
			node["password"] = password
		}
	case "ss", "shadowsocks":
		if method := xrayString(entry["method"]); method != "" {
			node["cipher"] = method
		}
		if password := xrayString(entry["password"]); password != "" {
			node["password"] = password
		}
	case "socks", "socks5", "http":
		if user != nil {
			if name := xrayString(user["user"]); name != "" {
				node["username"] = name
			}
			if pass := xrayString(user["passwd"]); pass != "" {
				node["password"] = pass
			}
		}
	}

	applyXrayStream(node, nodeType, stream)
	return node
}

// applyXrayStream 把 streamSettings 翻译成 mihomo 的 network/传输层 opts/tls 组。
//
// TLS SNI 的 YAML 键按协议不同：vmess/vless 用 servername，trojan/http 用 sni
// （内核 outbound 结构体就是这么定义的，写错键会被静默忽略）。ss 没有独立的
// SNI 字段，跳过。
func applyXrayStream(node map[string]any, nodeType string, stream map[string]any) {
	if stream == nil {
		return
	}
	network := xrayString(stream["network"])
	switch network {
	case "", "raw", "tcp", "msg":
		// mihomo 的默认就是 tcp；但 Xray 可能用 tcpSettings 夹带 http 伪装。
		if tcpSettings, ok := stream["tcpSettings"].(map[string]any); ok {
			if header, _ := tcpSettings["header"].(map[string]any); header != nil &&
				xrayString(header["type"]) == "http" {
				node["network"] = "http"
				httpOpts := map[string]any{}
				if request, _ := header["request"].(map[string]any); request != nil {
					if path := xrayStringList(request["path"]); len(path) > 0 {
						httpOpts["path"] = path
					}
					if headers, _ := request["headers"].(map[string]any); headers != nil {
						httpOpts["headers"] = xrayHeaderMap(headers)
					}
				}
				if len(httpOpts) > 0 {
					node["http-opts"] = httpOpts
				}
			}
		}
	case "ws":
		node["network"] = "ws"
		if wsSettings, _ := stream["wsSettings"].(map[string]any); wsSettings != nil {
			wsOpts := map[string]any{}
			if path := xrayString(wsSettings["path"]); path != "" {
				wsOpts["path"] = path
			}
			if headers, _ := wsSettings["headers"].(map[string]any); headers != nil {
				wsOpts["headers"] = xrayHeaderMap(headers)
			}
			if len(wsOpts) > 0 {
				node["ws-opts"] = wsOpts
			}
		}
	case "grpc":
		node["network"] = "grpc"
		if grpcSettings, _ := stream["grpcSettings"].(map[string]any); grpcSettings != nil {
			if service := xrayString(grpcSettings["serviceName"]); service != "" {
				node["grpc-opts"] = map[string]any{"grpc-service-name": service}
			}
		}
	case "h2", "http1.1":
		node["network"] = "h2"
		if h2Settings, _ := stream["h2Settings"].(map[string]any); h2Settings != nil {
			h2Opts := map[string]any{}
			if host := xrayStringList(h2Settings["host"]); len(host) > 0 {
				h2Opts["host"] = host
			}
			if path := xrayString(h2Settings["path"]); path != "" {
				h2Opts["path"] = path
			}
			if len(h2Opts) > 0 {
				node["h2-opts"] = h2Opts
			}
		}
	case "httpupgrade":
		node["network"] = "httpupgrade"
		if settings, _ := stream["httpupgradeSettings"].(map[string]any); settings != nil {
			opts := map[string]any{}
			if path := xrayString(settings["path"]); path != "" {
				opts["path"] = path
			}
			if host := xrayString(settings["host"]); host != "" {
				opts["host"] = host
			}
			if len(opts) > 0 {
				node["httpupgrade-opts"] = opts
			}
		}
	case "xhttp", "splithttp":
		node["network"] = "xhttp"
		if settings, _ := stream["xhttpSettings"].(map[string]any); settings != nil {
			opts := map[string]any{}
			if path := xrayString(settings["path"]); path != "" {
				opts["path"] = path
			}
			if host := xrayString(settings["host"]); host != "" {
				opts["host"] = host
			}
			if len(opts) > 0 {
				node["xhttp-opts"] = opts
			}
		}
	}

	security := xrayString(stream["security"])
	sniKey := ""
	switch nodeType {
	case "trojan", "http":
		sniKey = "sni"
	case "vless", "vmess":
		sniKey = "servername"
	}
	tlsSettings, _ := stream["tlsSettings"].(map[string]any)
	realitySettings, _ := stream["realitySettings"].(map[string]any)
	switch security {
	case "tls":
		node["tls"] = true
		if tlsSettings != nil && sniKey != "" {
			if sni := xrayString(tlsSettings["serverName"]); sni != "" {
				node[sniKey] = sni
			}
		}
		applyXrayTLSCommon(node, tlsSettings)
	case "reality":
		node["tls"] = true
		if realitySettings != nil {
			realityOpts := map[string]any{}
			if publicKey := xrayString(realitySettings["publicKey"]); publicKey != "" {
				realityOpts["public-key"] = publicKey
			}
			if shortID := xrayString(realitySettings["shortId"]); shortID != "" {
				realityOpts["short-id"] = shortID
			}
			if len(realityOpts) > 0 {
				node["reality-opts"] = realityOpts
			}
			if fingerprint := xrayString(realitySettings["fingerprint"]); fingerprint != "" {
				node["client-fingerprint"] = fingerprint
			}
			if sni := xrayString(realitySettings["serverName"]); sni != "" && sniKey != "" {
				node[sniKey] = sni
			}
		}
	}
}

// applyXrayTLSCommon 抽出 tls/reality 共用的字段（alpn / allowInsecure）。
func applyXrayTLSCommon(node map[string]any, tlsSettings map[string]any) {
	if tlsSettings == nil {
		return
	}
	if allowInsecure, ok := xrayBool(tlsSettings["allowInsecure"]); ok && allowInsecure {
		node["skip-cert-verify"] = true
	}
	if alpn := xrayStringList(tlsSettings["alpn"]); len(alpn) > 0 {
		node["alpn"] = alpn
	}
}

// xrayHeaderMap 把 Xray 的 headers（值可为 string 或 []string）归一成 map[string]any。
func xrayHeaderMap(headers map[string]any) map[string]any {
	result := map[string]any{}
	for key, value := range headers {
		if text, ok := value.(string); ok {
			result[key] = text
			continue
		}
		if list := xrayStringList(value); len(list) > 0 {
			result[key] = list[0]
		}
	}
	return result
}

// ---- 小工具：Xray JSON 经 yamlv3 解码后的取值都走这里做类型兼容 ----

func xrayString(value any) string {
	switch typed := value.(type) {
	case string:
		return typed
	case []any:
		if len(typed) > 0 {
			return xrayString(typed[0])
		}
	}
	return ""
}

func xrayInt(value any) (int, bool) {
	switch typed := value.(type) {
	case int:
		return typed, true
	case int64:
		return int(typed), true
	case uint64:
		return int(typed), true
	case float64:
		return int(typed), true
	case string:
		var parsed int
		if _, err := fmt.Sscanf(typed, "%d", &parsed); err == nil {
			return parsed, true
		}
	}
	return 0, false
}

func xrayBool(value any) (bool, bool) {
	if typed, ok := value.(bool); ok {
		return typed, true
	}
	return false, false
}

func xrayStringList(value any) []string {
	list, ok := value.([]any)
	if !ok {
		return nil
	}
	result := make([]string, 0, len(list))
	for _, item := range list {
		if text, ok := item.(string); ok {
			result = append(result, text)
		}
	}
	return result
}
