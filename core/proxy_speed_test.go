package main

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/constant"
)

// 下载测速的离线集成测试：httptest 本地服务器（127.0.0.1，不碰真网络）+
// DIRECT 适配器，把 downloadThrough 的拨号路、读取循环、截断与失败语义
// 全部过一遍。速度上限（speedTestSlots）在 handleMeasureSpeed 一层，不在此测。

func directProxy() constant.Proxy {
	return adapter.NewProxy(outbound.NewDirectWithOption(outbound.DirectOption{
		Name: "speed-test-direct",
	}))
}

// serveBytes 起一个回 N 字节响应体的测试服务器，返回地址与清理函数。
func serveBytes(t *testing.T, status int, payload []byte, slow time.Duration) (string, func()) {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/octet-stream")
		w.WriteHeader(status)
		chunk := make([]byte, 32<<10)
		sent := 0
		for sent < len(payload) {
			if slow > 0 {
				time.Sleep(slow)
			}
			n := copy(chunk, payload[sent:])
			if _, err := w.Write(chunk[:n]); err != nil {
				return
			}
			sent += n
			if f, ok := w.(http.Flusher); ok {
				f.Flush()
			}
		}
	}))
	return srv.URL, srv.Close
}

func TestDownloadThroughNormal(t *testing.T) {
	payload := make([]byte, 1<<20) // 1 MiB
	url, closeSrv := serveBytes(t, http.StatusOK, payload, 0)
	defer closeSrv()
	result, err := downloadThrough(context.Background(), directProxy(), url, speedTestDefaultMaxBytes)
	if err != nil {
		t.Fatalf("downloadThrough: %v", err)
	}
	if result.Bytes != int64(len(payload)) {
		t.Fatalf("bytes = %d, want %d", result.Bytes, len(payload))
	}
	if result.SpeedBps <= 0 {
		t.Fatalf("speed = %v, want > 0", result.SpeedBps)
	}
	if result.ElapsedMs < 0 {
		t.Fatalf("elapsed = %v, want >= 0", result.ElapsedMs)
	}
}

func TestDownloadThroughTruncatesToMaxBytes(t *testing.T) {
	payload := make([]byte, 2<<20) // 2 MiB，上限 1 MiB
	url, closeSrv := serveBytes(t, http.StatusOK, payload, 0)
	defer closeSrv()
	result, err := downloadThrough(context.Background(), directProxy(), url, 1<<20)
	if err != nil {
		t.Fatalf("downloadThrough: %v", err)
	}
	if result.Bytes != 1<<20 {
		t.Fatalf("bytes = %d, want %d", result.Bytes, 1<<20)
	}
}

// 预算耗尽只拉到部分数据 ≠ 失败：部分吞吐也是有效观测。
func TestDownloadThroughPartialOnTimeout(t *testing.T) {
	payload := make([]byte, 8<<20) // 8 MiB，短超时只能拉到一部分
	url, closeSrv := serveBytes(t, http.StatusOK, payload, 30*time.Millisecond)
	defer closeSrv()
	ctx, cancel := context.WithTimeout(context.Background(), 400*time.Millisecond)
	defer cancel()
	result, err := downloadThrough(ctx, directProxy(), url, speedTestDefaultMaxBytes)
	if err != nil {
		t.Fatalf("partial download should not fail, got: %v", err)
	}
	if result.Bytes == 0 {
		t.Fatal("partial download returned zero bytes")
	}
	if result.Bytes >= int64(len(payload)) {
		t.Fatal("expected a truncated download")
	}
}

func TestDownloadThroughErrorStatus(t *testing.T) {
	url, closeSrv := serveBytes(t, http.StatusForbidden, []byte("forbidden"), 0)
	defer closeSrv()
	_, err := downloadThrough(context.Background(), directProxy(), url, speedTestDefaultMaxBytes)
	if err == nil || !strings.Contains(err.Error(), "http status 403") {
		t.Fatalf("want http status error, got: %v", err)
	}
}

// 一个字节都没下到 + 连接中断 = 失败（与「部分下载」区分开）。
func TestDownloadThroughNoDataFails(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// 触发连接在响应头后立刻断开：Hijack 后直接关连接。
		hj, ok := w.(http.Hijacker)
		if !ok {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		conn, _, _ := hj.Hijack()
		if conn != nil {
			fmt.Fprint(conn, "HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n")
			_ = conn.Close()
		}
	}))
	defer srv.Close()
	_, err := downloadThrough(context.Background(), directProxy(), srv.URL, speedTestDefaultMaxBytes)
	if err == nil {
		t.Fatal("zero-byte download should fail")
	}
}

// 上下文取消同样属于「部分数据有效」的路径 —— 与超时共用同一个 break。
func TestDownloadThroughContextCancelPartial(t *testing.T) {
	payload := make([]byte, 8<<20)
	url, closeSrv := serveBytes(t, http.StatusOK, payload, 30*time.Millisecond)
	defer closeSrv()
	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		time.Sleep(250 * time.Millisecond)
		cancel()
	}()
	result, err := downloadThrough(ctx, directProxy(), url, speedTestDefaultMaxBytes)
	if err != nil {
		t.Fatalf("cancelled partial download should not fail, got: %v", err)
	}
	if result.Bytes == 0 {
		t.Fatal("cancelled partial download returned zero bytes")
	}
}

// io.EOF 正常收尾（server 关流）不应被当成错误 —— 放在最末作为语义锚点。
func TestDownloadThroughEOFIsNormalEnd(t *testing.T) {
	body := io.NopCloser(strings.NewReader("hello speed test"))
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("hello speed test"))
	}))
	defer srv.Close()
	_ = body
	result, err := downloadThrough(context.Background(), directProxy(), srv.URL, speedTestDefaultMaxBytes)
	if err != nil {
		t.Fatalf("downloadThrough: %v", err)
	}
	if result.Bytes != int64(len("hello speed test")) {
		t.Fatalf("bytes = %d", result.Bytes)
	}
}
