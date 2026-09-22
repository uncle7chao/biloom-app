package main

import "fmt"

// BiLoom: 订阅导入的「开箱可用」默认配置。
//
// 为什么必须有这一层：一份只带 proxies 的 profile 会同时踩到三个坑，而它们其实是
// 同一个根因 —— Clash 的策略组、规则、节点选择全都靠 proxy-groups / rules 驱动：
//
//  1. 内核在所有规则都不命中时把连接交给 DIRECT（tunnel.go 的 match() 末尾就是
//     `return proxies["DIRECT"], nil, nil`）。没有 MATCH 规则 = 连上了却什么都没
//     走代理，用户看到的是「已连接但网页打不开」。
//  2. FlClash 的「代理」页签由策略组列表驱动；规则模式下 GLOBAL 会被过滤掉，
//     分组为空 → 页签整个消失，用户连节点列表和测速按钮都找不到。
//  3. 没有分组就没有「自动选择」，每个新用户都得自己一个个点节点试。
//
// 所以转换订阅时除了 proxies 还要补一套默认分组与兜底规则。只在「确实发生了转换」
// 时注入 —— 本来就是 Clash 配置的订阅已经带着服务商自己的 proxy-groups 与 rules，
// 那是服务商的设计，不该被我们覆盖。

const (
	defaultGroupProxies  = "节点选择"
	defaultGroupAuto     = "自动选择"
	defaultGroupFallback = "故障转移"
	defaultGroupDirect   = "全球直连"
	defaultGroupAdBlock  = "广告拦截"
	defaultGroupFinal    = "漏网之鱼"
)

// defaultSubscriptionGroups 依据订阅里的节点名生成默认策略组与兜底规则。
//
// 规则里用到的 GEOIP / GEOSITE 分类名必须能被内核解析。名字写错的后果不是「规则
// 不生效」，而是内核加载配置直接报错、用户看到的是导入失败。所以这里只挑三种情况：
//   - GEOIP,LAN —— 内核在 rules/common/geoip.go 里对 country=="lan" 有专门分支，
//     直接用 iputil 判断，连 geodata 都不查；
//   - GEOIP,CN 与 GEOSITE,CATEGORY-ADS-ALL —— 已在随包发布的 assets/data/*.dat
//     里逐条核对过（core/subscription_defaults_test.go 会持续守着）。
//
// 顺带记一笔踩过的坑：最初这里写的是 GEOIP,PRIVATE。GEOIP.dat 里确实有 PRIVATE
// 这一条，但那只在 geodata-mode 下生效；默认走的是 GEOIP.metadb，PRIVATE 未必查得到。
// 而 LAN 是代码级特例，与用哪套数据无关 —— 这也是机场普遍写 LAN 而不是 PRIVATE 的原因。
func defaultSubscriptionGroups(proxies []map[string]any) ([]map[string]any, []string) {
	names := make([]string, 0, len(proxies))
	for _, proxy := range proxies {
		if name, ok := proxy["name"].(string); ok && name != "" {
			names = append(names, name)
		}
	}

	// 分组名与节点名共用同一个命名空间：Clash 里重名会让整份配置加载失败。
	// 机场节点名什么都有（真见过叫「节点选择」的），所以逐个让位，而不是假定它不存在。
	used := make(map[string]bool, len(names)+6)
	for _, name := range names {
		used[name] = true
	}
	unique := func(base string) string {
		if !used[base] {
			used[base] = true
			return base
		}
		for suffix := 1; ; suffix++ {
			candidate := fmt.Sprintf("%s %d", base, suffix)
			if !used[candidate] {
				used[candidate] = true
				return candidate
			}
		}
	}

	selector := unique(defaultGroupProxies)
	auto := unique(defaultGroupAuto)
	fallback := unique(defaultGroupFallback)
	direct := unique(defaultGroupDirect)
	adBlock := unique(defaultGroupAdBlock)
	final := unique(defaultGroupFinal)

	// 节点列表会被多个分组引用，每处都拷一份：这些切片最终会一起进 YAML，
	// 共享底层数组只会在以后某次改动里变成难查的连带 bug。
	allNodes := func() []string {
		return append([]string(nil), names...)
	}
	// 「节点选择」把自动选择与故障转移排在具体节点前面。Clash 的 select 组默认选中
	// 第一项，于是新导入的配置默认就在「自动选择」上 —— 用户不做任何操作也能走最快
	// 的节点，这就是 M2 要的「节点智能默认」，只是先在数据层兑现。
	selectorTargets := append([]string{auto, fallback}, names...)
	selectorTargets = append(selectorTargets, "DIRECT")

	groups := []map[string]any{
		{"name": selector, "type": "select", "proxies": selectorTargets},
		// url-test 的 url / interval / lazy 都不写：内核会补上默认值
		// （constant.DefaultTestURL + interval 300 + lazy true），这样「测速链接」
		// 仍然跟着 App 设置走，也不会在启动瞬间对上百个节点同时发探测。
		{"name": auto, "type": "url-test", "proxies": allNodes(), "tolerance": 50},
		{"name": fallback, "type": "fallback", "proxies": allNodes()},
		{"name": direct, "type": "select", "proxies": []string{"DIRECT", selector}},
		{"name": adBlock, "type": "select", "proxies": []string{"REJECT", "DIRECT"}},
		{"name": final, "type": "select", "proxies": []string{selector, auto, "DIRECT"}},
	}

	rules := []string{
		// 内网直连用 GEOIP,LAN —— 内核在 rules/common/geoip.go 的 NewGEOIP 里对
		// country=="lan" 有专门分支（走 iputil 判断，直接 return，不查 geodata），
		// 所以它在任何 geodata 模式下都成立，也正是各家机场的通行写法。
		// no-resolve：域名连接不该为了判断内网归属先去做一次解析。
		"GEOIP,LAN," + direct + ",no-resolve",
		"GEOSITE,CATEGORY-ADS-ALL," + adBlock,
		// GEOSITE,CN 必须排在 GEOIP,CN 前面。它是域名类规则，命中不需要先解析；
		// 而 fake-ip 模式下 GEOIP,CN 得先 ResolveIP 拿到真 IP 才判断得了
		// （见下面那条的注释），每条新连接都要等一次同步 DNS 解析。
		// 国内域名在这里就被直连掉，才是「打开国内网站不慢」的关键。
		"GEOSITE,CN," + direct,
		// GEOIP,CN 故意不写 no-resolve，这一点违反直觉但很重要：
		// fake-ip 模式下 tunnel.go 的 preHandleMetadata 会把 DstIP 清空、只留 Host，
		// 正因为没有 no-resolve，geoip.go 的 Match 才会先调 helper.ResolveIP()
		// 把真 IP 补回来；一旦加上 no-resolve，它会在 `!ip.IsValid()` 处直接
		// return false —— 这条规则等于彻底失效，国内 IP 流量全部绕去代理。
		// 它也确实是 GEOSITE,CN 没覆盖到的那部分国内地址的最后一道兜底。
		"GEOIP,CN," + direct,
		"MATCH," + final,
	}
	return groups, rules
}
