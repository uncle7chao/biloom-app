package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"

	"github.com/metacubex/mihomo/common/convert"
	yamlv3 "gopkg.in/yaml.v3"
)

// BiLoom: 配置编辑层。
//
// 「新增节点」本质上是往一份**已经存在**的 Clash 配置里追加内容。它和订阅导入的
// 输入性质相反，所以要求也相反：
//
//   - 订阅导入可以把整份配置重新生成 —— 反正是内核自己 marshal 出来的，没有别的东西；
//   - 配置编辑**必须原样保留用户配置的其余部分**：注释、缩进、以及我们这版内核还
//     不认识的新字段，一个都不能丢。
//
// 所以这里一律走 yaml.v3 的 Node 级局部改写：解析成语法树，只动 proxies 这一个
// 节点，其余节点原样带回（补默认分组那条路会额外动 proxy-groups 与 rules，但只在
// 它们确实缺失时才动手）。
//
// **为什么这里没有对应的「添加策略组」**：上游 FlClash 已经有一套完整的自定义策略组
// 编辑（views/profiles/overwrite/custom/groups.dart —— 支持 select / url-test /
// fallback / load-balance 四种类型、成员多选、过滤与测速参数），而且它把结果存在
// **独立的覆写数据**里，订阅更新冲不掉。再在这里实现一套「往 profile 文件追加组」
// 只会形成两条并存的路线，而且改文件那一版对订阅配置是有害的（下次更新订阅就没了）。
// 所以「添加策略组」的入口直接指向那个现成页面，内核不重复实现。
//
// **链式代理为什么在这里、而且只能在这里**（2026-09-23 更正，上一轮我判断错了）：
// 链式代理不是分组类型。Clash 早期的 `type: relay` 分组在本内核已被删除 ——
// `adapter/outboundgroup/parser.go:216` 对它直接返回错误，写出来会让**整份配置加载
// 失败**（不是警告、不是静默忽略）。上游现成的组编辑页里那个 Relay 选项因此是碰不得的。
// 现在的做法是代理级的 `dialer-proxy` 字段（`adapter/outbound/base.go:199`）：写
// `X.dialer-proxy: Y` 表示 X 通过 Y 建立连接，即 Y 是前置、X 是出口。它有两个特点
// 决定了它只能落在配置编辑这条路上：
//
//   - 它是 **proxy 级**字段，覆写层存的是「策略组 + 规则」，没有地方放它（要加就得
//     动数据库表结构，那是上游级别的改动）；
//   - 它可以指向**策略组名**，所以 UI 得能同时列出节点与分组，而候选名单只能从配置读。
//
// 代价与「新增节点」一样：写的是 profile 文件，订阅配置下次更新会冲掉 —— 界面那条
// 「转为本地配置」的提示同样适用。反过来说，链式代理本来就是一次设定好长期不变的
// 东西，转为本地配置对它比对新增节点更自然。
//
// 为什么不能用 config.RawConfig 解析再序列化（订阅转换那条路就是这么做的）：
// RawConfig 没有 `yaml:",inline"` 兜底字段（core/Clash.Meta/config/config.go:399
// 最后一个字段是 ClashForAndroid），它会**静默丢掉所有它不认识的顶层键**，注释
// 也一并消失 —— 用户手写的配置会被改残，而且不报错。订阅导入走那条路没问题，
// 因为输入本来就是内核生成的；这里不行。
//
// 代价是序列化时排版会被规范化（缩进统一、flow 风格展开），换来的是内容零丢失。
// 反过来做「纯文本插入」虽然能连排版都不动，但要自己处理 proxies 在文件末尾 /
// flow 风格 / 缩进推断等边界，一旦出错产出的是**非法 YAML**（配置直接加载失败），
// 比丢排版严重得多。

// profileDocument 把配置文本解析成可局部改写的语法树。
//
// 空配置（新建的空白配置）不是错误：用户完全可能新建一个空白配置再往里加节点，
// 这时给一棵只有一个空映射的树，后续追加逻辑就能照常工作。
func profileDocument(buf []byte) (*yamlv3.Node, *yamlv3.Node, error) {
	if strings.TrimSpace(stripBOM(string(buf))) == "" {
		root := &yamlv3.Node{Kind: yamlv3.MappingNode, Tag: "!!map"}
		return &yamlv3.Node{Kind: yamlv3.DocumentNode, Content: []*yamlv3.Node{root}}, root, nil
	}
	var doc yamlv3.Node
	if err := yamlv3.Unmarshal(buf, &doc); err != nil {
		return nil, nil, fmt.Errorf("配置内容不是合法的 YAML: %w", err)
	}
	if doc.Kind != yamlv3.DocumentNode || len(doc.Content) == 0 {
		return nil, nil, errors.New("配置内容为空")
	}
	root := doc.Content[0]
	if root.Kind != yamlv3.MappingNode {
		return nil, nil, errors.New("配置的顶层不是「键: 值」结构")
	}
	return &doc, root, nil
}

// marshalDocument 把语法树写回 YAML 文本。
//
// 用 Encoder 而不是 yaml.Marshal：两者对 Node 的输出一致，但 Encoder 能拿到
// 明确的错误与 Close 时机，不必依赖包级函数里的 panic/recover。
func marshalDocument(doc *yamlv3.Node) (string, error) {
	var builder strings.Builder
	encoder := yamlv3.NewEncoder(&builder)
	if err := encoder.Encode(doc); err != nil {
		return "", fmt.Errorf("配置无法序列化: %w", err)
	}
	if err := encoder.Close(); err != nil {
		return "", fmt.Errorf("配置无法序列化: %w", err)
	}
	return builder.String(), nil
}

// mappingEntry 在映射节点里按键取值，同时返回值在 Content 里的下标。
// 找不到时返回 (nil, -1)。
func mappingEntry(mapping *yamlv3.Node, key string) (*yamlv3.Node, int) {
	if mapping == nil || mapping.Kind != yamlv3.MappingNode {
		return nil, -1
	}
	for index := 0; index+1 < len(mapping.Content); index += 2 {
		if mapping.Content[index].Value == key {
			return mapping.Content[index+1], index + 1
		}
	}
	return nil, -1
}

// valueNodes 把结构化条目转成语法树节点，供挂进配置。
func valueNodes(values []map[string]any) ([]*yamlv3.Node, error) {
	result := make([]*yamlv3.Node, 0, len(values))
	for _, value := range values {
		buf, err := yamlv3.Marshal(value)
		if err != nil {
			return nil, fmt.Errorf("条目无法序列化: %w", err)
		}
		var doc yamlv3.Node
		if err := yamlv3.Unmarshal(buf, &doc); err != nil {
			return nil, fmt.Errorf("条目无法解析: %w", err)
		}
		if len(doc.Content) == 0 {
			continue
		}
		child := doc.Content[0]
		child.Anchor = ""
		result = append(result, child)
	}
	return result, nil
}

// appendToSequence 往顶层某个列表键追加节点，键不存在时新建。
func appendToSequence(root *yamlv3.Node, key string, children []*yamlv3.Node) error {
	if len(children) == 0 {
		return nil
	}
	sequence, _ := mappingEntry(root, key)
	if sequence == nil {
		sequence = &yamlv3.Node{Kind: yamlv3.SequenceNode, Tag: "!!seq"}
		root.Content = append(
			root.Content,
			&yamlv3.Node{Kind: yamlv3.ScalarNode, Tag: "!!str", Value: key},
			sequence,
		)
	}
	if sequence.Kind != yamlv3.SequenceNode {
		return fmt.Errorf("配置里的 %s 不是一个列表", key)
	}
	sequence.Content = append(sequence.Content, children...)
	return nil
}

// existingNames 收集配置里已占用的名字。
//
// 节点名、策略组名、proxy-provider 名在 Clash 里共用同一个命名空间，任何一处
// 重名都会让整份配置加载失败 —— 所以新增前必须把三类都算进来，只看 proxies
// 会漏掉「节点名撞了策略组名」这种真实会发生的冲突。
func existingNames(root *yamlv3.Node) map[string]bool {
	names := make(map[string]bool)
	collect := func(key string) {
		sequence, _ := mappingEntry(root, key)
		if sequence == nil || sequence.Kind != yamlv3.SequenceNode {
			return
		}
		for _, item := range sequence.Content {
			if name, _ := mappingEntry(item, "name"); name != nil {
				names[name.Value] = true
			}
		}
	}
	collect("proxies")
	collect("proxy-groups")
	collect("listeners")

	// proxy-providers 是 `名字: {…}` 形式的映射，键即名字，取值方式与上面不同。
	if providers, _ := mappingEntry(root, "proxy-providers"); providers != nil &&
		providers.Kind == yamlv3.MappingNode {
		for index := 0; index+1 < len(providers.Content); index += 2 {
			names[providers.Content[index].Value] = true
		}
	}
	return names
}

// parseProxyNodes 解析用户粘贴的内容，得出要追加的代理条目。
//
// 两种输入共用同一条出口：分享链接交给内核 convert 包（proxy-provider 路径上一直
// 在用它，覆盖 vless/vmess/trojan/ss/ssr/hysteria2/tuic/anytls/mieru 以及 ws/grpc/h2/
// xhttp/httpupgrade 等传输，还自带 base64 解码），YAML 片段直接解出来 —— 自己再写
// 一遍解析只会跟着内核漂移。
func parseProxyNodes(text string) ([]map[string]any, error) {
	trimmed := strings.TrimSpace(stripBOM(text))
	if trimmed == "" {
		return nil, errors.New("没有可用的内容")
	}
	if containsShareLink(trimmed, 0) {
		nodes, err := convert.ConvertsV2Ray([]byte(trimmed))
		if err != nil {
			return nil, fmt.Errorf("分享链接解析失败: %w", err)
		}
		if len(nodes) == 0 {
			return nil, errors.New("没有从分享链接里解析出节点")
		}
		// 链接没写 #名字 的条目由这里补自动名，而不是报「缺少 name」——
		// V2rayN 等工具导出的链接经常不带片段，报错等于把锅甩给用户。
		fillMissingShareNames(nodes)
		return normalizeProxyMaps(nodes, "分享链接")
	}
	return parseProxyFragment(trimmed)
}

// parseProxyFragment 解析 YAML 片段。
//
// 三种写法都收：整份 `proxies:` 前缀、裸的条目列表、以及单个节点（用户从别处
// 只拷了一条出来）。报错定位到具体第几条，而不是笼统地说「格式不对」。
func parseProxyFragment(text string) ([]map[string]any, error) {
	var value any
	if err := yamlv3.Unmarshal([]byte(text), &value); err != nil {
		return nil, errors.New(
			"既不是分享链接，也不是合法的 YAML 片段；" +
				"分享链接请以 vmess:// vless:// ss:// 等开头，YAML 片段每一条至少要有 name 与 type",
		)
	}
	switch typed := value.(type) {
	case []any:
		return normalizeProxyList(typed, "YAML 片段")
	case map[string]any:
		if raw, ok := typed["proxies"]; ok {
			list, ok := raw.([]any)
			if !ok {
				return nil, errors.New("片段里的 proxies 不是一个列表")
			}
			return normalizeProxyList(list, "YAML 片段")
		}
		if _, ok := typed["name"]; ok {
			return []map[string]any{typed}, nil
		}
		// V2rayN / Xray 导出的 JSON：整份配置带 outbounds，或用户只拷了单个
		// outbound（有 protocol + settings，没有 name/type）。JSON 是 YAML 子集，
		// 所以它们会一路走到这里 —— 在放弃之前先做一次自动转化。
		// sing-box 的节点同样住在 outbounds 里，但它用 type 标类型（Xray 用
		// protocol），且字段是 server/server_port 这套下划线命名 —— 两条转化路线
		// 按 outbound 的判别键分流，订阅侧的 convertSingBoxSubscription 原样复用。
		if raw, ok := typed["outbounds"]; ok {
			if xrayStyleOutbounds(raw) {
				return convertXrayConfig(typed)
			}
			return convertSingBoxSubscription([]byte(text))
		}
		if _, ok := typed["protocol"]; ok {
			if nodes, err := convertXrayConfig(
				map[string]any{"outbounds": []any{typed}},
			); err == nil && len(nodes) > 0 {
				return nodes, nil
			}
		}
		if _, ok := typed["type"]; ok {
			// sing-box 单 outbound（type + server + server_port，没有 name）。
			if _, hasServer := typed["server"]; hasServer {
				if _, hasPort := typed["server_port"]; hasPort {
					wrapped, err := json.Marshal(
						map[string]any{"outbounds": []any{typed}},
					)
					if err == nil {
						return convertSingBoxSubscription(wrapped)
					}
				}
			}
		}
		return nil, errors.New("YAML 片段里没找到节点：每条节点至少要有 name")
	}
	return nil, errors.New("YAML 片段里没找到节点")
}

// fillMissingShareNames 给没有 #名字 的分享链接条目补自动名。
//
// 分享链接的节点名来自 URL 的 #片段，V2rayN 等工具导出的链接经常不带，转换器
// 会给出空名。按 sing-box 路线的同一套约定生成 `地址:端口`，批内重名追加
// -2、-3（uniqueShareName 的规则）。连地址都没有的条目不硬编名字，交给后面的
// 校验去报真实问题。
func fillMissingShareNames(nodes []map[string]any) {
	names := make(map[string]int, len(nodes))
	for _, node := range nodes {
		if name := scalarToString(node["name"]); name != "" {
			names[name]++
			continue
		}
		server := scalarToString(node["server"])
		port := scalarToString(node["port"])
		name := server
		if port != "" {
			if name == "" {
				name = port
			} else {
				name = name + ":" + port
			}
		}
		if name == "" {
			continue
		}
		node["name"] = uniqueShareName(names, name)
	}
}

// asString 把 YAML/JSON 解出来的标量转成TrimSpace 后的字符串 —— 端口在两条
// 转换路线上分别是 int 和 string，判定键需要统一形态。
func scalarToString(value any) string {
	switch typed := value.(type) {
	case string:
		return strings.TrimSpace(typed)
	case int:
		return fmt.Sprintf("%d", typed)
	case int64:
		return fmt.Sprintf("%d", typed)
	case float64:
		return fmt.Sprintf("%d", int(typed))
	}
	return ""
}

// proxyIdentity 是「同一个节点」的判定键：协议|地址|端口|password|uuid。
//
// 名字去重拦不住「同一个节点换个名字再加一遍」—— 分享链接的名字来自 #片段、
// 导出配置的名字是自动生成的，两者必然不同，但连的是同一台服务器。凭据参与
// 判定：同一地址上不同账号（多用户端口）算不同节点，不误伤。
func proxyIdentity(node map[string]any) string {
	return strings.Join([]string{
		strings.ToLower(scalarToString(node["type"])),
		scalarToString(node["server"]),
		scalarToString(node["port"]),
		scalarToString(node["password"]),
		scalarToString(node["uuid"]),
	}, "|")
}

// collectProxyIdentities 收集配置里已有节点的身份键。
func collectProxyIdentities(root *yamlv3.Node) (map[string]bool, error) {
	identities := make(map[string]bool)
	sequence, _ := mappingEntry(root, "proxies")
	if sequence == nil || sequence.Kind != yamlv3.SequenceNode {
		return identities, nil
	}
	var proxies []map[string]any
	if err := sequence.Decode(&proxies); err != nil {
		return nil, fmt.Errorf("读取节点列表失败: %w", err)
	}
	for _, node := range proxies {
		if identity := proxyIdentity(node); identity != "||||" {
			identities[identity] = true
		}
	}
	return identities, nil
}

// normalizeProxyMaps 校验结构化条目 —— 分享链接转换器的输出已经是这个形状。
func normalizeProxyMaps(nodes []map[string]any, source string) ([]map[string]any, error) {
	if len(nodes) == 0 {
		return nil, fmt.Errorf("%s里没有节点", source)
	}
	for index, node := range nodes {
		if name, _ := node["name"].(string); strings.TrimSpace(name) == "" {
			return nil, fmt.Errorf("%s第 %d 条缺少 name", source, index+1)
		}
	}
	return nodes, nil
}

// normalizeProxyList 校验 YAML 解出来的条目列表 —— 元素要先确认是映射。
func normalizeProxyList(items []any, source string) ([]map[string]any, error) {
	if len(items) == 0 {
		return nil, fmt.Errorf("%s里没有节点", source)
	}
	result := make([]map[string]any, 0, len(items))
	for index, item := range items {
		node, ok := item.(map[string]any)
		if !ok {
			return nil, fmt.Errorf("%s第 %d 条不是「键: 值」结构", source, index+1)
		}
		if name, _ := node["name"].(string); strings.TrimSpace(name) == "" {
			return nil, fmt.Errorf("%s第 %d 条缺少 name", source, index+1)
		}
		result = append(result, node)
	}
	return result, nil
}

// ensureUsableDefaults 给「有节点但没有任何策略组」的配置补上默认分组与兜底规则。
//
// 判据刻意收紧到 `proxy-groups 缺失或为空 && proxies 非空`：只要配置里已经有分组
// 就一律不碰 —— 那是服务商或用户自己的设计，覆盖它才是真正的伤害。
//
// 规则分两种补法，不混：原本没有 rules 时补一整套默认规则（缺了它流量全走 DIRECT，
// 用户看到的是「已连接但网页打不开」）；原本有 rules 时只追加一条 MATCH 兜底
// （缺了它，所有规则都不命中的连接会被内核交给 DIRECT，同样等于没代理），
// 已有规则一条都不动。
func ensureUsableDefaults(root *yamlv3.Node) (bool, int, error) {
	groups, _ := mappingEntry(root, "proxy-groups")
	if groups != nil && groups.Kind == yamlv3.SequenceNode && len(groups.Content) > 0 {
		return false, 0, nil
	}
	proxiesNode, _ := mappingEntry(root, "proxies")
	if proxiesNode == nil || proxiesNode.Kind != yamlv3.SequenceNode ||
		len(proxiesNode.Content) == 0 {
		return false, 0, nil
	}

	var proxies []map[string]any
	if err := proxiesNode.Decode(&proxies); err != nil {
		return false, 0, fmt.Errorf("读取节点列表失败: %w", err)
	}
	defaultGroups, rules := defaultSubscriptionGroups(proxies)

	groupNodes, err := valueNodes(defaultGroups)
	if err != nil {
		return false, 0, err
	}
	if groups == nil {
		if err := appendToSequence(root, "proxy-groups", groupNodes); err != nil {
			return false, 0, err
		}
	} else {
		// 存在但为空（`proxy-groups: []` 或 null）：就地填充，保留它原有的位置。
		groups.Kind = yamlv3.SequenceNode
		groups.Tag = "!!seq"
		groups.Value = ""
		groups.Content = groupNodes
	}

	rulesNode, _ := mappingEntry(root, "rules")
	switch {
	case rulesNode == nil:
		ruleNodes := make([]*yamlv3.Node, 0, len(rules))
		for _, rule := range rules {
			ruleNodes = append(ruleNodes, &yamlv3.Node{
				Kind:  yamlv3.ScalarNode,
				Tag:   "!!str",
				Value: rule,
			})
		}
		if err := appendToSequence(root, "rules", ruleNodes); err != nil {
			return false, 0, err
		}
	case rulesNode.Kind == yamlv3.SequenceNode:
		hasMatch := false
		for _, item := range rulesNode.Content {
			if strings.HasPrefix(strings.ToUpper(strings.TrimSpace(item.Value)), "MATCH") {
				hasMatch = true
				break
			}
		}
		if !hasMatch {
			rulesNode.Content = append(rulesNode.Content, &yamlv3.Node{
				Kind:  yamlv3.ScalarNode,
				Tag:   "!!str",
				Value: rules[len(rules)-1],
			})
		}
	}
	return true, len(proxies), nil
}

// healUngroupedProxies 把「不属于任何策略组的节点」接回默认锚点分组。
//
// 背景（2026-09-25 用户报障「新增节点不显示」）：默认分组只在 proxy-groups 缺失/
// 为空的那一刻注入（ensureUsableDefaults），注入内容是**当时**的全部节点。之后
// 用户再加节点，节点只落进 proxies——不属于任何组。而「代理」页由分组驱动、
// 规则模式下 GLOBAL 兜底组会被隐藏、分流规则也只指向组：结果就是节点加进去了，
// 页面上看不见，选也选不到，等于白加。
//
// 治法：找出游离节点（没被任何分组的成员列表引用的 proxies 条目），追加进默认
// 锚点组（节点选择/自动选择/故障转移，见 subscription_defaults.go）里**已存在**
// 的那些，恢复「锚点组引用全部节点」的模板不变量。三条边界：
//   - 只动锚点组 —— 服务商或用户自建的分组的成员列表一个不碰；
//   - 锚点组一个都不在时不碰任何东西 —— 那种配置有自己的分组设计，把节点塞进
//     哪个组该由用户决定（「按地区生成分组」就是干这个的）；
//   - 幂等 —— 已被组引用的节点不重复追加；没有游离节点时一个字节都不动。
func healUngroupedProxies(root *yamlv3.Node) (bool, error) {
	proxiesNode, _ := mappingEntry(root, "proxies")
	if proxiesNode == nil || proxiesNode.Kind != yamlv3.SequenceNode ||
		len(proxiesNode.Content) == 0 {
		return false, nil
	}
	groupsNode, _ := mappingEntry(root, "proxy-groups")
	if groupsNode == nil || groupsNode.Kind != yamlv3.SequenceNode ||
		len(groupsNode.Content) == 0 {
		return false, nil
	}

	anchorNames := map[string]bool{
		defaultGroupProxies:  true,
		defaultGroupAuto:     true,
		defaultGroupFallback: true,
	}
	referenced := map[string]bool{}
	var anchorGroups []*yamlv3.Node
	for _, item := range groupsNode.Content {
		if item.Kind != yamlv3.MappingNode {
			continue
		}
		name := scalarValue(item, "name")
		if name == "" {
			continue
		}
		referenced[name] = true
		members, _ := mappingEntry(item, "proxies")
		if members != nil && members.Kind == yamlv3.SequenceNode {
			for _, m := range members.Content {
				if m.Kind == yamlv3.ScalarNode && m.Value != "" {
					referenced[m.Value] = true
				}
			}
		}
		if anchorNames[name] {
			anchorGroups = append(anchorGroups, item)
		}
	}
	if len(anchorGroups) == 0 {
		return false, nil
	}

	// 按配置里的顺序收集游离节点（而不是 map 遍历），追加时保持可预期的顺序。
	ungrouped := make([]string, 0)
	for _, item := range proxiesNode.Content {
		if item.Kind != yamlv3.MappingNode {
			continue
		}
		name := scalarValue(item, "name")
		if name == "" || referenced[name] {
			continue
		}
		ungrouped = append(ungrouped, name)
	}
	if len(ungrouped) == 0 {
		return false, nil
	}

	changed := false
	for _, group := range anchorGroups {
		members, _ := mappingEntry(group, "proxies")
		if members == nil || members.Kind != yamlv3.SequenceNode {
			continue
		}
		inGroup := map[string]bool{}
		for _, m := range members.Content {
			if m.Kind == yamlv3.ScalarNode {
				inGroup[m.Value] = true
			}
		}
		for _, name := range ungrouped {
			if inGroup[name] {
				continue
			}
			members.Content = append(members.Content, &yamlv3.Node{
				Kind:  yamlv3.ScalarNode,
				Tag:   "!!str",
				Value: name,
			})
			inGroup[name] = true
			changed = true
		}
	}
	return changed, nil
}

// patchMissingDefaults 给「有节点但没有策略组」的 Clash 配置补上默认分组与兜底规则。
//
// 返回的 changed 为 false 时表示**一个字节都没动**，调用方必须原样使用输入 ——
// 这是这条路线的全部安全性来源：正常配置（有分组）走不到序列化，排版与注释
// 完全不受影响。
func patchMissingDefaults(buf []byte) ([]byte, bool, int, error) {
	doc, root, err := profileDocument(buf)
	if err != nil {
		return nil, false, 0, err
	}
	changed, nodeCount, err := ensureUsableDefaults(root)
	if err != nil {
		return nil, false, 0, err
	}
	// 游离节点治理：刚注入默认分组时它必然是 no-op（注入的组本来就引用了全部
	// 节点）；已带分组的配置则靠它把「注入之后才加的节点」接回来 —— 用户点一次
	// 「更新」，历史游离节点就全部回到分组里。
	healed, err := healUngroupedProxies(root)
	if err != nil {
		return nil, false, 0, err
	}
	if !changed && !healed {
		return nil, false, 0, nil
	}
	out, err := marshalDocument(doc)
	if err != nil {
		return nil, false, 0, err
	}
	return []byte(out), true, nodeCount, nil
}

// handleAddProxyNodes 往配置里追加节点。
func handleAddProxyNodes(params *AddProxyNodesParams) (AddProxyNodesResult, error) {
	doc, root, err := profileDocument([]byte(params.YAML))
	if err != nil {
		return AddProxyNodesResult{}, err
	}
	nodes, err := parseProxyNodes(params.Nodes)
	if err != nil {
		return AddProxyNodesResult{}, err
	}

	// 重名一律跳过而不是自动改名。Clash 里同名会让整份配置加载失败，所以两个
	// 绝不能都留下；而自动改名会让节点列表里冒出用户没写过的名字（「HK 01 2」），
	// 他之后再想找自己刚加的那条就找不到了。跳过并如实回报，用户自己决定要不要
	// 先删旧的。
	//
	// 名字之外再做一层**身份去重**（协议+地址+端口+凭据）：同一个节点用分享链接
	// 加过一次、又用导出配置加一次，两边的名字必然不同（片段名 vs 自动名），
	// 光查名字拦不住，但它们连的是同一台服务器 —— 也跳过并如实回报。
	used := existingNames(root)
	identities, err := collectProxyIdentities(root)
	if err != nil {
		return AddProxyNodesResult{}, err
	}
	added := make([]string, 0, len(nodes))
	skipped := make([]string, 0)
	accepted := make([]map[string]any, 0, len(nodes))
	pending := make(map[string]bool, len(nodes))
	for _, node := range nodes {
		name, _ := node["name"].(string)
		name = strings.TrimSpace(name)
		if used[name] || pending[name] {
			skipped = append(skipped, name)
			continue
		}
		if identity := proxyIdentity(node); identity != "||||" {
			if identities[identity] {
				skipped = append(skipped, name)
				continue
			}
			identities[identity] = true
		}
		pending[name] = true
		added = append(added, name)
		accepted = append(accepted, node)
	}

	if len(accepted) > 0 {
		children, err := valueNodes(accepted)
		if err != nil {
			return AddProxyNodesResult{}, err
		}
		if err := appendToSequence(root, "proxies", children); err != nil {
			return AddProxyNodesResult{}, err
		}
		if _, _, err := ensureUsableDefaults(root); err != nil {
			return AddProxyNodesResult{}, err
		}
		// 配置已有分组时上一行是 no-op，新节点就成了游离节点（页面上看不见、
		// 分流也用不上）。把新节点接回锚点组；顺带治好历史上同根因的游离节点。
		if _, err := healUngroupedProxies(root); err != nil {
			return AddProxyNodesResult{}, err
		}
	}

	out, err := marshalDocument(doc)
	if err != nil {
		return AddProxyNodesResult{}, err
	}
	return AddProxyNodesResult{YAML: out, Added: added, Skipped: skipped}, nil
}

// handleRemoveProxyNodes 从配置里删除节点。
//
// 删节点不只是从 proxies 里抠掉几行：所有引用被删名字的地方都要同步清理，漏掉
// 任何一处整份配置加载失败 ——
//   - 策略组的 proxies 成员（成员被删空时补 DIRECT 保住组的合法性）；
//   - 规则的出口（规则可以直接指向节点名；兜底的 MATCH 规则改写回 DIRECT，
//     其余规则删掉）；
//   - listeners 的 proxy 字段（删掉该字段让它回落默认行为，不整条删 listener）。
//
// 只动 proxies/proxy-groups/rules/listeners 四处，注释、排版与其余内容原样保留
//（同 handleAddProxyNodes 的文档级编辑模式）。没找到的名字如实回传 missing。
func handleRemoveProxyNodes(params *RemoveProxyNodesParams) (RemoveProxyNodesResult, error) {
	requested := make(map[string]bool, len(params.Names))
	for _, name := range params.Names {
		if trimmed := strings.TrimSpace(name); trimmed != "" {
			requested[trimmed] = true
		}
	}
	if len(requested) == 0 {
		return RemoveProxyNodesResult{}, errors.New("没有指定要删除的节点")
	}

	doc, root, err := profileDocument([]byte(params.YAML))
	if err != nil {
		return RemoveProxyNodesResult{}, err
	}

	// ① proxies：主体。
	removedSet := make(map[string]bool, len(requested))
	if proxies, _ := mappingEntry(root, "proxies"); proxies != nil &&
		proxies.Kind == yamlv3.SequenceNode {
		kept := make([]*yamlv3.Node, 0, len(proxies.Content))
		for _, item := range proxies.Content {
			name := scalarValue(item, "name")
			if requested[name] {
				removedSet[name] = true
				continue
			}
			kept = append(kept, item)
		}
		proxies.Content = kept
	}

	// ② 策略组成员。
	if groups, _ := mappingEntry(root, "proxy-groups"); groups != nil &&
		groups.Kind == yamlv3.SequenceNode {
		for _, group := range groups.Content {
			members, _ := mappingEntry(group, "proxies")
			if members == nil || members.Kind != yamlv3.SequenceNode {
				continue
			}
			kept := make([]*yamlv3.Node, 0, len(members.Content))
			changed := false
			for _, member := range members.Content {
				if member.Kind == yamlv3.ScalarNode && requested[member.Value] {
					changed = true
					continue
				}
				kept = append(kept, member)
			}
			if changed && len(kept) == 0 {
				// Clash 要求组的 proxies 非空；删空了就补 DIRECT 兜底。
				kept = append(kept, &yamlv3.Node{
					Kind:  yamlv3.ScalarNode,
					Tag:   "!!str",
					Value: "DIRECT",
				})
			}
			if changed {
				members.Content = kept
			}
		}
	}

	// ③ 规则出口。规则形态：`TYPE,payload,target[,no-resolve]` 或 `MATCH,target`，
	// 目标段总是倒数第一段（有 no-resolve 时倒数第二段）。逻辑规则（AND/OR/NOT）
	// 的 payload 自带逗号，但目标同样是最后一段，这套判定对它们也成立。
	if rules, _ := mappingEntry(root, "rules"); rules != nil &&
		rules.Kind == yamlv3.SequenceNode {
		kept := make([]*yamlv3.Node, 0, len(rules.Content))
		for _, rule := range rules.Content {
			if rule.Kind != yamlv3.ScalarNode {
				kept = append(kept, rule)
				continue
			}
			parts := strings.Split(rule.Value, ",")
			target := parts[len(parts)-1]
			if target == "no-resolve" && len(parts) >= 3 {
				target = parts[len(parts)-2]
			}
			if !requested[strings.TrimSpace(target)] {
				kept = append(kept, rule)
				continue
			}
			if strings.HasPrefix(strings.TrimSpace(rule.Value), "MATCH,") {
				// 兜底规则不能删（删了所有未命中流量交给内核默认行为），
				// 改回 DIRECT 保住语义。
				kept = append(kept, &yamlv3.Node{
					Kind:  yamlv3.ScalarNode,
					Tag:   "!!str",
					Value: "MATCH,DIRECT",
				})
			}
			// 其余指向被删节点的规则直接去掉：那条规则描述的分流对象已经不存在。
		}
		rules.Content = kept
	}

	// ④ listeners 的 proxy 字段。
	if listeners, _ := mappingEntry(root, "listeners"); listeners != nil &&
		listeners.Kind == yamlv3.SequenceNode {
		for _, listener := range listeners.Content {
			if proxyNode, _ := mappingEntry(listener, "proxy"); proxyNode != nil &&
				requested[proxyNode.Value] {
				removeMappingValue(listener, "proxy")
			}
		}
	}

	removed := make([]string, 0, len(requested))
	missing := make([]string, 0)
	for _, name := range params.Names {
		trimmed := strings.TrimSpace(name)
		if trimmed == "" {
			continue
		}
		if removedSet[trimmed] {
			if !containsString(removed, trimmed) {
				removed = append(removed, trimmed)
			}
			continue
		}
		if !containsString(missing, trimmed) {
			missing = append(missing, trimmed)
		}
	}
	if len(removed) == 0 {
		return RemoveProxyNodesResult{}, errors.New(
			"配置里找不到要删除的节点；请先刷新面板",
		)
	}
	out, err := marshalDocument(doc)
	if err != nil {
		return RemoveProxyNodesResult{}, err
	}
	return RemoveProxyNodesResult{YAML: out, Removed: removed, Missing: missing}, nil
}

// handleUpdateProxyNode 原地更新一个节点的参数。
//
// 编辑的语义是「参数变了、身份没变」：策略组成员、规则出口、链式引用全都
// 用**名字**锚定这个节点，所以名字不许改（想改名 = 删除 + 重新添加，那是
// 两个动作、两次确认，混进编辑里用户会以为引用还在）。实现上用新片段
// **整体替换**旧条目而不是字段级合并 —— 合并救不了「用户删掉了一个字段」
// 的场景（比如去掉 ws-opts），整体替换语义最直白：编辑器里看到什么，落盘
// 就是什么。
//
// 只动 proxies 里这一个条目，注释、排版与其余内容原样保留（文档级编辑模式）。
func handleUpdateProxyNode(params *UpdateProxyNodeParams) (UpdateProxyNodeResult, error) {
	name := strings.TrimSpace(params.Name)
	if name == "" {
		return UpdateProxyNodeResult{}, errors.New("没有指定要更新的节点")
	}
	doc, root, err := profileDocument([]byte(params.YAML))
	if err != nil {
		return UpdateProxyNodeResult{}, err
	}
	nodes, err := parseProxyNodes(params.Node)
	if err != nil {
		return UpdateProxyNodeResult{}, err
	}
	if len(nodes) != 1 {
		return UpdateProxyNodeResult{}, errors.New(
			"节点片段必须恰好包含一个节点",
		)
	}
	node := nodes[0]
	newName := strings.TrimSpace(scalarToString(node["name"]))
	if newName != name {
		return UpdateProxyNodeResult{}, errors.New(
			"不允许在编辑中修改节点名；改名请删除后重新添加",
		)
	}

	// 身份去重：编辑后如果和另一个节点的 协议|地址|端口|凭据 完全相同，
	// 等于变相造出一个重复节点 —— 同名会加载失败，不同名则列表里出现两条
	// 分不清的记录。排除自身后再查。
	var existing []map[string]any
	if proxies, _ := mappingEntry(root, "proxies"); proxies != nil &&
		proxies.Kind == yamlv3.SequenceNode {
		if err := proxies.Decode(&existing); err != nil {
			return UpdateProxyNodeResult{}, fmt.Errorf("读取节点列表失败: %w", err)
		}
	}
	if identity := proxyIdentity(node); identity != "||||" {
		for _, other := range existing {
			if strings.TrimSpace(scalarToString(other["name"])) == name {
				continue
			}
			if proxyIdentity(other) == identity {
				return UpdateProxyNodeResult{}, errors.New(
					"另一个节点已是相同的地址/端口/凭据；请直接编辑那个节点",
				)
			}
		}
	}

	proxies, _ := mappingEntry(root, "proxies")
	if proxies == nil || proxies.Kind != yamlv3.SequenceNode {
		return UpdateProxyNodeResult{}, errors.New("配置里没有 proxies 段")
	}
	index := -1
	for i, item := range proxies.Content {
		if scalarValue(item, "name") == name {
			index = i
			break
		}
	}
	if index == -1 {
		return UpdateProxyNodeResult{}, errors.New(
			"配置里找不到要更新的节点；请先刷新面板",
		)
	}
	children, err := valueNodes([]map[string]any{node})
	if err != nil {
		return UpdateProxyNodeResult{}, err
	}
	proxies.Content[index] = children[0]

	out, err := marshalDocument(doc)
	if err != nil {
		return UpdateProxyNodeResult{}, err
	}
	return UpdateProxyNodeResult{YAML: out, Updated: name}, nil
}

func containsString(list []string, target string) bool {
	for _, item := range list {
		if item == target {
			return true
		}
	}
	return false
}

// scalarValue 读一个标量字段，取不到时返回空串。
func scalarValue(node *yamlv3.Node, key string) string {
	value, _ := mappingEntry(node, key)
	if value == nil || value.Kind != yamlv3.ScalarNode {
		return ""
	}
	return strings.TrimSpace(value.Value)
}

// setMappingValue 写入一个字符串字段，键已存在就原地替换。
//
// 「原地替换」而不是「先删再追加」：追加会把字段挪到条目末尾，用户按字段顺序读它
// 自己的配置时，新增的那一项会突然跑到最后一行。
func setMappingValue(mapping *yamlv3.Node, key, value string) {
	if _, index := mappingEntry(mapping, key); index >= 0 {
		mapping.Content[index] = &yamlv3.Node{
			Kind:  yamlv3.ScalarNode,
			Tag:   "!!str",
			Value: value,
		}
		return
	}
	mapping.Content = append(
		mapping.Content,
		&yamlv3.Node{Kind: yamlv3.ScalarNode, Tag: "!!str", Value: key},
		&yamlv3.Node{Kind: yamlv3.ScalarNode, Tag: "!!str", Value: value},
	)
}

// removeMappingValue 删掉一个字段，删掉了返回 true。
func removeMappingValue(mapping *yamlv3.Node, key string) bool {
	if _, index := mappingEntry(mapping, key); index >= 0 {
		mapping.Content = append(mapping.Content[:index-1], mapping.Content[index+1:]...)
		return true
	}
	return false
}

// handleReadProfileTargets 列出链式代理能引用的候选：节点（带当前链）与策略组。
func handleReadProfileTargets(params *ReadProfileTargetsParams) (ProfileTargets, error) {
	_, root, err := profileDocument([]byte(params.YAML))
	if err != nil {
		return ProfileTargets{}, err
	}
	result := ProfileTargets{
		Proxies: []ProfileTarget{},
		Groups:  []ProfileTarget{},
		Nodes:   []map[string]any{},
	}
	if proxies, _ := mappingEntry(root, "proxies"); proxies != nil &&
		proxies.Kind == yamlv3.SequenceNode {
		var nodes []map[string]any
		if err := proxies.Decode(&nodes); err != nil {
			return ProfileTargets{}, fmt.Errorf("读取节点列表失败: %w", err)
		}
		for _, node := range nodes {
			name := strings.TrimSpace(scalarToString(node["name"]))
			if name == "" {
				continue
			}
			result.Proxies = append(result.Proxies, ProfileTarget{
				Name:   name,
				Type:   scalarToString(node["type"]),
				Dialer: scalarToString(node["dialer-proxy"]),
			})
			result.Nodes = append(result.Nodes, node)
		}
	}
	if groups, _ := mappingEntry(root, "proxy-groups"); groups != nil &&
		groups.Kind == yamlv3.SequenceNode {
		for _, item := range groups.Content {
			name := scalarValue(item, "name")
			if name == "" {
				continue
			}
			result.Groups = append(result.Groups, ProfileTarget{
				Name: name,
				Type: scalarValue(item, "type"),
			})
		}
	}
	return result, nil
}

// handleSetProxyChain 给一个节点挂上（或解除）前置代理。
//
// 三条校验都做在这里，而不是丢给内核去报错：`dialer-proxy` 指向不存在的名字会让
// **整份配置加载失败**（`proxy [x] dialer-proxy [y] not found`），而这条路写下去的
// 是用户正在用的配置 —— 等下次加载才发现，等于把用户的网络先弄断了再说。
//
// 注意 handleValidateConfig **拦不住**这类错误：它只跑 UnmarshalRawConfig，不解析
// 分组与 dialer 解析，所以别指望保存时那道校验兜底。
func handleSetProxyChain(params *SetProxyChainParams) (SetProxyChainResult, error) {
	target := strings.TrimSpace(params.Target)
	dialer := strings.TrimSpace(params.Dialer)
	if target == "" {
		return SetProxyChainResult{}, errors.New("没有指定要做链式代理的节点")
	}

	doc, root, err := profileDocument([]byte(params.YAML))
	if err != nil {
		return SetProxyChainResult{}, err
	}
	proxies, _ := mappingEntry(root, "proxies")
	if proxies == nil || proxies.Kind != yamlv3.SequenceNode {
		return SetProxyChainResult{}, errors.New("这份配置里没有节点，先把节点加进来再设链式代理")
	}

	// 一次遍历同时拿到「名字 → 节点」与「名字 → 前置」，后面校验与成环检测都要用。
	var targetNode *yamlv3.Node
	dialers := make(map[string]string)
	proxyNames := make(map[string]bool)
	for _, item := range proxies.Content {
		name := scalarValue(item, "name")
		if name == "" {
			continue
		}
		proxyNames[name] = true
		dialers[name] = scalarValue(item, "dialer-proxy")
		if name == target {
			targetNode = item
		}
	}
	if targetNode == nil {
		// 覆写里的组名也会走到这里：链只能挂在节点上，挂到组上内核只记一条日志
		// 就忽略（`adapter/outboundgroup/parser.go:68`），表现为「设了没反应」。
		return SetProxyChainResult{}, fmt.Errorf(
			"配置里找不到名为 %q 的节点；链式代理只能挂在节点上，不能挂在策略组上",
			target,
		)
	}
	if targetNode.Kind != yamlv3.MappingNode {
		return SetProxyChainResult{}, fmt.Errorf("节点 %q 的内容不是「键: 值」结构", target)
	}

	if dialer == "" {
		removeMappingValue(targetNode, "dialer-proxy")
		out, err := marshalDocument(doc)
		if err != nil {
			return SetProxyChainResult{}, err
		}
		return SetProxyChainResult{YAML: out}, nil
	}

	groups, _ := mappingEntry(root, "proxy-groups")
	groupNames := make(map[string]bool)
	if groups != nil && groups.Kind == yamlv3.SequenceNode {
		for _, item := range groups.Content {
			if name := scalarValue(item, "name"); name != "" {
				groupNames[name] = true
			}
		}
	}
	if !proxyNames[dialer] && !groupNames[dialer] {
		return SetProxyChainResult{}, fmt.Errorf(
			"配置里找不到名为 %q 的前置；它必须是一个节点名或策略组名",
			dialer,
		)
	}

	// 成环：从 dialer 沿既有的链往前走。走到 target 就说明接上会绕圈；而如果中途
	// 撞见一个**已经访问过**的节点，说明这条链本来就绕在环里 —— 那也得拦，否则
	// 接上去之后内核解析时是无限递归。
	if reason := chainLoopReason(dialers, target, dialer); reason != "" {
		return SetProxyChainResult{}, errors.New(reason)
	}

	setMappingValue(targetNode, "dialer-proxy", dialer)
	out, err := marshalDocument(doc)
	if err != nil {
		return SetProxyChainResult{}, err
	}
	return SetProxyChainResult{YAML: out}, nil
}

// handleCopyProxyNode 把来源配置里的一个节点复制进目标配置。
//
// 这是「跨配置挑选」的底层能力：链式代理是名字引用、只在同一份配置内成立，
// 界面让用户从任何配置挑出口/前置，挑中来源配置的节点就先调这里把它搬进
// 目标配置，链再挂在搬过来的那份参数上。
//
// 三条规则：
//   - **剥掉 dialer-proxy**：复制体在目标配置里是孤立节点，它原来挂的前置
//     （可能是来源配置里的某个组名）在目标配置里未必存在 —— 带过来就是悬空
//     引用，整份配置加载失败。想给复制体设链，在目标配置里重新设。
//   - **名字冲突自动改名**（追加 -2、-3）：与 addProxyNodes 的「跳过」不同，
//     这里跳过会让链挂不上（用户明明选了这个节点），自动改名则链引用回传的
//     最终名即可，节点参数一字不差。
//   - **身份相同直接复用**：目标配置里已有 协议|地址|端口|凭据 完全一致的
//     节点时不追加 —— 同一个节点复制两次不该产出两条记录，复用已有的名字。
func handleCopyProxyNode(params *CopyProxyNodeParams) (CopyProxyNodeResult, error) {
	name := strings.TrimSpace(params.Name)
	if name == "" {
		return CopyProxyNodeResult{}, errors.New("没有指定要复制的节点")
	}

	// 来源：找到节点并把参数原样解出来。文档树本身不再使用（只读解码），
	// 用 `_` 接住 —— 来源配置一个字节都不会被改。
	_, srcRoot, err := profileDocument([]byte(params.From))
	if err != nil {
		return CopyProxyNodeResult{}, fmt.Errorf("来源配置解析失败: %w", err)
	}
	var node map[string]any
	if proxies, _ := mappingEntry(srcRoot, "proxies"); proxies != nil &&
		proxies.Kind == yamlv3.SequenceNode {
		for _, item := range proxies.Content {
			if scalarValue(item, "name") == name && item.Kind == yamlv3.MappingNode {
				if err := item.Decode(&node); err != nil {
					return CopyProxyNodeResult{}, fmt.Errorf(
						"读取节点 %q 失败: %w", name, err,
					)
				}
				break
			}
		}
	}
	if node == nil {
		return CopyProxyNodeResult{}, fmt.Errorf(
			"来源配置里找不到名为 %q 的节点；请刷新面板后重试",
			name,
		)
	}
	// 复制体不许带链：dialer-proxy 指向的名字只在来源配置里有意义。
	delete(node, "dialer-proxy")

	// 目标：追加（或复用）。
	dstDoc, dstRoot, err := profileDocument([]byte(params.To))
	if err != nil {
		return CopyProxyNodeResult{}, fmt.Errorf("目标配置解析失败: %w", err)
	}
	used := existingNames(dstRoot)

	// 身份复用先于改名：目标配置里已有同一台服务器就直接用它。
	identities := make(map[string]string) // identity → 已有节点名
	if proxies, _ := mappingEntry(dstRoot, "proxies"); proxies != nil &&
		proxies.Kind == yamlv3.SequenceNode {
		var existing []map[string]any
		if err := proxies.Decode(&existing); err != nil {
			return CopyProxyNodeResult{}, fmt.Errorf("读取节点列表失败: %w", err)
		}
		for _, other := range existing {
			if identity := proxyIdentity(other); identity != "||||" {
				if otherName, _ := other["name"].(string); otherName != "" {
					identities[identity] = strings.TrimSpace(otherName)
				}
			}
		}
	}
	if identity := proxyIdentity(node); identity != "||||" {
		if existingName, ok := identities[identity]; ok {
			return CopyProxyNodeResult{
				YAML:   params.To,
				Name:   existingName,
				Reused: true,
			}, nil
		}
	}

	finalName := name
	if used[finalName] {
		for suffix := 2; ; suffix++ {
			candidate := fmt.Sprintf("%s-%d", name, suffix)
			if !used[candidate] {
				finalName = candidate
				break
			}
		}
	}
	node["name"] = finalName

	children, err := valueNodes([]map[string]any{node})
	if err != nil {
		return CopyProxyNodeResult{}, err
	}
	if err := appendToSequence(dstRoot, "proxies", children); err != nil {
		return CopyProxyNodeResult{}, err
	}
	// 与 addProxyNodes 同一套收尾：没分组的配置补默认分组，有分组的把新节点
	// 接回锚点组 —— 否则复制过来的节点在代理页看不见、分流也够不着。
	if _, _, err := ensureUsableDefaults(dstRoot); err != nil {
		return CopyProxyNodeResult{}, err
	}
	if _, err := healUngroupedProxies(dstRoot); err != nil {
		return CopyProxyNodeResult{}, err
	}
	out, err := marshalDocument(dstDoc)
	if err != nil {
		return CopyProxyNodeResult{}, err
	}
	return CopyProxyNodeResult{YAML: out, Name: finalName}, nil
}

// handleAddProxyChain 新建一条**独立的链式代理节点**。
//
// 与 handleSetProxyChain 的区别是模型：setProxyChain 把 dialer-proxy 写到出口
// 节点身上，链「住」在出口里，代理页上看不出哪条是链；这里生成一个新 proxy
// 条目 —— 参数复制自出口、dialer-proxy 指向前置、名字独立（默认「链式代理N」
// 递增），并把它收进 Group 指定的策略组（不存在就创建 select 组）。所有链
// 集中在一个组里，代理页就是一个独立页签，建了几条、各自走什么路一目了然。
//
// 校验与 setProxyChain 同一套标准（dialer 悬空引用会让整份配置加载失败，而
// handleValidateConfig 拦不住这类错误，必须在这里挡）：
//   - 出口必须是 proxies 里真实存在的节点（组不行，组没法被复制成新条目）；
//   - 前置必须是节点名或策略组名；
//   - 前置沿既有链走不能成环。
//
// 收尾顺序有意安排：先 ensureUsableDefaults（空配置先有基本分组，出口节点
// 也能被默认组引用），再追加链节点，最后保证链分组存在 —— 链节点天生就在
// 链分组里被引用，不需要 healUngroupedProxies 再接一遍。
func handleAddProxyChain(params *AddProxyChainParams) (AddProxyChainResult, error) {
	exit := strings.TrimSpace(params.Exit)
	dialer := strings.TrimSpace(params.Dialer)
	base := strings.TrimSpace(params.Name)
	group := strings.TrimSpace(params.Group)
	switch {
	case exit == "":
		return AddProxyChainResult{}, errors.New("没有指定链式代理的出口节点")
	case dialer == "":
		return AddProxyChainResult{}, errors.New("没有指定链式代理的前置")
	case base == "":
		return AddProxyChainResult{}, errors.New("没有指定链式代理的名称")
	case group == "":
		return AddProxyChainResult{}, errors.New("没有指定链式代理的分组名")
	}

	doc, root, err := profileDocument([]byte(params.YAML))
	if err != nil {
		return AddProxyChainResult{}, err
	}
	// 空配置先补基本分组：默认组引用全部节点（含出口），MATCH 兜底规则也让
	// 流量有去处。已有分组的配置这一步是 no-op。
	if _, _, err := ensureUsableDefaults(root); err != nil {
		return AddProxyChainResult{}, err
	}

	// 找出口节点并复制参数。
	var node map[string]any
	if proxies, _ := mappingEntry(root, "proxies"); proxies != nil &&
		proxies.Kind == yamlv3.SequenceNode {
		for _, item := range proxies.Content {
			if scalarValue(item, "name") == exit && item.Kind == yamlv3.MappingNode {
				if err := item.Decode(&node); err != nil {
					return AddProxyChainResult{}, fmt.Errorf(
						"读取节点 %q 失败: %w", exit, err,
					)
				}
				break
			}
		}
	}
	if node == nil {
		return AddProxyChainResult{}, fmt.Errorf(
			"配置里找不到名为 %q 的出口节点；链式代理的出口必须是节点，请刷新面板后重试",
			exit,
		)
	}
	// 复制体不许继承出口已有的链：那个 dialer-proxy 是出口自己的设置，新链
	// 的前置由本次调用指定（覆盖写在下面），残留旧值只会造成误解。
	delete(node, "dialer-proxy")

	// 前置存在性：节点名或策略组名。名字与成环检测都在追加**之前**做，失败
	// 时配置一个字节都没动。
	used := existingNames(root)
	if !used[dialer] {
		return AddProxyChainResult{}, fmt.Errorf(
			"配置里找不到名为 %q 的前置；它必须是一个节点名或策略组名",
			dialer,
		)
	}

	// 名字解析。AutoNumber（默认名路径）：不管基础名本身空不空，一律从
	// 名称1 开始编号，取已占用最大编号 +1 —— 用户删了中间某条后新链接着
	// 往后排，不回头填空，编号与创建顺序始终一致。自定义名路径：先用原名，
	// 被占用才追加 -2、-3（与 copyProxyNode 同一规则）。
	finalName := base
	if params.AutoNumber {
		maxN := 0
		for usedName := range used {
			if !strings.HasPrefix(usedName, base) {
				continue
			}
			if n, err := strconv.Atoi(usedName[len(base):]); err == nil && n > maxN {
				maxN = n
			}
		}
		finalName = fmt.Sprintf("%s%d", base, maxN+1)
		for used[finalName] {
			maxN++
			finalName = fmt.Sprintf("%s%d", base, maxN+1)
		}
	} else if used[finalName] {
		for suffix := 2; ; suffix++ {
			candidate := fmt.Sprintf("%s-%d", base, suffix)
			if !used[candidate] {
				finalName = candidate
				break
			}
		}
	}
	node["name"] = finalName
	node["dialer-proxy"] = dialer

	// 成环检测：从 dialer 沿既有 dialer-proxy 往前走。新节点还没人引用，走不回
	// 它自己，但前置自身的链可能本来就在环里 —— 那必须拦（内核解析会无限递归）。
	dialers := make(map[string]string)
	if proxies, _ := mappingEntry(root, "proxies"); proxies != nil &&
		proxies.Kind == yamlv3.SequenceNode {
		for _, item := range proxies.Content {
			if name := scalarValue(item, "name"); name != "" {
				dialers[name] = scalarValue(item, "dialer-proxy")
			}
		}
	}
	if reason := chainLoopReason(dialers, finalName, dialer); reason != "" {
		return AddProxyChainResult{}, errors.New(reason)
	}

	children, err := valueNodes([]map[string]any{node})
	if err != nil {
		return AddProxyChainResult{}, err
	}
	if err := appendToSequence(root, "proxies", children); err != nil {
		return AddProxyChainResult{}, err
	}

	// 链分组：已存在就追加成员（幂等），不存在就新建 select 组。分组名若被
	// 某个**节点**占用则报错 —— 组与节点共用命名空间，硬建会让整份配置加载失败。
	groups, _ := mappingEntry(root, "proxy-groups")
	var chainGroup *yamlv3.Node
	if groups != nil && groups.Kind == yamlv3.SequenceNode {
		for _, item := range groups.Content {
			if scalarValue(item, "name") == group && item.Kind == yamlv3.MappingNode {
				chainGroup = item
				break
			}
		}
	}
	if chainGroup == nil && used[group] {
		return AddProxyChainResult{}, fmt.Errorf(
			"配置里已有名为 %q 的节点，无法用它作为链式代理的分组名；请换一个名字",
			group,
		)
	}
	if chainGroup == nil {
		created, err := valueNodes([]map[string]any{{
			"name":    group,
			"type":    "select",
			"proxies": []any{finalName},
		}})
		if err != nil {
			return AddProxyChainResult{}, err
		}
		if err := appendToSequence(root, "proxy-groups", created); err != nil {
			return AddProxyChainResult{}, err
		}
	} else {
		members, _ := mappingEntry(chainGroup, "proxies")
		if members == nil {
			members = &yamlv3.Node{Kind: yamlv3.SequenceNode, Tag: "!!seq"}
			chainGroup.Content = append(
				chainGroup.Content,
				&yamlv3.Node{Kind: yamlv3.ScalarNode, Tag: "!!str", Value: "proxies"},
				members,
			)
		}
		if members.Kind != yamlv3.SequenceNode {
			return AddProxyChainResult{}, fmt.Errorf(
				"分组 %q 的 proxies 不是一个列表，无法追加链式代理",
				group,
			)
		}
		present := false
		for _, m := range members.Content {
			if m.Kind == yamlv3.ScalarNode && m.Value == finalName {
				present = true
				break
			}
		}
		if !present {
			members.Content = append(members.Content, &yamlv3.Node{
				Kind:  yamlv3.ScalarNode,
				Tag:   "!!str",
				Value: finalName,
			})
		}
	}

	out, err := marshalDocument(doc)
	if err != nil {
		return AddProxyChainResult{}, err
	}
	return AddProxyChainResult{YAML: out, Name: finalName, Group: group}, nil
}

// chainLoopReason 判断把 target 的前置接到 dialer 上之后会不会成环；不会则返回空串。
//
// 两种情况都要拦：
//   - 从 dialer 往前走能走回 target —— 新接的这条边构成了环，也包括「自己指向自己」
//     （那时第一步 current 就等于 target）；
//   - 走的途中撞见已经访问过的节点 —— 说明**配置里原本就有的**这条链自己绕圈了。
//     用户手写的配置可能本来就坏，这时不能顺着它无限走下去。
func chainLoopReason(dialers map[string]string, target, dialer string) string {
	seen := make(map[string]bool)
	for current := dialer; current != ""; current = dialers[current] {
		if current == target {
			return fmt.Sprintf(
				"%q 与 %q 之间已经有一条链了，再接一次会绕成一个环",
				dialer,
				target,
			)
		}
		if seen[current] {
			return fmt.Sprintf(
				"前置 %q 的链本身就绕在环里（%q 重复出现），先把它理顺再改",
				dialer,
				current,
			)
		}
		seen[current] = true
	}
	return ""
}
