package main

import (
	"context"
	"fmt"
	"io"
	"net"
	"net/netip"
	"strings"
	"time"

	"github.com/metacubex/mihomo/component/http"
	"github.com/metacubex/mihomo/component/mmdb"
	"github.com/metacubex/mihomo/constant"
)

// 「测落地」：让一个 HTTP 请求**真的从这个节点走出去**，看它从哪个 IP 出来。
//
// 测延迟（URLTest）只回延迟数、不回内容，外部控制器也没有「经指定节点取回
// 响应」的端点，所以只能加方法。
//
// ## 为什么是「内核本地分类」而不是「回显服务带地理信息」
//
// 第一版让节点去请求 ipwho.is / ip-api.com 这类自带 country 字段的回显服务，
// 由 Dart 解析 JSON。但 ip-api 免费版按出口 IP 限流 45 req/min —— 同一节点上
// 的所有用户共享额度，把「测落地」自动化挂到测延迟节奏上的那一刻就会撞墙。
//
// 现在的形态：节点只访问**只回一个 IP 字符串**的极轻回显服务（api.ipify.org，
// 响应就十几个字节，没有配额概念），拿到出口 IP 后在内核**本地**查随包发布的
// geoip.metadb 定国家 —— 与规则分流 GEOIP 用的同一份数据、同一条 LookupCode
// 通路。地理查询零外部依赖、零限流，「自动测落地」才立得住。
//
// params/result 的结构定义在 constant.go，与其余方法入参放在一起。

// proxyIPDialer 把 component/http 的 `DialContext(network, address)` 翻译成
// 代理适配器的 `DialContext(metadata)` —— 与 URLTest 走同一条拨号路，因此对
// 链式代理（dialer-proxy）和策略组（拨给当前选中节点）的行为一致。每次连接
// 独立拨号，不复用连接，省掉 URLTest 那套「单连接塞给 Transport」的小心翼翼。
type proxyIPDialer struct {
	proxy constant.Proxy
}

func (d proxyIPDialer) DialContext(
	ctx context.Context,
	network string,
	address string,
) (net.Conn, error) {
	metadata := constant.Metadata{}
	if err := metadata.SetRemoteAddress(address); err != nil {
		return nil, err
	}
	metadata.NetWork = constant.TCP
	return d.proxy.DialContext(ctx, &metadata)
}

func (d proxyIPDialer) ListenPacket(
	ctx context.Context,
	network string,
	address string,
	_ netip.AddrPort,
) (net.PacketConn, error) {
	// IP 回显是纯 HTTP，只会走 TCP；constant.Proxy 包装器也没把 UDP 出口
	// 露出来。这里宁可明确拒绝，也不把「不该发生」变成「静默走错路」。
	return nil, fmt.Errorf("udp is not supported for proxy ip probe")
}

// 64 KiB 的响应体上限足够任何 IP 回显服务；LimitReader 在这里兜底，防止把
// 一个不受信服务的大响应整段搬过管道。
const requestProxyIPMaxBodyBytes = 64 << 10

const requestProxyIPDefaultTimeout = 10 * time.Second

// 回显服务按序尝试，两个都走 https：明文 http 的响应内容能被出口路径上的
// 任何一跳改写 —— 回显服务是「出口 IP」这个事实的唯一来源，让它可被篡改
// 等于把落地判定交给中间人。两个故意选不同域名，免得单一服务商抽风时
// 全体节点集体测不出；https 多一次握手对极轻回显可忽略。
var requestProxyIPEchoUrls = []string{
	"https://api.ipify.org",
	"https://ifconfig.me/ip",
}

// fetchExitIP 经指定节点把 GET 发出去，拿回出口 IP。
func fetchExitIP(
	ctx context.Context,
	proxy constant.Proxy,
	url string,
) (netip.Addr, error) {
	resp, err := http.HttpRequest(
		ctx,
		url,
		"GET",
		nil,
		nil,
		http.WithDialer(proxyIPDialer{proxy: proxy}),
	)
	if err != nil {
		return netip.Addr{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return netip.Addr{}, fmt.Errorf("http status %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, requestProxyIPMaxBodyBytes))
	if err != nil {
		return netip.Addr{}, err
	}
	addr, err := netip.ParseAddr(strings.TrimSpace(string(body)))
	if err != nil {
		return netip.Addr{}, fmt.Errorf("echo service returned %q: %w", body, err)
	}
	return addr, nil
}

// lookupExitCountry 用随包发布的 geoip 数据本地查国家码。与规则分流
// （rules/common/geoip.go）走同一个 mmdb 单例 —— 数据一致，也不多耗内存。
//
// 先 Verify 再 IPInstance 不是多余：IPInstance 在 MMDB 文件缺失时会
// log.Fatalln 直接把内核带走，而「用户手滑删了数据库文件」不该表现为
// 「整个梯子崩了」。Verify 打不开文件就返回一个普通错误，探测失败而已。
func lookupExitCountry(addr netip.Addr) (string, error) {
	if !mmdb.Verify(constant.Path.MMDB()) {
		return "", fmt.Errorf("geoip database not ready")
	}
	for _, code := range mmdb.IPInstance().LookupCode(addr.AsSlice()) {
		if code != "" {
			return code, nil
		}
	}
	return "", nil
}

func handleRequestProxyIP(params *RequestProxyIPParams) (*RequestProxyIPResult, error) {
	if params.Name == "" {
		return nil, fmt.Errorf("missing proxy name")
	}
	proxy := lookupProxy(params.Name)
	if proxy == nil {
		return nil, fmt.Errorf("proxy %s not found", params.Name)
	}
	timeout := time.Duration(params.Timeout) * time.Millisecond
	if timeout <= 0 {
		timeout = requestProxyIPDefaultTimeout
	}

	// params.Url 保留为「外部指定回显地址」的口子（Dart 侧现在不传，走默认链）。
	urls := requestProxyIPEchoUrls
	if params.Url != "" {
		urls = []string{params.Url}
	}

	var lastErr error
	for _, url := range urls {
		ctx, cancel := context.WithTimeout(context.Background(), timeout)
		addr, err := fetchExitIP(ctx, proxy, url)
		cancel()
		if err != nil {
			lastErr = err
			continue
		}
		country, err := lookupExitCountry(addr)
		if err != nil {
			return nil, err
		}
		return &RequestProxyIPResult{IP: addr.String(), Country: country}, nil
	}
	if lastErr == nil {
		lastErr = fmt.Errorf("no echo url attempted")
	}
	return nil, lastErr
}
