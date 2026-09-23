package main

import (
	"errors"
	"fmt"
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
		return nil, errors.New("YAML 片段里没找到节点：每条节点至少要有 name")
	}
	return nil, errors.New("YAML 片段里没找到节点")
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
	if err != nil || !changed {
		return nil, false, 0, err
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
	used := existingNames(root)
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
	}

	out, err := marshalDocument(doc)
	if err != nil {
		return AddProxyNodesResult{}, err
	}
	return AddProxyNodesResult{YAML: out, Added: added, Skipped: skipped}, nil
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
	}
	if proxies, _ := mappingEntry(root, "proxies"); proxies != nil &&
		proxies.Kind == yamlv3.SequenceNode {
		for _, item := range proxies.Content {
			name := scalarValue(item, "name")
			if name == "" {
				continue
			}
			result.Proxies = append(result.Proxies, ProfileTarget{
				Name:   name,
				Type:   scalarValue(item, "type"),
				Dialer: scalarValue(item, "dialer-proxy"),
			})
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
