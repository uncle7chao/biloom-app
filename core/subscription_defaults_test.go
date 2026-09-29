package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// 默认策略组与兜底规则的回归测试。
//
// 这一层的失败方式很讨厌：转换阶段一切正常，直到内核加载配置时才报
// "proxy [xxx] not found" 或 geodata 分类找不到 —— 用户看到的是「导入成功但用不了」。
// 所以下面三条不变量都要锁住：
//  1. 分组引用的每个名字都能解析（节点名 / 内置代理 / 另一个分组）；
//  2. 分组名与节点名不重名；
//  3. 规则里的 GEOIP / GEOSITE 分类名真实存在于随包发布的 geodata。

// collectGroupTargets 摊平所有分组引用的名字，供调用方逐个核对。
func collectGroupTargets(groups []map[string]any) []string {
	var targets []string
	for _, group := range groups {
		raw, ok := group["proxies"].([]any)
		if !ok {
			continue
		}
		for _, item := range raw {
			if name, ok := item.(string); ok {
				targets = append(targets, name)
			}
		}
	}
	return targets
}

// builtinProxyNames 是内核在 parseProxies 里无条件注册的代理名
// （config.go: proxies["DIRECT"] / ["REJECT"] …），分组可以直接引用它们。
var builtinProxyNames = map[string]bool{
	"DIRECT": true, "REJECT": true, "REJECT-DROP": true,
	"COMPATIBLE": true, "PASS": true, "PASS-RULE": true,
}

func TestConvertSubscriptionInjectsUsableDefaults(t *testing.T) {
	shape := convertToShape(t, vlessShareLinkFixture+"\n"+trojanShareLinkFixture)

	nodeNames := map[string]bool{}
	for _, proxy := range shape.Proxies {
		if name, ok := proxy["name"].(string); ok {
			nodeNames[name] = true
		}
	}
	if len(nodeNames) != 2 {
		t.Fatalf("fixture should yield 2 nodes, got %d", len(nodeNames))
	}

	groupNames := map[string]bool{}
	for _, group := range shape.ProxyGroups {
		name, _ := group["name"].(string)
		if name == "" {
			t.Fatalf("group without a name: %v", group)
		}
		if groupNames[name] {
			t.Fatalf("duplicated group name: %s", name)
		}
		if nodeNames[name] {
			t.Fatalf("group name collides with a node name: %s", name)
		}
		groupNames[name] = true
	}
	if len(groupNames) != 5 {
		t.Fatalf("expected 5 default groups, got %d (%v)", len(groupNames), groupNames)
	}

	if first, _ := shape.ProxyGroups[0]["name"].(string); first != defaultGroupProxies {
		t.Fatalf("first group = %q, want %q", first, defaultGroupProxies)
	}
	// select 组默认选中第一项 —— 把自动选择排在最前，新导入的配置不做任何操作
	// 就能走当前最快的节点。
	selectorTargets, _ := shape.ProxyGroups[0]["proxies"].([]any)
	if len(selectorTargets) == 0 || selectorTargets[0] != defaultGroupAuto {
		t.Fatalf("selector group should default to %s, got %v", defaultGroupAuto, selectorTargets)
	}

	// 每个被引用的名字都必须能解析。名字对不上时内核会拒绝加载整份配置。
	for _, target := range collectGroupTargets(shape.ProxyGroups) {
		if nodeNames[target] || groupNames[target] || builtinProxyNames[target] {
			continue
		}
		t.Fatalf("group references an unresolvable proxy: %s", target)
	}

	// 没有 MATCH 兜底的话，规则模式下所有连接都会落到 DIRECT（tunnel.go 的 match()
	// 末尾就是 `return proxies["DIRECT"]`），表现就是「连上了但什么都没走代理」。
	if len(shape.Rules) == 0 {
		t.Fatal("no rules were injected")
	}
	last := shape.Rules[len(shape.Rules)-1]
	if !strings.EqualFold(last, "MATCH,"+defaultGroupFinal) {
		t.Fatalf("last rule = %q, want MATCH,%s", last, defaultGroupFinal)
	}

	// 规则里指向的目标同样必须能解析 —— 指向不存在的分组会让内核拒绝加载整份配置，
	// 而报错发生在「加载」阶段，看起来跟规则毫无关系。
	for _, rule := range shape.Rules {
		parts := strings.Split(rule, ",")
		var target string
		switch {
		case len(parts) == 2 && strings.EqualFold(parts[0], "MATCH"):
			target = parts[1]
		case len(parts) >= 3:
			target = parts[2]
		default:
			t.Fatalf("rule %q does not name a target", rule)
		}
		if !groupNames[target] && !builtinProxyNames[target] {
			t.Fatalf("rule %q points at an unresolvable target", rule)
		}
	}

	// 内网要直连，否则 LAN 里的设备（路由器后台、NAS）会因为走代理而访问不到。
	joined := strings.Join(shape.Rules, "\n")
	if !strings.Contains(joined, "GEOIP,LAN,") {
		t.Error("内网网段没有直连规则：LAN 设备会因为走代理而访问不到")
	}

	// 国内分流必须是「域名类规则在前、IP 类规则在后」，且 GEOIP,CN 不得带 no-resolve。
	// 这两条都反直觉，写反了既不会编译报错、也不会在加载时报错，只会在用户那里
	// 表现为「国内网站也慢 / 也走代理」，极难回溯，所以在这里钉死。
	if !strings.Contains(joined, "GEOSITE,CN,") {
		t.Error(
			"缺 GEOSITE,CN：国内域名要先做一次同步 DNS 解析才轮得到 GEOIP,CN 判定，" +
				"打开国内站点的体感延迟会明显偏高",
		)
	}
	if strings.Index(joined, "GEOSITE,CN,") > strings.Index(joined, "GEOIP,CN,") {
		t.Error("GEOSITE,CN 排在 GEOIP,CN 之后，等于白写：该发生的解析已经发生过了")
	}
	if strings.Contains(joined, "GEOIP,CN,"+defaultGroupDirect+",no-resolve") {
		t.Error(
			"GEOIP,CN 带了 no-resolve：fake-ip 模式下内核已把 DstIP 清空、只留 Host，" +
				"这条规则会在 !ip.IsValid() 处直接 return false —— 国内 IP 流量全部绕去代理",
		)
	}
}

// 机场节点名什么都有。真有节点叫「节点选择」时，分组必须让位，而不是让配置加载失败。
func TestDefaultSubscriptionGroupsAvoidNodeNameCollisions(t *testing.T) {
	proxies := []map[string]any{
		{"name": defaultGroupProxies},
		{"name": defaultGroupProxies},
		{"name": defaultGroupFinal},
		{"name": "HK-1"},
	}
	groups, rules := defaultSubscriptionGroups(proxies)

	used := map[string]bool{}
	for _, proxy := range proxies {
		used[proxy["name"].(string)] = true
	}
	for _, group := range groups {
		name := group["name"].(string)
		if used[name] {
			t.Fatalf("group kept a colliding name: %s", name)
		}
		used[name] = true
	}

	// 让位之后 MATCH 必须指向改名后的那个「漏网之鱼」，否则规则指向不存在的分组。
	target := groups[len(groups)-1]["name"].(string)
	if rules[len(rules)-1] != "MATCH,"+target {
		t.Fatalf("MATCH target %q does not match the renamed group %q",
			rules[len(rules)-1], target)
	}
}

// 「代理」页只该看到两个分组：节点选择 / 自动选择。其余四个是 rules 的目标 ——
// 规则里必须写一个目标名（`GEOSITE,CN,全球直连` 里的那个名字），所以它们得存在，
// 但不必各占一个页签，标 hidden。
//
// 这条不变量的两头都会静默失效：
//   - 少标一个 → 用户页签栏里多一个看不懂的标签（这次就是这么被用户发现的：
//     「这些个标签是你起的？乱七八糟的，根本就没有实际意义」）；
//   - 多标一个（把 selector / auto 也标上）→ 页签栏直接空掉，用户连节点列表和
//     测速按钮都找不到。
//
// 两头都不编译报错、也不在加载时报错，只在界面上表现出来，所以在这里钉死。
func TestDefaultSubscriptionGroupsHidePlumbingOnly(t *testing.T) {
	shape := convertToShape(t, vlessShareLinkFixture+"\n"+trojanShareLinkFixture)

	wantVisible := []string{defaultGroupProxies, defaultGroupAuto}
	wantHidden := []string{
		defaultGroupFallback,
		defaultGroupDirect,
		defaultGroupFinal,
	}

	var visible, hidden []string
	for _, group := range shape.ProxyGroups {
		name, _ := group["name"].(string)
		raw, marked := group["hidden"]
		if !marked {
			visible = append(visible, name)
			continue
		}
		// 必须是真 bool，不能是字符串 "true"：内核把它解到 Go 的 bool 字段
		// （outboundgroup/parser.go 的 `group:"hidden,omitempty"`），字符串会让
		// 整份配置解析失败 —— 而用户看到的是「订阅导入失败」，和分组毫无表面关联。
		if value, ok := raw.(bool); !ok || !value {
			t.Fatalf("group %q 的 hidden 不是 true: %#v", name, raw)
		}
		hidden = append(hidden, name)
	}

	// 顺序也管：可见分组里 node select 必须排第一 —— select 组默认选中第一项，
	// 它不在首位，「代理」页打开时就不在用户入口上了。
	if strings.Join(visible, ",") != strings.Join(wantVisible, ",") {
		t.Errorf("「代理」页可见分组 = %v，应只有 %v", visible, wantVisible)
	}
	if strings.Join(hidden, ",") != strings.Join(wantHidden, ",") {
		t.Errorf("隐藏分组 = %v，应为 %v", hidden, wantHidden)
	}

	// 隐藏的分组必须仍然被规则引用 —— 否则「藏」就退化成了「删」，
	// 国内分流会失效，而且界面上没有任何提示。（广告拦截组已随 2026-09-29
	// 的规则删除一并移除 —— 它会 REJECT 掉 AdMob/AdSense 全家，包括我们
	// 自己的广告变现流量。）
	joined := strings.Join(shape.Rules, "\n")
	for _, name := range []string{defaultGroupDirect} {
		if !strings.Contains(joined, ","+name) {
			t.Errorf("没有任何规则指向隐藏分组 %q：它要么成了死重量，要么分流已经断了", name)
		}
	}
	if !strings.HasSuffix(joined, "MATCH,"+defaultGroupFinal) {
		t.Errorf("MATCH 没有指向隐藏分组 %q，规则模式下没命中的流量会落到 DIRECT",
			defaultGroupFinal)
	}
}

// 默认规则里的 GEOIP / GEOSITE 分类名必须能被内核解析。写错名字既不会编译报错、
// 也不会在转换时报错，只会在内核加载配置时失败，而报错内容和「订阅格式」毫无关系，
// 极难定位 —— 起草这套规则时原本写的是 GEOIP,PRIVATE，而它在默认的 metadb 模式下
// 未必查得到。
//
// GEOIP,LAN 是唯一的例外，而且必须留着这个例外：内核在 rules/common/geoip.go 的
// NewGEOIP 里对 country=="lan" 直接 return，用 iputil 判断，不查任何 geodata，
// 所以它本来就不该出现在 geodata 的分类表里。
func TestDefaultSubscriptionRulesMatchBundledGeodata(t *testing.T) {
	geoip := geoCodes(t, "GEOIP.dat")
	geosite := geoCodes(t, "GEOSITE.dat")

	_, rules := defaultSubscriptionGroups([]map[string]any{{"name": "HK-1"}})
	checked := 0
	for _, rule := range rules {
		parts := strings.Split(rule, ",")
		if len(parts) < 2 {
			continue
		}
		payload := strings.ToUpper(parts[1])
		switch parts[0] {
		case "GEOIP":
			if payload == "LAN" {
				continue // 内核代码级特例，见上面的说明
			}
			checked++
			if !geoip[payload] {
				t.Errorf("GEOIP 分类 %q 不在随包 geodata 里，这会让配置加载失败", parts[1])
			}
		case "GEOSITE":
			checked++
			if !geosite[payload] {
				t.Errorf("GEOSITE 分类 %q 不在随包 geodata 里，这会让配置加载失败", parts[1])
			}
		}
	}
	if checked == 0 {
		t.Fatal("默认规则完全没有用到 geodata，这条用例失去了意义")
	}
}

// 广告拦截规则必须保持删除状态（2026-09-29 用户拍板）。CATEGORY-ADS-ALL 收录了
// admob.com / googlesyndication.com / doubleclick.net 等 —— BiLoom 自己的变现就是
// AdMob/AdSense，这条规则等于默认把用户访问广告后台、乃至 Android 版自家广告 SDK
// 的流量全部 REJECT。谁要是把它加回来，这条用例会拦住。
func TestDefaultSubscriptionRulesMustNotBlockAds(t *testing.T) {
	_, rules := defaultSubscriptionGroups([]map[string]any{{"name": "HK-1"}})
	joined := strings.Join(rules, "\n")
	if strings.Contains(joined, "CATEGORY-ADS-ALL") {
		t.Fatalf("默认规则里出现了广告拦截（CATEGORY-ADS-ALL），会 REJECT 掉 AdMob/AdSense 流量：\n%s", joined)
	}
	for _, rule := range rules {
		if strings.Contains(rule, "REJECT") {
			t.Fatalf("默认规则里出现了 REJECT 出站：%s", rule)
		}
	}
}

// --- 包内 geodata 分类名核对 -------------------------------------------------
//
// assets/data 下的 GEOIP.dat / GEOSITE.dat 是 MetaCubeX 的 protobuf 格式：
//
//	GeoIPList   { repeated GeoIP   entry = 1 }   GeoIP  { string country_code = 1; … }
//	GeoSiteList { repeated GeoSite entry = 1 }   GeoSite{ string country_code = 1; … }
//
// 只需要「取每层 field 1 的字符串」，不值得为它引入 protobuf 运行时，这里带一个
// 够用的走读器。顺带说明为什么不能直接搜字节：分类名前面跟着变长字段头，
// 裸搜既可能漏也可能误命中。

func pbVarint(buf []byte, pos int) (uint64, int, error) {
	var value uint64
	shift := uint(0)
	for {
		if pos >= len(buf) {
			return 0, 0, io.ErrUnexpectedEOF
		}
		byteVal := buf[pos]
		pos++
		value |= uint64(byteVal&0x7F) << shift
		if byteVal&0x80 == 0 {
			return value, pos, nil
		}
		shift += 7
		if shift > 63 {
			return 0, 0, fmt.Errorf("varint overflow")
		}
	}
}

func pbWalk(buf []byte, visit func(field, wire int, payload []byte)) error {
	pos := 0
	for pos < len(buf) {
		key, next, err := pbVarint(buf, pos)
		if err != nil {
			return err
		}
		field, wire := int(key>>3), int(key&0x07)
		pos = next
		var payload []byte
		switch wire {
		case 0:
			value, next, err := pbVarint(buf, pos)
			if err != nil {
				return err
			}
			payload = []byte(strconv.FormatUint(value, 10))
			pos = next
		case 1:
			if pos+8 > len(buf) {
				return io.ErrUnexpectedEOF
			}
			payload, pos = buf[pos:pos+8], pos+8
		case 2:
			length, next, err := pbVarint(buf, pos)
			if err != nil {
				return err
			}
			if next+int(length) > len(buf) {
				return io.ErrUnexpectedEOF
			}
			payload, pos = buf[next:next+int(length)], next+int(length)
		case 5:
			if pos+4 > len(buf) {
				return io.ErrUnexpectedEOF
			}
			payload, pos = buf[pos:pos+4], pos+4
		default:
			return fmt.Errorf("unsupported wire type %d", wire)
		}
		visit(field, wire, payload)
	}
	return nil
}

func geoCodes(t *testing.T, name string) map[string]bool {
	t.Helper()
	buf, err := os.ReadFile(filepath.Join("..", "assets", "data", name))
	if err != nil {
		t.Skipf("bundled geodata is not available: %v", err)
	}
	codes := map[string]bool{}
	err = pbWalk(buf, func(field, wire int, payload []byte) {
		if field != 1 || wire != 2 {
			return
		}
		// 每个顶层 entry 内部的 field 1 就是分类名。
		if err := pbWalk(payload, func(inner, innerWire int, innerPayload []byte) {
			if inner == 1 && innerWire == 2 {
				codes[strings.ToUpper(string(innerPayload))] = true
			}
		}); err != nil {
			t.Errorf("walk entry of %s: %v", name, err)
		}
	})
	if err != nil {
		t.Fatalf("walk %s: %v", name, err)
	}
	if len(codes) == 0 {
		t.Fatalf("%s yielded no categories", name)
	}
	return codes
}
