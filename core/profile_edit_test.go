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
