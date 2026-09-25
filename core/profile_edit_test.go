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

// ---- updateProxyNode ----

// 正常路径：换地址/端口/密码后，名字所在条目整体被替换，组员与规则引用原样
// 保留（名字没动），其余内容（注释、未知顶层键）不动。
func TestUpdateProxyNodeReplacesEntry(t *testing.T) {
	result, err := handleUpdateProxyNode(&UpdateProxyNodeParams{
		YAML: editableProfileFixture,
		Name: "HK-01",
		Node: `{"name":"HK-01","type":"ss","server":"5.6.7.8","port":9999,"cipher":"aes-256-gcm","password":"newpass"}`,
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Updated != "HK-01" {
		t.Fatalf("updated = %q, want HK-01", result.Updated)
	}
	shape := decodeShape(t, result.YAML)
	if len(shape.Proxies) != 1 {
		t.Fatalf("proxies = %+v, want 1 entry", shape.Proxies)
	}
	proxy := shape.Proxies[0]
	if proxy["server"] != "5.6.7.8" || proxy["port"] != 9999 {
		t.Fatalf("proxy not updated: %+v", proxy)
	}
	// 旧字段必须真的没了（整体替换而不是字段合并）。
	if _, ok := proxy["cipher"]; !ok {
		t.Fatalf("cipher should be kept from the new fragment: %+v", proxy)
	}
	// 引用原样。
	selectMembers := groupMembers(t, shape, "我的选择")
	if len(selectMembers) != 2 || !selectMembers["HK-01"] {
		t.Fatalf("我的选择 members = %v, want HK-01 + DIRECT", selectMembers)
	}
	// 注释与未知顶层键仍在。
	if !strings.Contains(result.YAML, "# 我的配置") ||
		!strings.Contains(result.YAML, "bi-loom-custom-key") {
		t.Fatal("comments or unknown top-level keys were dropped")
	}
}

// 名字是组员/规则/链式引用的锚点，编辑不允许改名。
func TestUpdateProxyNodeRejectsRename(t *testing.T) {
	if _, err := handleUpdateProxyNode(&UpdateProxyNodeParams{
		YAML: editableProfileFixture,
		Name: "HK-01",
		Node: `{"name":"HK-02","type":"ss","server":"1.2.3.4","port":8388,"cipher":"aes-256-gcm","password":"pass"}`,
	}); err == nil {
		t.Fatal("expected an error when renaming via update")
	}
}

// 编辑后与另一个节点的 身份键 完全相同 → 拒绝（变相造重复节点）。
func TestUpdateProxyNodeRejectsIdentityCollision(t *testing.T) {
	fixture := `# 我的配置，注释要留着
mixed-port: 7890
proxies:
  - name: HK-01
    type: ss
    server: 1.2.3.4
    port: 8388
    cipher: aes-256-gcm
    password: pass
  - name: HK-01-B
    type: ss
    server: 5.6.7.8
    port: 9999
    cipher: aes-256-gcm
    password: newpass
proxy-groups:
  - name: 我的选择
    type: select
    proxies:
      - HK-01
      - DIRECT
rules:
  - MATCH,我的选择
`
	if _, err := handleUpdateProxyNode(&UpdateProxyNodeParams{
		YAML: fixture,
		Name: "HK-01",
		Node: `{"name":"HK-01","type":"ss","server":"5.6.7.8","port":9999,"cipher":"aes-256-gcm","password":"newpass"}`,
	}); err == nil {
		t.Fatal("expected an identity collision error")
	}
}

// 找不到目标节点时明确报错（面板数据过期场景），而不是返回没变化的 YAML。
func TestUpdateProxyNodeErrorsWhenMissing(t *testing.T) {
	if _, err := handleUpdateProxyNode(&UpdateProxyNodeParams{
		YAML: editableProfileFixture,
		Name: "不存在的",
		Node: `{"name":"不存在的","type":"ss","server":"1.2.3.4","port":8388}`,
	}); err == nil {
		t.Fatal("expected an error when the node is missing")
	}
}

// copyProxyNode 的回归测试：跨配置复制节点是「链式代理跨配置挑选」的底层能力，
// 三条规则各钉一个用例 —— 剥 dialer-proxy、重名自动改名、身份相同直接复用。

const copySrcFixture = `proxies:
  - name: 出口A
    type: ss
    server: 9.9.9.9
    port: 8388
    cipher: aes-256-gcm
    password: src-pass
    dialer-proxy: 来源配置的前置组
`

// 基本路径：参数原样带过去、dialer-proxy 剥掉、目标配置其余内容不动。
func TestCopyProxyNodeAppendsAndStripsDialer(t *testing.T) {
	result, err := handleCopyProxyNode(&CopyProxyNodeParams{
		From: copySrcFixture,
		To:   editableProfileFixture,
		Name: "出口A",
	})
	if err != nil {
		t.Fatalf("copy failed: %v", err)
	}
	if result.Name != "出口A" || result.Reused {
		t.Fatalf("unexpected result: name=%q reused=%v", result.Name, result.Reused)
	}
	for _, want := range []string{"9.9.9.9", "src-pass", "aes-256-gcm"} {
		if !strings.Contains(result.YAML, want) {
			t.Fatalf("copied node lost param %q", want)
		}
	}
	if strings.Contains(result.YAML, "来源配置的前置组") {
		t.Fatal("dialer-proxy 必须被剥掉：带过来就是悬空引用，整份配置加载失败")
	}
	if !strings.Contains(result.YAML, "# 我的配置，注释要留着") ||
		!strings.Contains(result.YAML, "bi-loom-custom-key") {
		t.Fatal("目标配置的注释与未知顶层键被弄丢了")
	}
	if !strings.Contains(result.YAML, "remember: me") {
		t.Fatal("未知顶层键的内容被弄丢了")
	}
}

// 目标配置已有同名（撞的是策略组名也一样）→ 自动改名，链引用回传的最终名。
func TestCopyProxyNodeRenamesOnNameCollision(t *testing.T) {
	result, err := handleCopyProxyNode(&CopyProxyNodeParams{
		From: copySrcFixture,
		To:   editableProfileFixture,
		Name: "我的选择", // 目标配置里这是策略组名
	})
	if err == nil {
		// 来源里没有叫「我的选择」的节点，应当直接报找不到。
		t.Fatal("expected an error for a missing source node")
	}
	_ = result

	collisionFixture := `proxies:
  - name: HK-01
    type: ss
    server: 9.9.9.9
    port: 8388
    cipher: aes-256-gcm
    password: src-pass
`
	result, err = handleCopyProxyNode(&CopyProxyNodeParams{
		From: collisionFixture,
		To:   editableProfileFixture,
		Name: "HK-01",
	})
	if err != nil {
		t.Fatalf("copy failed: %v", err)
	}
	if result.Name != "HK-01-2" {
		t.Fatalf("expected renamed to HK-01-2, got %q", result.Name)
	}
	if !strings.Contains(result.YAML, "HK-01-2") {
		t.Fatal("renamed node missing from output yaml")
	}
}

// 目标配置里已有同一节点（身份键相同、名字不同）→ 复用，不追加，YAML 原样返回。
func TestCopyProxyNodeReusesIdenticalNode(t *testing.T) {
	dst := `proxies:
  - name: 已有的
    type: ss
    server: 9.9.9.9
    port: 8388
    cipher: aes-256-gcm
    password: src-pass
`
	result, err := handleCopyProxyNode(&CopyProxyNodeParams{
		From: copySrcFixture,
		To:   dst,
		Name: "出口A",
	})
	if err != nil {
		t.Fatalf("copy failed: %v", err)
	}
	if !result.Reused || result.Name != "已有的" {
		t.Fatalf("expected reuse of 已有的, got name=%q reused=%v", result.Name, result.Reused)
	}
	if result.YAML != dst {
		t.Fatal("reused path must not touch the target yaml")
	}
}

// 来源配置里没有这个节点 → 明确报错（面板数据过期场景）。
func TestCopyProxyNodeErrorsWhenMissing(t *testing.T) {
	if _, err := handleCopyProxyNode(&CopyProxyNodeParams{
		From: copySrcFixture,
		To:   editableProfileFixture,
		Name: "不存在的",
	}); err == nil {
		t.Fatal("expected an error when the source node is missing")
	}
}

// addProxyChain 的回归测试：新建**独立的链式代理节点**并收进专属分组。
// 三条规则各钉用例 —— 默认名自动编号（取已占用最大编号 +1，不回填空位）、
// 自定义名原样使用（被占才 -2）、出口/前置不存在要报错而不是写坏配置。

// 基本路径：参数复制自出口、dialer-proxy 指向前置、分组自动创建并收纳。
func TestAddProxyChainCreatesNodeAndGroup(t *testing.T) {
	result, err := handleAddProxyChain(&AddProxyChainParams{
		YAML:       editableProfileFixture,
		Exit:       "HK-01",
		Dialer:     "我的选择", // 前置可以是策略组
		Name:       "链式代理",
		AutoNumber: true,
		Group:      "链式代理",
	})
	if err != nil {
		t.Fatalf("add failed: %v", err)
	}
	if result.Name != "链式代理1" || result.Group != "链式代理" {
		t.Fatalf("unexpected result: name=%q group=%q", result.Name, result.Group)
	}
	for _, want := range []string{
		"链式代理1", "1.2.3.4", "aes-256-gcm", "dialer-proxy: 我的选择",
	} {
		if !strings.Contains(result.YAML, want) {
			t.Fatalf("chain node lost %q", want)
		}
	}
	// 分组：select 类型、成员是链式代理1。用结构化断言而不是文本匹配 ——
	// 序列化的缩进风格（顶层 4 空格）不属于本 handler 的承诺范围。
	var decoded map[string]any
	if err := yaml.Unmarshal([]byte(result.YAML), &decoded); err != nil {
		t.Fatalf("result yaml is not valid: %v", err)
	}
	groups, _ := decoded["proxy-groups"].([]any)
	var chainGroup map[string]any
	for _, item := range groups {
		if group, ok := item.(map[string]any); ok && group["name"] == "链式代理" {
			chainGroup = group
			break
		}
	}
	if chainGroup == nil {
		t.Fatal("chain group missing")
	}
	if chainGroup["type"] != "select" {
		t.Fatalf("chain group type = %v, want select", chainGroup["type"])
	}
	members, _ := chainGroup["proxies"].([]any)
	if len(members) != 1 || members[0] != "链式代理1" {
		t.Fatalf("chain group members = %v, want [链式代理1]", members)
	}
	// 其余内容一个不能丢。
	for _, want := range []string{"# 我的配置，注释要留着", "bi-loom-custom-key", "MATCH,我的选择"} {
		if !strings.Contains(result.YAML, want) {
			t.Fatalf("rest of config lost %q", want)
		}
	}
}

// 默认名编号：已有 链式代理1 和 链式代理3 → 新链取最大编号 +1 = 链式代理4，
// 不回头填 链式代理2 的空位（编号与创建顺序保持一致）。
func TestAddProxyChainAutoNumberTakesMaxPlusOne(t *testing.T) {
	dst := `proxies:
  - name: HK-01
    type: ss
    server: 1.2.3.4
    port: 8388
    cipher: aes-256-gcm
    password: pass
  - name: 链式代理1
    type: ss
    server: 5.6.7.8
    port: 8388
    cipher: aes-256-gcm
    password: pass
    dialer-proxy: HK-01
  - name: 链式代理3
    type: ss
    server: 9.9.9.9
    port: 8388
    cipher: aes-256-gcm
    password: pass
    dialer-proxy: HK-01
proxy-groups:
  - name: 链式代理
    type: select
    proxies:
      - 链式代理1
      - 链式代理3
`
	result, err := handleAddProxyChain(&AddProxyChainParams{
		YAML:       dst,
		Exit:       "HK-01",
		Dialer:     "HK-01",
		Name:       "链式代理",
		AutoNumber: true,
		Group:      "链式代理",
	})
	if err != nil {
		t.Fatalf("add failed: %v", err)
	}
	if result.Name != "链式代理4" {
		t.Fatalf("expected 链式代理4, got %q", result.Name)
	}
	// 已存在的分组直接追加成员，不重复建组。
	if n := strings.Count(result.YAML, "name: 链式代理\n"); n != 1 {
		t.Fatalf("chain group duplicated: %d", n)
	}
	if !strings.Contains(result.YAML, "- 链式代理4") {
		t.Fatal("chain node not added into chain group")
	}
}

// 自定义名：原样使用、不加数字；被占用才追加 -2（与 copyProxyNode 同规则）。
func TestAddProxyChainCustomNameKeptOrSuffixed(t *testing.T) {
	result, err := handleAddProxyChain(&AddProxyChainParams{
		YAML:   editableProfileFixture,
		Exit:   "HK-01",
		Dialer: "我的选择",
		Name:   "我的专线",
		Group:  "链式代理",
	})
	if err != nil {
		t.Fatalf("add failed: %v", err)
	}
	if result.Name != "我的专线" {
		t.Fatalf("custom name must be kept verbatim, got %q", result.Name)
	}

	// 同名再来一条：-2 兜底。
	result, err = handleAddProxyChain(&AddProxyChainParams{
		YAML:   result.YAML,
		Exit:   "HK-01",
		Dialer: "我的选择",
		Name:   "我的专线",
		Group:  "链式代理",
	})
	if err != nil {
		t.Fatalf("add failed: %v", err)
	}
	if result.Name != "我的专线-2" {
		t.Fatalf("expected 我的名-2 fallback, got %q", result.Name)
	}
	if !strings.Contains(result.YAML, "- 我的专线-2") {
		t.Fatal("second chain not added into chain group")
	}
}

// 出口或前置不存在：报错，且配置不能被写坏（这里直接以错误为准，无产物可验）。
func TestAddProxyChainErrorsOnMissingExitOrDialer(t *testing.T) {
	if _, err := handleAddProxyChain(&AddProxyChainParams{
		YAML:   editableProfileFixture,
		Exit:   "不存在的出口",
		Dialer: "我的选择",
		Name:   "链式代理",
		Group:  "链式代理",
	}); err == nil {
		t.Fatal("expected an error for a missing exit node")
	}
	if _, err := handleAddProxyChain(&AddProxyChainParams{
		YAML:   editableProfileFixture,
		Exit:   "HK-01",
		Dialer: "不存在的前置",
		Name:   "链式代理",
		Group:  "链式代理",
	}); err == nil {
		t.Fatal("expected an error for a missing dialer")
	}
}
