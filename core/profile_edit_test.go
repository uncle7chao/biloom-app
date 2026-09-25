package main

import (
	"strings"
	"testing"

	"github.com/metacubex/mihomo/common/yaml"
)

// 配置编辑层的回归测试。
//
// 这一层最要紧的约束是「用户配置的其余部分必须原样保留」，所以几乎每个用例都会
// 顺带检查注释与未知顶层键还在 —— 那正是「用 config.RawConfig 解析再序列化」
// 那条捷径会**静默**毁掉的东西（RawConfig 没有 inline 兜底字段）。

// editableProfileFixture 模拟一份用户手写的配置：带注释、带这版内核不认识的顶层键，
// 也带一份自建分组（用来验证已有分组不会被动）。
const editableProfileFixture = `# 我的配置，注释要留着
mixed-port: 7890
proxies:
  - name: HK-01
    type: ss
    server: 1.2.3.4
    port: 8388
    cipher: aes-256-gcm
    password: pass
proxy-groups:
  - name: 我的选择
    type: select
    proxies:
      - HK-01
      - DIRECT
rules:
  - MATCH,我的选择

# 这个键内核还不认识，但绝不能丢
bi-loom-custom-key:
  remember: me
`

func decodeShape(t *testing.T, text string) profileShape {
	t.Helper()
	var shape profileShape
	if err := yaml.Unmarshal([]byte(text), &shape); err != nil {
		t.Fatalf("output is not parseable YAML: %v\n%s", err, text)
	}
	return shape
}

func TestAddProxyNodesKeepsUnrelatedContent(t *testing.T) {
	result, err := handleAddProxyNodes(&AddProxyNodesParams{
		YAML:  editableProfileFixture,
		Nodes: vlessShareLinkFixture,
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Added) != 1 || len(result.Skipped) != 0 {
		t.Fatalf("added = %v, skipped = %v, want 1 added and 0 skipped",
			result.Added, result.Skipped)
	}
	if !strings.Contains(result.YAML, "# 我的配置，注释要留着") {
		t.Fatalf("leading comment was dropped:\n%s", result.YAML)
	}
	if !strings.Contains(result.YAML, "remember: me") {
		t.Fatalf("unknown top-level key was dropped:\n%s", result.YAML)
	}
	if !strings.Contains(result.YAML, "mixed-port: 7890") {
		t.Fatalf("unrelated scalar key was dropped:\n%s", result.YAML)
	}
	shape := decodeShape(t, result.YAML)
	if len(shape.Proxies) != 2 {
		t.Fatalf("proxies = %d, want 2", len(shape.Proxies))
	}
	if len(shape.ProxyGroups) != 1 || shape.ProxyGroups[0]["name"] != "我的选择" {
		t.Fatalf("existing groups must be untouched, got %+v", shape.ProxyGroups)
	}
	if len(shape.Rules) != 1 {
		t.Fatalf("existing rules must be untouched, got %+v", shape.Rules)
	}
}

// 重名节点在 Clash 里会让整份配置加载失败，所以只能留一个。这里选择「跳过并
// 如实回报」而不是自动改名 —— 自动改名会让节点列表里冒出用户没写过的名字。
func TestAddProxyNodesSkipsDuplicateNames(t *testing.T) {
	result, err := handleAddProxyNodes(&AddProxyNodesParams{
		YAML: editableProfileFixture,
		Nodes: "- name: HK-01\n  type: ss\n  server: 5.6.7.8\n" +
			"  port: 8388\n  cipher: aes-256-gcm\n  password: other\n",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Added) != 0 || len(result.Skipped) != 1 || result.Skipped[0] != "HK-01" {
		t.Fatalf("added = %v, skipped = %v, want HK-01 skipped", result.Added, result.Skipped)
	}
	if shape := decodeShape(t, result.YAML); len(shape.Proxies) != 1 {
		t.Fatalf("proxies = %d, want the original single node", len(shape.Proxies))
	}
}

// 同一批里自己重名：只在 YAML 片段路径上会命中 —— 分享链接路径轮不到我们管，
// 内核的转换器自己就会把重名的第二条改名（见下一个用例）。
func TestAddProxyNodesSkipsDuplicatesWithinBatch(t *testing.T) {
	result, err := handleAddProxyNodes(&AddProxyNodesParams{
		YAML: bareProxiesFixture,
		Nodes: "- name: JP-01\n  type: trojan\n  server: 1.1.1.1\n  port: 443\n  password: a\n" +
			"- name: JP-01\n  type: trojan\n  server: 2.2.2.2\n  port: 443\n  password: b\n",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Added) != 1 || len(result.Skipped) != 1 || result.Skipped[0] != "JP-01" {
		t.Fatalf("added = %v, skipped = %v, want one added and one skipped",
			result.Added, result.Skipped)
	}
}

// 钉住一个上游行为：内核的分享链接转换器（convert.ConvertsV2Ray）遇到重名会自己
// 加 `-01` 后缀。所以「从剪贴板粘两遍同一条链接」不会把配置搞坏，但节点列表里会
// 多出一个带后缀的节点。这行代码不是我们写的，用户却会看见，所以在这里记下来，
// 免得日后把它当成我们的 bug 去查。
func TestShareLinkConverterRenamesDuplicates(t *testing.T) {
	nodes, err := parseProxyNodes(vlessShareLinkFixture + "\n" + vlessShareLinkFixture + "\n")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(nodes) != 2 {
		t.Fatalf("nodes = %d, want 2", len(nodes))
	}
	first, _ := nodes[0]["name"].(string)
	second, _ := nodes[1]["name"].(string)
	if first == second {
		t.Fatalf("upstream converter should disambiguate, both are %q", first)
	}
	if !strings.HasSuffix(second, "-01") {
		t.Fatalf("second name = %q, want a -01 suffix", second)
	}
}

func TestAddProxyNodesAcceptsProxiesFragment(t *testing.T) {
	result, err := handleAddProxyNodes(&AddProxyNodesParams{
		YAML: editableProfileFixture,
		Nodes: "proxies:\n  - name: JP-01\n    type: trojan\n" +
			"    server: 5.6.7.8\n    port: 443\n    password: pw\n",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Added) != 1 || result.Added[0] != "JP-01" {
		t.Fatalf("added = %v, want JP-01", result.Added)
	}
	if shape := decodeShape(t, result.YAML); len(shape.Proxies) != 2 {
		t.Fatalf("proxies = %d, want 2", len(shape.Proxies))
	}
}

func TestAddProxyNodesRejectsUnusableInput(t *testing.T) {
	for name, nodes := range map[string]string{
		"空白":     "   \n",
		"既非链接也非 YAML": "这不是节点",
		"条目缺少 name": "- type: ss\n  server: 1.2.3.4\n",
	} {
		if _, err := handleAddProxyNodes(&AddProxyNodesParams{
			YAML:  bareProxiesFixture,
			Nodes: nodes,
		}); err == nil {
			t.Fatalf("%s：期望报错，却通过了", name)
		}
	}
}

// 空白配置里加第一个节点：必须连分组与兜底规则一起补上，否则用户拿到的是一个
// 「已连接但网页打不开」的配置。
func TestAddProxyNodesToBlankProfileBackfillsDefaults(t *testing.T) {
	result, err := handleAddProxyNodes(&AddProxyNodesParams{
		YAML:  "",
		Nodes: vlessShareLinkFixture,
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	shape := decodeShape(t, result.YAML)
	if len(shape.Proxies) != 1 {
		t.Fatalf("proxies = %d, want 1", len(shape.Proxies))
	}
	if len(shape.ProxyGroups) == 0 {
		t.Fatal("default groups were not injected")
	}
	if len(shape.Rules) == 0 {
		t.Fatal("fallback rules were not injected")
	}
}

// 已有 rules 但缺 MATCH 兜底：只追加 MATCH，用户写下的规则一条都不能动。
func TestAddProxyNodesAppendsOnlyMatchWhenRulesExist(t *testing.T) {
	const fixture = `proxies:
  - name: HK-01
    type: ss
    server: 1.2.3.4
    port: 8388
    cipher: aes-256-gcm
    password: pass
rules:
  - GEOIP,LAN,DIRECT
`
	result, err := handleAddProxyNodes(&AddProxyNodesParams{
		YAML:  fixture,
		Nodes: vlessShareLinkFixture,
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	shape := decodeShape(t, result.YAML)
	if len(shape.Rules) != 2 {
		t.Fatalf("rules = %+v, want the original one plus a MATCH fallback", shape.Rules)
	}
	if shape.Rules[0] != "GEOIP,LAN,DIRECT" {
		t.Fatalf("the original rule was moved or rewritten: %+v", shape.Rules)
	}
	if !strings.HasPrefix(shape.Rules[1], "MATCH,") {
		t.Fatalf("last rule = %q, want a MATCH fallback", shape.Rules[1])
	}
}

// healGroupsFixture 模拟「先加过一个节点、默认分组已注入」的中间态：分组里只有
// HK-01，之后追加的节点不会进任何组 —— 这正是「新增节点不显示」的根因。US-01
// 则模拟历史上已经游离的节点（同样不在任何组里）。
const healGroupsFixture = `mixed-port: 7890
proxies:
  - name: HK-01
    type: ss
    server: 1.2.3.4
    port: 8388
    cipher: aes-256-gcm
    password: pass
  - name: US-01
    type: ss
    server: 5.6.7.8
    port: 8388
    cipher: aes-256-gcm
    password: pass
proxy-groups:
  - name: 节点选择
    type: select
    proxies:
      - 自动选择
      - 故障转移
      - HK-01
      - DIRECT
  - name: 自动选择
    type: url-test
    proxies:
      - HK-01
    tolerance: 50
  - name: 故障转移
    type: fallback
    proxies:
      - HK-01
    hidden: true
rules:
  - MATCH,节点选择
`

func groupMembers(t *testing.T, shape profileShape, group string) map[string]bool {
	t.Helper()
	for _, g := range shape.ProxyGroups {
		if g["name"] != group {
			continue
		}
		raw, ok := g["proxies"].([]any)
		if !ok {
			t.Fatalf("group %s has no proxies list: %+v", group, g)
		}
		members := make(map[string]bool, len(raw))
		for _, m := range raw {
			s, _ := m.(string)
			members[s] = true
		}
		return members
	}
	t.Fatalf("group %s not found in %+v", group, shape.ProxyGroups)
	return nil
}

// 加节点时：新节点与历史游离节点都要被接回三个锚点组；锚点组之外的东西不动。
func TestAddProxyNodesHealsUngroupedProxies(t *testing.T) {
	result, err := handleAddProxyNodes(&AddProxyNodesParams{
		YAML:  healGroupsFixture,
		Nodes: vlessShareLinkFixture,
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Added) != 1 || result.Added[0] != "HK-443-WS-TLS" {
		t.Fatalf("added = %v, want [HK-443-WS-TLS]", result.Added)
	}
	shape := decodeShape(t, result.YAML)
	if len(shape.Proxies) != 3 {
		t.Fatalf("proxies = %d, want 3", len(shape.Proxies))
	}
	for _, group := range []string{"节点选择", "自动选择", "故障转移"} {
		members := groupMembers(t, shape, group)
		for _, name := range []string{"HK-01", "US-01", "HK-443-WS-TLS"} {
			if !members[name] {
				t.Fatalf("group %s is missing %q after healing: %v", group, name, members)
			}
		}
	}
	// 幂等：同一份结果再走一遍，不能有任何新变化。
	second, err := handleAddProxyNodes(&AddProxyNodesParams{
		YAML:  result.YAML,
		Nodes: trojanShareLinkFixture,
	})
	if err != nil {
		t.Fatalf("unexpected error on second pass: %v", err)
	}
	if len(second.Added) != 1 || second.Added[0] != "JP-Trojan" {
		t.Fatalf("second pass added = %v, want [JP-Trojan]", second.Added)
	}
	shape2 := decodeShape(t, second.YAML)
	members := groupMembers(t, shape2, "节点选择")
	for _, name := range []string{"HK-01", "US-01", "HK-443-WS-TLS", "JP-Trojan"} {
		if !members[name] {
			t.Fatalf("group 节点选择 is missing %q after second pass: %v", name, members)
		}
	}
	if len(shape2.Proxies) != 4 {
		t.Fatalf("proxies = %d, want 4", len(shape2.Proxies))
	}
}

// 没有锚点组（分组全是自建名）时一个字节都不能动 —— 哪怕有游离节点，
// 塞哪个组是用户的决定。
func TestHealSkipsProfilesWithoutAnchorGroups(t *testing.T) {
	const fixture = `mixed-port: 7890
proxies:
  - name: HK-01
    type: ss
    server: 1.2.3.4
    port: 8388
    cipher: aes-256-gcm
    password: pass
  - name: US-01
    type: ss
    server: 5.6.7.8
    port: 8388
    cipher: aes-256-gcm
    password: pass
proxy-groups:
  - name: 我的选择
    type: select
    proxies:
      - HK-01
rules:
  - MATCH,我的选择
`
	out, changed, _, err := patchMissingDefaults([]byte(fixture))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if changed {
		t.Fatalf("profile without anchor groups must be untouched, got:\n%s", out)
	}
	if out != nil {
		t.Fatalf("unchanged input must return nil output, got:\n%s", out)
	}
}

// 「更新」路径（patchMissingDefaults）：已有分组 + 游离节点时要把游离节点接回。
func TestPatchMissingDefaultsHealsUngroupedProxies(t *testing.T) {
	out, changed, _, err := patchMissingDefaults([]byte(healGroupsFixture))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !changed {
		t.Fatal("ungrouped proxies were not healed")
	}
	shape := decodeShape(t, string(out))
	members := groupMembers(t, shape, "节点选择")
	if !members["US-01"] {
		t.Fatalf("US-01 was not healed into 节点选择: %v", members)
	}
	// 原有成员一个都不能丢，顺序也保持「自动选择、故障转移在前」。
	for _, name := range []string{"自动选择", "故障转移", "HK-01", "DIRECT"} {
		if !members[name] {
			t.Fatalf("original member %q was dropped: %v", name, members)
		}
	}
}

// 分享链接不带 #名字（V2rayN 导出的常态）时自动生成 `地址:端口`，而不是报
// 「缺少 name」把用户挡在门外。
func TestParseShareLinkWithoutFragmentGetsGeneratedName(t *testing.T) {
	nodes, err := parseProxyNodes(
		"hysteria2://letmein@example.com:8443/?insecure=1&sni=real.example.com",
	)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(nodes) != 1 {
		t.Fatalf("want 1 node, got %d", len(nodes))
	}
	name, _ := nodes[0]["name"].(string)
	if name != "example.com:8443" {
		t.Fatalf("generated name = %q, want example.com:8443", name)
	}
}

// 同一个节点换个名字再加一遍（分享链接的名字来自 #片段、导出配置的名字是自动
// 生成的，必然不同）要按身份（协议+地址+端口+凭据）识别为重复并跳过。
func TestAddProxyNodesSkipsSameNodeUnderDifferentNames(t *testing.T) {
	result, err := handleAddProxyNodes(&AddProxyNodesParams{
		YAML: healGroupsFixture,
		Nodes: `- name: 改个名字还是它
  type: ss
  server: 1.2.3.4
  port: 8388
  cipher: aes-256-gcm
  password: pass
- name: 别的机器
  type: ss
  server: 9.9.9.9
  port: 8388
  cipher: aes-256-gcm
  password: pass
`,
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Added) != 1 || result.Added[0] != "别的机器" {
		t.Fatalf("added = %v, want only 别的机器", result.Added)
	}
	if len(result.Skipped) != 1 || result.Skipped[0] != "改个名字还是它" {
		t.Fatalf("skipped = %v, want 改个名字还是它", result.Skipped)
	}
}

// removeFixture：HK-01 同时被组员、规则引用；自动选择组只有它一个成员；
// US-01 被 no-resolve 规则引用 —— 覆盖删除时要同步清理的所有引用形态。
const removeFixture = `mixed-port: 7890
proxies:
  - name: HK-01
    type: ss
    server: 1.2.3.4
    port: 8388
    cipher: aes-256-gcm
    password: pass
  - name: US-01
    type: ss
    server: 5.6.7.8
    port: 8388
    cipher: aes-256-gcm
    password: pass
proxy-groups:
  - name: 节点选择
    type: select
    proxies:
      - HK-01
      - US-01
  - name: 自动选择
    type: url-test
    proxies:
      - HK-01
rules:
  - DOMAIN-SUFFIX,example.com,HK-01
  - IP-CIDR,1.1.1.1/32,US-01,no-resolve
  - MATCH,节点选择
`

func TestRemoveProxyNodesCleansUpReferences(t *testing.T) {
	result, err := handleRemoveProxyNodes(&RemoveProxyNodesParams{
		YAML:  removeFixture,
		Names: []string{"HK-01", "US-01", "不存在的"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Removed) != 2 {
		t.Fatalf("removed = %v, want HK-01 + US-01", result.Removed)
	}
	if len(result.Missing) != 1 || result.Missing[0] != "不存在的" {
		t.Fatalf("missing = %v, want 不存在的", result.Missing)
	}
	shape := decodeShape(t, result.YAML)
	if len(shape.Proxies) != 0 {
		t.Fatalf("proxies not emptied: %+v", shape.Proxies)
	}
	// 两个成员都删了，组被删空 → 补 DIRECT 兜底。
	selectMembers := groupMembers(t, shape, "节点选择")
	if len(selectMembers) != 1 || !selectMembers["DIRECT"] {
		t.Fatalf("节点选择 members = %v, want only DIRECT", selectMembers)
	}
	autoMembers := groupMembers(t, shape, "自动选择")
	if len(autoMembers) != 1 || !autoMembers["DIRECT"] {
		t.Fatalf("自动选择 members = %v, want only DIRECT", autoMembers)
	}
	// 指向被删节点的规则删掉；MATCH 兜底原样保留。
	if len(shape.Rules) != 1 || shape.Rules[0] != "MATCH,节点选择" {
		t.Fatalf("rules = %v, want only MATCH,节点选择", shape.Rules)
	}
}

// 一个都没删到时明确报错，而不是返回一份没变化还假装成功的 YAML。
func TestRemoveProxyNodesErrorsWhenNothingRemoved(t *testing.T) {
	if _, err := handleRemoveProxyNodes(&RemoveProxyNodesParams{
		YAML:  removeFixture,
		Names: []string{"不存在的"},
	}); err == nil {
		t.Fatal("expected an error when nothing was removed")
	}
}
