<div>

[**English**](README.md)

</div>

# BiLoom

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)

基于 ClashMeta 内核的多平台代理客户端，简单易用，完全开源。

> BiLoom 是 [FlClash](https://github.com/chen08209/FlClash) 的 fork，后者以 GPL-3.0 授权。
> 原应用的设计与大部分代码均出自 FlClash 作者，详见[致谢](#致谢)。

<!-- TODO(M2): UI 改造完成后补充 BiLoom 界面截图。 -->

## 功能

✈️ 多平台：当前发布 Android 与 Windows；Linux、macOS 的打包配置保留在仓库中

💻 自适应多种屏幕尺寸，提供多套配色主题

💡 基于 Material You 设计，类 [Surfboard](https://github.com/getsurfboard/surfboard) 界面

🔀 策略组、规则与订阅配置管理，支持 WebDAV 数据同步

📊 流量统计、连接追踪与规则命中查看

🛡️ Android 与 Windows 上的 TUN 模式，由特权助手服务提供支持

🔒 未内置任何分析统计或第三方崩溃上报 SDK

## 下载

构建产物发布在 [Releases](https://github.com/biloom/biloom-app/releases) 页面。

## 使用

### Android

应用响应以下广播 action：

```bash
app.biloom.top.action.START

app.biloom.top.action.STOP

app.biloom.top.action.TOGGLE
```

### 深链

通过链接直接导入订阅配置：

```
biloom://install-config?url=<订阅链接>
```

同时兼容通用的 `clash://` 与 `clashmeta://` 协议。

### Linux

请先安装以下依赖：

```bash
sudo apt-get install libayatana-appindicator3-dev
```

## 构建

1. 安装 **Flutter**、**Go**、**Rust** 工具链。

2. 拉取依赖：

   ```bash
   flutter pub get
   ```

3. 构建 —— Go 内核与 Rust 助手由 setup 构建钩子自动编译：

   ```bash
   dart setup.dart windows
   ```

   其他目标：`android`、`linux`、`macos`。

   各平台前置条件：

   - **Android** —— Android SDK，以及 `android/gradle/libs.versions.toml` 中钉死的 NDK 版本
   - **Windows** —— Visual Studio C++ 生成工具与
     [Inno Setup 6](https://jrsoftware.org/isinfo.php)。若未安装在默认路径，
     请用 `INNO_SETUP_PATH` 指定。

## 致谢

- **[FlClash](https://github.com/chen08209/FlClash)** —— 本项目 fork 的上游应用，GPL-3.0 授权。
- **[Clash.Meta / mihomo](https://github.com/MetaCubeX/mihomo)** —— 驱动隧道的代理内核。

## 许可证

以 [GNU General Public License v3.0](LICENSE) 授权，与上游项目一致。
分发本应用的二进制文件时，您有义务提供对应的源代码。
