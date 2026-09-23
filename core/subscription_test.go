package main

import (
	"encoding/base64"
	"os"
	"strings"
	"testing"

	"github.com/metacubex/mihomo/common/yaml"
)

// 订阅兼容层的回归测试。
//
// 这些用例都刻意写成「服务商真实会吐出来的形状」，而不是最小可解析样例 ——
// 这一层的价值全在真实形状上：带 early data 的 ws、xhttp 的 mode、ssd 里
// 逐节点覆盖顶层字段、sing-box 的 outbounds 里混着 selector/direct。

const (
	// bareProxiesFixture 刻意**只有 proxies**：它模拟的是「用户手写的片段」或
	// 「先建空白配置、再加节点」的中间态，而不是机场订阅的形状 —— 服务商吐出来的
	// Clash 配置一定带 proxy-groups 与 rules。两种形状会走到转换层的不同分支，
	// 所以两个 fixture 都得留着。
	bareProxiesFixture = `proxies:
  - name: clash-ss
    type: ss
    server: 1.2.3.4
    port: 8388
    cipher: aes-256-gcm
    password: pass
`

	// clashWithGroupsFixture 是机场订阅的真实形状：自带分组与规则，还带注释。
	// 转换层对它必须一个字节都不改 —— 那是服务商自己的设计。
	clashWithGroupsFixture = `# 服务商写的注释，必须原样保留
proxies:
  - name: HK-01
    type: ss
    server: 1.2.3.4
    port: 8388
    cipher: aes-256-gcm
    password: pass
proxy-groups:
  - name: 机场自选
    type: select
    proxies:
      - HK-01
      - DIRECT
rules:
  - MATCH,机场自选
`

	vlessShareLinkFixture = "vless://8dd89a84-66b6-4d39-ab12-c2b2b2c4ff66@v.example.com:443" +
		"?encryption=none&security=tls&sni=v.example.com&fp=chrome&type=ws" +
		"&host=v.example.com&path=%2F%3Fed%3D2048#HK-443-WS-TLS"

	trojanShareLinkFixture = "trojan://secret-pw@t.example.com:443" +
		"?security=tls&sni=t.example.com&type=ws&host=t.example.com&path=%2Fws#JP-Trojan"

	xhttpShareLinkFixture = "vless://uuid-xhttp@x.example.com:443" +
		"?encryption=none&security=tls&sni=x.example.com&type=xhttp" +
		"&host=x.example.com&path=%2Fx&mode=stream-one#XHTTP-Node"

	singBoxFixture = `{
  "log": {"level": "info"},
  "outbounds": [
    {
      "type": "vless",
      "tag": "sb-hk",
      "server": "sb.example.com",
      "server_port": 443,
      "uuid": "11111111-1111-1111-1111-111111111111",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "sb.example.com",
        "insecure": true,
        "utls": {"enabled": true, "fingerprint": "chrome"}
      },
      "transport": {"type": "ws", "path": "/ws", "headers": {"Host": "sb.example.com"}}
    },
    {
      "type": "trojan",
      "tag": "sb-jp",
      "server": "tj.example.com",
      "server_port": 8443,
      "password": "pw-jp",
      "tls": {"enabled": true, "server_name": "tj.example.com"}
    },
    {"type": "selector", "tag": "auto", "outbounds": ["sb-hk"]},
    {"type": "direct", "tag": "direct"}
  ]
}`

	ssdFixtureJSON = `{"airport":"demo","port":443,"encryption":"aes-256-gcm","password":"top-secret",` +
		`"servers":[{"server":"a.example.com","remarks":"A"},` +
		`{"server":"b.example.com","port":8443,"password":"p2","remarks":"B"}]}`
)

func base64Fixture(text string) string {
	return base64.StdEncoding.EncodeToString([]byte(text))
}

type profileShape struct {
	Proxies     []map[string]any `yaml:"proxies"`
	ProxyGroups []map[string]any `yaml:"proxy-groups"`
	Rules       []string         `yaml:"rules"`
}

func convertToShape(t *testing.T, input string) profileShape {
	t.Helper()
	converted, err := subscriptionToProfileYAML([]byte(input))
	if err != nil {
		t.Fatalf("convert failed: %v", err)
	}
	var shape profileShape
	if err := yaml.Unmarshal(converted.YAML, &shape); err != nil {
		t.Fatalf("converted output is not parseable YAML: %v\n%s", err, converted.YAML)
	}
	return shape
}

func TestConvertSubscriptionClashPassthrough(t *testing.T) {
	converted, err := subscriptionToProfileYAML([]byte(clashWithGroupsFixture))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if converted.Format != subscriptionFormatClash {
		t.Fatalf("format = %q, want clash", converted.Format)
	}
	if converted.Changed {
		t.Fatal("a Clash profile must be passed through untouched")
	}
	if string(converted.YAML) != clashWithGroupsFixture {
		t.Fatalf("payload was rewritten:\n%s", converted.YAML)
	}
}

// 只有 proxies、没有任何策略组的配置，原样放行等于给用户一份用不了的配置：
// 「代理」页签由分组驱动会整块消失，且所有流量都走 DIRECT（内核在规则全不命中时
// 把连接交给 DIRECT）。转换层要补上默认分组与兜底规则 —— 但**不能碰节点本身**。
func TestConvertSubscriptionBackfillsMissingGroups(t *testing.T) {
	converted, err := subscriptionToProfileYAML([]byte(bareProxiesFixture))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !converted.Changed {
		t.Fatal("a bare proxies profile must be backfilled with default groups")
	}
	var shape profileShape
	if err := yaml.Unmarshal(converted.YAML, &shape); err != nil {
		t.Fatalf("backfilled output is not parseable YAML: %v\n%s", err, converted.YAML)
	}
	if len(shape.Proxies) != 1 || shape.Proxies[0]["name"] != "clash-ss" {
		t.Fatalf("original nodes must survive backfilling, got %+v", shape.Proxies)
	}
	if len(shape.ProxyGroups) == 0 {
		t.Fatal("default groups were not injected")
	}
	if len(shape.Rules) == 0 {
		t.Fatal("fallback rules were not injected")
	}
	if converted.NodeCount != 1 {
		t.Fatalf("node count = %d, want 1", converted.NodeCount)
	}
}

func TestConvertSubscriptionBase64V2Ray(t *testing.T) {
	payload := vlessShareLinkFixture + "\n" + trojanShareLinkFixture + "\n"
	shape := convertToShape(t, base64Fixture(payload))

	if len(shape.Proxies) != 2 {
		t.Fatalf("got %d proxies, want 2", len(shape.Proxies))
	}

	vless := shape.Proxies[0]
	if vless["type"] != "vless" || vless["server"] != "v.example.com" {
		t.Fatalf("unexpected vless mapping: %v", vless)
	}
	if vless["name"] != "HK-443-WS-TLS" {
		t.Fatalf("node name lost: %v", vless["name"])
	}
	if vless["servername"] != "v.example.com" || vless["tls"] != true {
		t.Fatalf("tls mapping wrong: %v", vless)
	}
	if vless["network"] != "ws" {
		t.Fatalf("network = %v, want ws", vless["network"])
	}
	// path=/?ed=2048 是 v2ray 生态里的通行写法:early data 请求直接编在路径里，
	// 由服务端解释。必须原样保留 —— 顺手把它拆成 max-early-data 反而会让
	// 服务端认不出而这个节点连不上。
	wsOpts, ok := vless["ws-opts"].(map[string]any)
	if !ok {
		t.Fatalf("ws-opts missing: %v", vless)
	}
	if wsOpts["path"] != "/?ed=2048" {
		t.Fatalf("ws path = %v", wsOpts["path"])
	}

	trojan := shape.Proxies[1]
	if trojan["type"] != "trojan" || trojan["password"] != "secret-pw" {
		t.Fatalf("unexpected trojan mapping: %v", trojan)
	}
	if trojan["sni"] != "t.example.com" {
		t.Fatalf("trojan sni = %v", trojan["sni"])
	}
}

func TestConvertSubscriptionWebSocketEarlyData(t *testing.T) {
	// early data 写在顶层 query(ed=N)时才是 max-early-data，两个位置语义不同。
	link := "vless://uuid-ed@ed.example.com:443?encryption=none&security=tls" +
		"&sni=ed.example.com&type=ws&host=ed.example.com&path=%2Fws&ed=2048#ED-Node"
	shape := convertToShape(t, link)
	wsOpts, ok := shape.Proxies[0]["ws-opts"].(map[string]any)
	if !ok {
		t.Fatalf("ws-opts missing: %v", shape.Proxies[0])
	}
	if wsOpts["max-early-data"] != 2048 {
		t.Fatalf("max-early-data = %v, want 2048", wsOpts["max-early-data"])
	}
	if wsOpts["early-data-header-name"] != "Sec-WebSocket-Protocol" {
		t.Fatalf("early-data-header-name = %v", wsOpts["early-data-header-name"])
	}
}

// JSON 是 YAML 的子集，所以服务端返回的 JSON 错误体有可能被当成「合法但没节点」的
// Clash 配置原样放行 —— 那会让用户拿到一个空节点列表而不是报错。这条用例锁住顺序。
func TestConvertSubscriptionRejectsJsonErrorBody(t *testing.T) {
	for _, body := range []string{
		`{"code":1,"msg":"subscription expired"}`,
		`{"data":null}`,
	} {
		_, err := subscriptionToProfileYAML([]byte(body))
		if err == nil {
			t.Fatalf("JSON body was accepted as a config: %s", body)
		}
		// 报错里要带上服务端原文，否则用户只看到「无法识别」无从判断是过期还是被墙。
		if !strings.Contains(err.Error(), "expired") && !strings.Contains(err.Error(), "data") {
			t.Fatalf("error does not quote the server payload: %v", err)
		}
	}
}

func TestConvertSubscriptionPlainTextShareLinks(t *testing.T) {
	// 明文列表和 base64 是同一种订阅的两种封装，嗅探必须都认。
	converted, err := subscriptionToProfileYAML([]byte(vlessShareLinkFixture))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if converted.Format != subscriptionFormatV2Ray {
		t.Fatalf("format = %q, want v2ray", converted.Format)
	}
	if !converted.Changed || converted.NodeCount != 1 {
		t.Fatalf("changed=%v nodeCount=%d", converted.Changed, converted.NodeCount)
	}
}

func TestConvertSubscriptionXHTTPTransport(t *testing.T) {
	// xhttp 是新版 Xray 的传输，老客户端一律不认。内核的 convert 包已经支持，
	// 这里锁住「别在嗅探环节把它当垃圾丢掉」。
	shape := convertToShape(t, xhttpShareLinkFixture)
	if len(shape.Proxies) != 1 {
		t.Fatalf("got %d proxies, want 1", len(shape.Proxies))
	}
	proxy := shape.Proxies[0]
	if proxy["network"] != "xhttp" {
		t.Fatalf("network = %v, want xhttp", proxy["network"])
	}
	xhttpOpts, ok := proxy["xhttp-opts"].(map[string]any)
	if !ok {
		t.Fatalf("xhttp-opts missing: %v", proxy)
	}
	if xhttpOpts["mode"] != "stream-one" || xhttpOpts["path"] != "/x" {
		t.Fatalf("xhttp-opts = %v", xhttpOpts)
	}
}

func TestConvertSubscriptionSingBox(t *testing.T) {
	converted, err := subscriptionToProfileYAML([]byte(singBoxFixture))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if converted.Format != subscriptionFormatSingBox {
		t.Fatalf("format = %q, want sing-box", converted.Format)
	}

	var shape profileShape
	if err := yaml.Unmarshal(converted.YAML, &shape); err != nil {
		t.Fatalf("output not parseable: %v", err)
	}
	// selector / direct 不是节点，必须被跳过而不是变成两个假节点。
	if len(shape.Proxies) != 2 {
		t.Fatalf("got %d proxies, want 2 (%v)", len(shape.Proxies), shape.Proxies)
	}

	vless := shape.Proxies[0]
	if vless["uuid"] != "11111111-1111-1111-1111-111111111111" {
		t.Fatalf("uuid lost: %v", vless)
	}
	if vless["flow"] != "xtls-rprx-vision" {
		t.Fatalf("flow lost: %v", vless["flow"])
	}
	if vless["skip-cert-verify"] != true || vless["client-fingerprint"] != "chrome" {
		t.Fatalf("tls details lost: %v", vless)
	}
	if vless["network"] != "ws" {
		t.Fatalf("network = %v", vless["network"])
	}
	wsOpts, _ := vless["ws-opts"].(map[string]any)
	if wsOpts == nil {
		t.Fatalf("ws-opts missing: %v", vless)
	}
	headers, _ := wsOpts["headers"].(map[string]any)
	if headers == nil || headers["Host"] != "sb.example.com" {
		t.Fatalf("ws Host header lost: %v", wsOpts)
	}

	trojan := shape.Proxies[1]
	if trojan["type"] != "trojan" || trojan["password"] != "pw-jp" {
		t.Fatalf("unexpected trojan mapping: %v", trojan)
	}
	if trojan["sni"] != "tj.example.com" {
		t.Fatalf("trojan sni = %v", trojan["sni"])
	}
}

func TestConvertSubscriptionSSD(t *testing.T) {
	shape := convertToShape(t, "ssd://"+base64Fixture(ssdFixtureJSON))
	if len(shape.Proxies) != 2 {
		t.Fatalf("got %d proxies, want 2", len(shape.Proxies))
	}

	first := shape.Proxies[0]
	// 第一个节点没写 port/password，必须回退到 ssd 顶层同名字段。
	if first["port"] != 443 || first["password"] != "top-secret" {
		t.Fatalf("top-level fallback failed: %v", first)
	}
	if first["cipher"] != "aes-256-gcm" {
		t.Fatalf("cipher = %v", first["cipher"])
	}

	second := shape.Proxies[1]
	if second["port"] != 8443 || second["password"] != "p2" {
		t.Fatalf("per-server override failed: %v", second)
	}
}

func TestConvertSubscriptionRejectsGarbage(t *testing.T) {
	_, err := subscriptionToProfileYAML([]byte("this is not a subscription at all"))
	if err == nil {
		t.Fatal("expected an error for unrecognised content")
	}
	// 报错必须是给人看的：这是用户唯一能拿到的一句话。
	if !strings.Contains(err.Error(), "无法识别该订阅格式") {
		t.Fatalf("error is not the user-facing message: %v", err)
	}
}

func TestConvertSubscriptionKeepsRawErrorForBrokenYaml(t *testing.T) {
	// 一份写坏的 Clash 配置要保留内核的原始报错（行号、字段名），
	// 换成「无法识别该订阅格式」反而让正在编辑配置的人无从下手。
	_, err := subscriptionToProfileYAML([]byte("proxies: [\n"))
	if err == nil {
		t.Fatal("expected an error for broken YAML")
	}
	if strings.Contains(err.Error(), "无法识别该订阅格式") {
		t.Fatalf("broken YAML was misclassified as an unknown subscription: %v", err)
	}
}

// 服务端返回 200 但正文为空是真实会发生的情况（链接过期、需要重新获取）。
// 报错要指向链接本身，而不是含糊地说「格式不认识」 —— 这两件事的排查方向完全不同。
//
// 判定位置是下载入口 handleConvertSubscription，而不是共用的 subscriptionToProfileYAML：
// 后者还被两条读磁盘的路径复用，那里的空配置必须放行（见下一条用例）。
func TestConvertSubscriptionRejectsAnEmptyBody(t *testing.T) {
	for _, body := range []string{"", "   ", "\n\n", "\ufeff\n", "\n# nothing here\n"} {
		_, err := handleConvertSubscription(body)
		if err == nil {
			t.Fatalf("empty body was accepted as a subscription: %q", body)
		}
		if !strings.Contains(err.Error(), "订阅内容为空") {
			t.Fatalf("error %q does not point at the empty body", err)
		}
	}
}

// 但「磁盘上的 profile 是空的」是合法状态（新建的配置、被清空的配置），内核按默认值
// 跑即可。上一版把这两件事混为一谈，结果 loadConfig 的空文件用例全量跑的时候挂了 ——
// 存量用户的空配置会突然加载失败。这条用例把它钉住。
func TestBlankProfileIsStillTreatedAsDefaults(t *testing.T) {
	// 两个入口都要覆盖，这是上一版留下的缺口：当时只修了 loadConfig 走的
	// subscriptionToFullConfigYAML，而编辑页保存、以及运行时配置生成走的是
	// subscriptionToProfileYAML —— 同一份空配置在那里被判成「订阅内容为空」，
	// 用户看到的是「这个配置永远无法启用」，且提示文案指向一个他根本没在下载的订阅。
	for _, body := range []string{"", "\n", "# only a comment\n", "---\n"} {
		out, format, err := subscriptionToFullConfigYAML([]byte(body))
		if err != nil {
			t.Fatalf("blank profile %q was rejected by loadConfig: %v", body, err)
		}
		if string(out) != body {
			t.Fatalf("blank profile %q was rewritten to %q", body, out)
		}
		if format != subscriptionFormatClash {
			t.Fatalf("blank profile %q reported format %q", body, format)
		}

		converted, err := subscriptionToProfileYAML([]byte(body))
		if err != nil {
			t.Fatalf(
				"blank profile %q was rejected on the profile path: %v",
				body,
				err,
			)
		}
		if string(converted.YAML) != body {
			t.Fatalf(
				"blank profile %q was rewritten to %q on the profile path",
				body,
				converted.YAML,
			)
		}
		if converted.Format != subscriptionFormatClash {
			t.Fatalf(
				"blank profile %q reported format %q on the profile path",
				body,
				converted.Format,
			)
		}
	}
}

// TestConvertSubscriptionRealFixture 用一条真实订阅跑端到端回归。
// 真实订阅含账号凭据，所以不进仓库：把原文写到文件里，用环境变量指过去即可。
//
//	BILOOM_SUB_FIXTURE=<path> go test ./... -run TestConvertSubscriptionRealFixture -v
func TestConvertSubscriptionRealFixture(t *testing.T) {
	path := os.Getenv("BILOOM_SUB_FIXTURE")
	if path == "" {
		t.Skip("BILOOM_SUB_FIXTURE not set")
	}
	body, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("cannot read fixture: %v", err)
	}
	converted, err := subscriptionToProfileYAML(body)
	if err != nil {
		t.Fatalf("convert failed: %v", err)
	}
	if converted.Format != subscriptionFormatV2Ray {
		t.Fatalf("format = %q, want v2ray", converted.Format)
	}
	if converted.NodeCount < 100 {
		t.Fatalf("nodeCount = %d, expected the full subscription", converted.NodeCount)
	}

	var shape profileShape
	if err := yaml.Unmarshal(converted.YAML, &shape); err != nil {
		t.Fatalf("output not parseable: %v", err)
	}
	if len(shape.Proxies) != converted.NodeCount {
		t.Fatalf("proxies = %d, nodeCount = %d", len(shape.Proxies), converted.NodeCount)
	}

	// 节点名必须唯一，否则 Clash 会丢节点。
	names := make(map[string]struct{}, len(shape.Proxies))
	networks := make(map[string]int)
	for _, proxy := range shape.Proxies {
		name, _ := proxy["name"].(string)
		if name == "" {
			t.Fatalf("node without a name: %v", proxy)
		}
		if _, duplicated := names[name]; duplicated {
			t.Fatalf("duplicated node name: %s", name)
		}
		names[name] = struct{}{}
		network, _ := proxy["network"].(string)
		networks[network]++
	}
	t.Logf("converted %d nodes, transports: %v", len(shape.Proxies), networks)

	if networks["xhttp"] == 0 {
		t.Error("subscription carries xhttp nodes but none survived the conversion")
	}

	// 真实订阅里节点名带各种符号与表情，是「YAML 转义把名字弄坏」最容易暴露的地方。
	// 「节点选择」必须把每一个节点都收进去，否则用户在代理页里看不到全部节点。
	if len(shape.ProxyGroups) != 6 {
		t.Fatalf("default groups = %d, want 6", len(shape.ProxyGroups))
	}
	selector, _ := shape.ProxyGroups[0]["proxies"].([]any)
	inSelector := make(map[string]bool, len(selector))
	for _, item := range selector {
		if name, ok := item.(string); ok {
			inSelector[name] = true
		}
	}
	for name := range names {
		if !inSelector[name] {
			t.Fatalf("node %q is missing from the default selector group", name)
		}
	}
	if len(shape.Rules) == 0 || !strings.HasPrefix(shape.Rules[len(shape.Rules)-1], "MATCH,") {
		t.Fatalf("default rules missing or without a MATCH fallback: %v", shape.Rules)
	}
}
