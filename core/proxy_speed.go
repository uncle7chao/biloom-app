package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"time"

	"github.com/metacubex/mihomo/component/http"
	"github.com/metacubex/mihomo/constant"
)

// 「下载测速」：经指定节点真的下一个样本文件，量出响应体阶段的吞吐。
//
// 测延迟（URLTest）量的是首字节往返，回答「通不通、快不快响应」；但节点
// 真正的带宽只有把一段体量拉下来才知道 —— 1ms 的 ping 完全可以配 50 KB/s
// 的真实吞吐。与「测落地」（proxy_ip.go）同一个问题域：外部控制器没有
// 「经指定节点传输数据」的端点，所以只能加方法。
//
// ## 为什么计时只覆盖响应体阶段
//
// 拨号 + TLS 握手 + 首字节那几秒是「延迟」，URLTest 已经量过了。远端节点
// （美西动辄 200ms+）把这 200ms 混进一个 5 秒的下载窗口，带宽会被系统性
// 拉低 4%+，小文件场景更糟。所以时钟在响应头到手后才起 —— 我们要的是
// 纯吞吐，不是 TTFB 的杂音。
//
// ## 为什么默认 Cloudflare 的 speed 端点
//
// `https://speed.cloudflare.com/__down?bytes=N` 按参数精确回 N 字节，全球
// Anycast 无配额概念，且 https —— 响应内容可被出口路径篡改的场景下，测速
// 结果最多被骗「虚高」（对端少发字节）或「虚低」，不会像明文 http 那样被
// 中间人整段替换。bytes 给 10 MiB：既能让常见 10~100 MB/s 的节点跑出稳定
// 读数，又把单节点流量压在一次测速 ≈ 十几 MB 的量级。
//
// params/result 的结构定义在 constant.go，与其余方法入参放在一起。

const speedTestDefaultTimeout = 20 * time.Second

// 单节点单次下载的字节数上限：兜的是「外部指定了一个不受控大文件地址」的
// 场景 —— 默认地址自身只回 10 MiB，远够不到这个盖子。
const speedTestDefaultMaxBytes = 16 << 20

const speedTestDefaultURL = "https://speed.cloudflare.com/__down?bytes=10485760"

// 并发槽：4 路。测速和测落地不同 —— 它是**真带宽**消耗，16 路并发会把
// 出口带宽全部挤给自己的测速流量（用户当下的连接被活活挤死）。4 路既能
// 饱和一条百兆级线路，又给正常流量留了活口。Dart 侧 TaskPool 同为 4，
// 两侧一致，Dart 不会白排长队。
var speedTestSlots = make(chan struct{}, 4)

func handleMeasureSpeed(params *MeasureSpeedParams) (*MeasureSpeedResult, error) {
	if params.Name == "" {
		return nil, fmt.Errorf("missing proxy name")
	}
	proxy := lookupProxy(params.Name)
	if proxy == nil {
		return nil, fmt.Errorf("proxy %s not found", params.Name)
	}
	timeout := time.Duration(params.Timeout) * time.Millisecond
	if timeout <= 0 {
		timeout = speedTestDefaultTimeout
	}
	maxBytes := params.MaxBytes
	if maxBytes <= 0 {
		maxBytes = speedTestDefaultMaxBytes
	}
	// params.Url 保留为「外部指定样本文件地址」的口子（Dart 侧现在不传，
	// 走默认链）。
	url := params.Url
	if url == "" {
		url = speedTestDefaultURL
	}

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	// 排队拿并发槽，且**计入总预算**：批量测速时后到的节点要等前头的下完
	// 才轮得到自己，这段等待是真实存在的耗时，不该叠加在预算之外。
	select {
	case speedTestSlots <- struct{}{}:
		defer func() { <-speedTestSlots }()
	case <-ctx.Done():
		return nil, fmt.Errorf("speed test queue timeout")
	}

	return downloadThrough(ctx, proxy, url, maxBytes)
}

// downloadThrough 经 proxy 把样本文件拉下来并计时 —— 从 handleMeasureSpeed
// 拆出来是为了能对本地 httptest 服务器做纯离线测试（不碰真网络）。
func downloadThrough(
	ctx context.Context,
	proxy constant.Proxy,
	url string,
	maxBytes int64,
) (*MeasureSpeedResult, error) {
	// 与测延迟、测落地同一条拨号路：proxy.DialContext(metadata)，对链式代理
	// （dialer-proxy）和策略组（拨给当前选中节点）的行为一致。
	resp, err := http.HttpRequest(
		ctx,
		url,
		"GET",
		nil,
		nil,
		http.WithDialer(proxyIPDialer{proxy: proxy}),
	)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return nil, fmt.Errorf("http status %d", resp.StatusCode)
	}

	start := time.Now()
	buf := make([]byte, 32<<10)
	var total int64
	var readErr error
	for total < maxBytes {
		if ctx.Err() != nil {
			break
		}
		n, err := resp.Body.Read(buf)
		total += int64(n)
		if err != nil {
			readErr = err
			break
		}
	}
	elapsed := time.Since(start)

	// 一个字节都没下到才算失败。预算耗尽只拉到部分数据 ≠ 失败 —— 部分吞吐
	// 也是有效观测（「这个节点实测 300 KB/s」比「超时」有用得多）。
	if total == 0 {
		if readErr != nil && !errors.Is(readErr, io.EOF) {
			return nil, readErr
		}
		if ctx.Err() != nil {
			return nil, fmt.Errorf("speed test timeout with no data")
		}
		return nil, fmt.Errorf("no data received")
	}
	return &MeasureSpeedResult{
		Bytes:     total,
		ElapsedMs: elapsed.Milliseconds(),
		SpeedBps:  float64(total) / elapsed.Seconds(),
	}, nil
}
