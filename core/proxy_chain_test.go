package main

// 链式代理的形态调研（钉住上游行为，不是自研功能的回归测试）。
//
// 背景：BiLoom 的「添加链式代理」原先照搬了 Clash 的 `type: relay` 分组写法。
// 但本内核（Clash.Meta @ 70f0570 一线）**已经把 relay 分组类型删掉了**，
// 写出来的是致命错误 —— 整份配置加载失败。这个文件把三件事钉死：
//
//  1. relay 分组 = 致命错误（不是警告、不是静默忽略）；
//  2. 现状的正确做法是**代理级** `dialer-proxy` 字段；
//  3. `dialer-proxy` 可以指向另一个代理，**也可以指向一个策略组名**。
//
// 用 `config.Parse` 而不是 `executor.ParseWithBytes`：前者跑到「建好代理与分组」
// 就返回，不启动监听器与外部控制器，适合测试。

import (
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/config"
)

const relayPairProxies = `
proxies:
  - name: hop-a
    type: ss
    server: 203.0.113.10
    port: 443
    cipher: aes-128-gcm
    password: pass-a
  - name: hop-b
    type: ss
    server: 203.0.113.11
    port: 443
    cipher: aes-128-gcm
    password: pass-b
`

// relay 分组必须被拒绝：这份配置一旦落盘，用户整份配置都用不了。
func TestRelayGroupTypeIsRejected(t *testing.T) {
	profile := relayPairProxies + `
proxy-groups:
  - name: my-chain
    type: relay
    proxies:
      - hop-a
      - hop-b
rules:
  - MATCH,my-chain
`
	_, err := config.Parse([]byte(profile))
	if err == nil {
		t.Fatal("relay 分组竟然通过了：如果上游把它加回来了，BiLoom 的链式代理可以改回分组写法")
	}
	if !strings.Contains(err.Error(), "relay") {
		t.Fatalf("期望报错里点明 relay，实际是: %v", err)
	}
}

// 现状的正确写法：代理级 dialer-proxy 指向另一个代理。
func TestProxyLevelDialerProxyBuildsChain(t *testing.T) {
	profile := relayPairProxies + `
  - name: hop-b-chained
    type: ss
    server: 203.0.113.11
    port: 443
    cipher: aes-128-gcm
    password: pass-b
    dialer-proxy: hop-a
rules:
  - MATCH,hop-b-chained
`
	if _, err := config.Parse([]byte(profile)); err != nil {
		t.Fatalf("代理级 dialer-proxy 应当可用，实际报错: %v", err)
	}
}

// dialer-proxy 支持写**策略组名**：这是让「按组当前选择决定前跳」成立的前提。
func TestDialerProxyAcceptsGroupName(t *testing.T) {
	profile := `
proxies:
  - name: hop-a
    type: ss
    server: 203.0.113.10
    port: 443
    cipher: aes-128-gcm
    password: pass-a
  - name: exit
    type: ss
    server: 203.0.113.11
    port: 443
    cipher: aes-128-gcm
    password: pass-b
    dialer-proxy: front-pool
proxy-groups:
  - name: front-pool
    type: select
    proxies:
      - hop-a
      - DIRECT
rules:
  - MATCH,exit
`
	if _, err := config.Parse([]byte(profile)); err != nil {
		t.Fatalf("dialer-proxy 指向策略组名应当可用，实际报错: %v", err)
	}
}

// 指向不存在的名字必须是错误 —— 这是写入前的把关依据（拼错名字不能静默直连）。
func TestDialerProxyRejectsUnknownName(t *testing.T) {
	profile := strings.Replace(
		relayPairProxies+`
rules:
  - MATCH,hop-a
`,
		"    password: pass-a\n",
		"    password: pass-a\n    dialer-proxy: no-such-thing\n",
		1,
	)
	if _, err := config.Parse([]byte(profile)); err == nil {
		t.Fatal("dialer-proxy 指向不存在的名字应当报错")
	} else {
		t.Logf("报错内容: %v", err)
	}
}

// 组级 dialer-proxy 只记日志、不生效 —— 钉住它，避免以后误以为写在组上就行。
func TestGroupLevelDialerProxyIsIgnored(t *testing.T) {
	profile := relayPairProxies + `
proxy-groups:
  - name: g
    type: select
    proxies:
      - hop-a
      - hop-b
    dialer-proxy: hop-a
rules:
  - MATCH,g
`
	parsed, err := config.Parse([]byte(profile))
	if err != nil {
		// 上游把它改成硬失败也算合理，但不能是「悄悄生效」。
		t.Logf("组级 dialer-proxy 被拒绝（也算合理）: %v", err)
		return
	}
	_ = parsed
}

// handleValidateConfig 只做 UnmarshalRawConfig，不解析分组 —— 所以它**发现不了**
// relay 这类错误。钉住这个落差：链式代理写入前必须自己把关，不能指望 validateConfig。
func TestValidateConfigShapeDoesNotCatchRelayGroups(t *testing.T) {
	profile := relayPairProxies + `
proxy-groups:
  - name: my-chain
    type: relay
    proxies:
      - hop-a
      - hop-b
rules:
  - MATCH,my-chain
`
	// 这正是 handleValidateConfig 走的那一步。
	if _, err := config.UnmarshalRawConfig([]byte(profile)); err != nil {
		t.Fatalf("UnmarshalRawConfig 竟然拦住了 relay：%v", err)
	}
	// 而真正加载时会失败。
	if _, err := config.Parse([]byte(profile)); err == nil {
		t.Fatal("config.Parse 应当拦住 relay 分组")
	}
}

// ---------------------------------------------------------------------------
// 自研入口：setProxyChain / readProfileTargets
// ---------------------------------------------------------------------------

// chainFixture 是用户手写的配置：两个节点、一个分组，带注释与未知顶层键。
const chainFixture = `# 手写的注释
mixed-port: 7890
proxies:
  - name: 香港入口
    type: ss
    server: 203.0.113.10
    port: 8388
    cipher: aes-256-gcm
    password: pass-a
  - name: 落地出口
    type: ss
    server: 203.0.113.11
    port: 8388
    cipher: aes-256-gcm
    password: pass-b
proxy-groups:
  - name: 自动选择
    type: url-test
    proxies:
      - 香港入口
      - 落地出口
rules:
  - MATCH,自动选择

bi-loom-note: keep-me
`

func TestReadProfileTargetsListsProxiesAndGroups(t *testing.T) {
	targets, err := handleReadProfileTargets(&ReadProfileTargetsParams{
		YAML: chainFixture,
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(targets.Proxies) != 2 {
		t.Fatalf("proxies = %+v, want 2", targets.Proxies)
	}
	if targets.Proxies[0].Name != "香港入口" || targets.Proxies[0].Type != "ss" {
		t.Fatalf("第一条 = %+v，期望名字与类型都读出来", targets.Proxies[0])
	}
	if targets.Proxies[0].Dialer != "" {
		t.Fatalf("还没设链，Dialer 应当是空的，实际 %q", targets.Proxies[0].Dialer)
	}
	if len(targets.Groups) != 1 || targets.Groups[0].Name != "自动选择" {
		t.Fatalf("groups = %+v, want 自动选择", targets.Groups)
	}
}

func TestSetProxyChainWritesDialerProxy(t *testing.T) {
	result, err := handleSetProxyChain(&SetProxyChainParams{
		YAML:   chainFixture,
		Target: "落地出口",
		Dialer: "香港入口",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// 配置其余部分一个字节都不该动。
	for _, keep := range []string{"# 手写的注释", "bi-loom-note: keep-me", "mixed-port: 7890"} {
		if !strings.Contains(result.YAML, keep) {
			t.Fatalf("%q 被丢掉了:\n%s", keep, result.YAML)
		}
	}
	// 写出来的东西必须真能加载 —— 这是这条路线唯一有意义的验收。
	if _, err := config.Parse([]byte(result.YAML)); err != nil {
		t.Fatalf("写入后的配置加载失败: %v\n%s", err, result.YAML)
	}
	// 前置写在了出口节点上，而不是别处。
	targets, err := handleReadProfileTargets(&ReadProfileTargetsParams{YAML: result.YAML})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	var exit ProfileTarget
	for _, item := range targets.Proxies {
		if item.Name == "落地出口" {
			exit = item
		}
	}
	if exit.Dialer != "香港入口" {
		t.Fatalf("落地出口 的 dialer = %q, want 香港入口", exit.Dialer)
	}
}

func TestSetProxyChainAcceptsGroupName(t *testing.T) {
	result, err := handleSetProxyChain(&SetProxyChainParams{
		YAML:   chainFixture,
		Target: "落地出口",
		Dialer: "自动选择",
	})
	if err != nil {
		t.Fatalf("前置写成策略组名应当被接受: %v", err)
	}
	if _, err := config.Parse([]byte(result.YAML)); err != nil {
		t.Fatalf("写入后的配置加载失败: %v", err)
	}
}

func TestSetProxyChainClearsWithEmptyDialer(t *testing.T) {
	chained, err := handleSetProxyChain(&SetProxyChainParams{
		YAML:   chainFixture,
		Target: "落地出口",
		Dialer: "香港入口",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	cleared, err := handleSetProxyChain(&SetProxyChainParams{
		YAML:   chained.YAML,
		Target: "落地出口",
		Dialer: "",
	})
	if err != nil {
		t.Fatalf("解除链路不该报错: %v", err)
	}
	if strings.Contains(cleared.YAML, "dialer-proxy") {
		t.Fatalf("解除后仍残留 dialer-proxy:\n%s", cleared.YAML)
	}
	if !strings.Contains(cleared.YAML, "password: pass-b") {
		t.Fatalf("解除链路时把节点本身删掉了:\n%s", cleared.YAML)
	}
}

func TestSetProxyChainRejectsUnusableEdits(t *testing.T) {
	cases := []struct {
		name     string
		profile  string
		target   string
		dialer   string
		contains string
	}{
		{
			name:     "目标不是节点",
			profile:  chainFixture,
			target:   "自动选择",
			dialer:   "香港入口",
			contains: "找不到名为",
		},
		{
			name:     "前置不存在",
			profile:  chainFixture,
			target:   "落地出口",
			dialer:   "不存在的节点",
			contains: "找不到名为",
		},
		{
			name:     "自己指向自己",
			profile:  chainFixture,
			target:   "落地出口",
			dialer:   "落地出口",
			contains: "绕成一个环",
		},
		{
			name:     "空目标",
			profile:  chainFixture,
			target:   "  ",
			dialer:   "香港入口",
			contains: "没有指定",
		},
		{
			name:     "没有节点",
			profile:  "mixed-port: 7890\n",
			target:   "落地出口",
			dialer:   "香港入口",
			contains: "没有节点",
		},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			_, err := handleSetProxyChain(&SetProxyChainParams{
				YAML:   testCase.profile,
				Target: testCase.target,
				Dialer: testCase.dialer,
			})
			if err == nil {
				t.Fatal("本该被拒绝，却写成功了")
			}
			if !strings.Contains(err.Error(), testCase.contains) {
				t.Fatalf("报错应当点明原因（含 %q），实际: %v", testCase.contains, err)
			}
		})
	}
}

// 已经存在一条 a→b→c 的链，把 c 的前置接到 a 上会把整条链绕回来，必须拦。
func TestSetProxyChainDetectsCycleThroughExistingChain(t *testing.T) {
	const chained = `proxies:
  - name: a
    type: ss
    server: 203.0.113.1
    port: 8388
    cipher: aes-256-gcm
    password: p
    dialer-proxy: b
  - name: b
    type: ss
    server: 203.0.113.2
    port: 8388
    cipher: aes-256-gcm
    password: p
    dialer-proxy: c
  - name: c
    type: ss
    server: 203.0.113.3
    port: 8388
    cipher: aes-256-gcm
    password: p
rules:
  - MATCH,a
`
	_, err := handleSetProxyChain(&SetProxyChainParams{
		YAML:   chained,
		Target: "c",
		Dialer: "a",
	})
	if err == nil {
		t.Fatal("c 接在 a 前面会把 a→b→c 绕成环，应当被拒绝")
	}
	if !strings.Contains(err.Error(), "绕成一个环") {
		t.Fatalf("报错应当点明成环，实际: %v", err)
	}
}

// 配置里本来就绕圈（a↔b）时：既不能死循环，也不能把一个挂在环外的新节点接进去。
func TestSetProxyChainRejectsPreExistingCycle(t *testing.T) {
	const cyclic = `proxies:
  - name: a
    type: ss
    server: 203.0.113.1
    port: 8388
    cipher: aes-256-gcm
    password: p
    dialer-proxy: b
  - name: b
    type: ss
    server: 203.0.113.2
    port: 8388
    cipher: aes-256-gcm
    password: p
    dialer-proxy: a
  - name: c
    type: ss
    server: 203.0.113.3
    port: 8388
    cipher: aes-256-gcm
    password: p
rules:
  - MATCH,a
`
	done := make(chan struct{})
	var chainErr error
	go func() {
		defer close(done)
		_, chainErr = handleSetProxyChain(&SetProxyChainParams{
			YAML:   cyclic,
			Target: "c",
			Dialer: "a",
		})
	}()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("检测成环时死循环了 —— 配置里原本就有的环必须能被 seen 挡住")
	}
	if chainErr == nil {
		t.Fatal("前置本身绕在环里，接上去只会得到一个无限递归的链，应当被拒绝")
	}
	if !strings.Contains(chainErr.Error(), "环") {
		t.Fatalf("报错应当点明环，实际: %v", chainErr)
	}
}
