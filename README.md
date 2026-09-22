<div>

[**简体中文**](README_zh_CN.md)

</div>

# BiLoom

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)

A multi-platform proxy client built on the ClashMeta core — simple, easy to use
and fully open source.

> BiLoom is a fork of [FlClash](https://github.com/chen08209/FlClash), which is
> licensed under GPL-3.0. The original application, its design and the bulk of
> this codebase are the work of the FlClash authors — see [Credits](#credits).

<!-- TODO(M2): add BiLoom screenshots once the UI refresh lands. -->

## Features

✈️ Multi-platform: Android and Windows ship today; Linux and macOS packaging
stays in-tree so the fork keeps building everywhere

💻 Adaptive layout across screen sizes, with multiple colour themes

💡 Built on Material You design, with a [Surfboard](https://github.com/getsurfboard/surfboard)-like UI

🔀 Proxy groups, rules and subscription profiles, with WebDAV data sync

📊 Traffic statistics, connection tracking and rule-match inspection

🛡️ TUN mode on Android and Windows through a privileged helper service

🔒 No analytics or crash-reporting SDK is bundled

## Download

Builds are published on the [Releases](https://github.com/biloom/biloom-app/releases) page.

## Use

### Android

The app responds to the following broadcast actions:

```bash
app.biloom.top.action.START

app.biloom.top.action.STOP

app.biloom.top.action.TOGGLE
```

### Deep links

Import a subscription profile straight from a link:

```
biloom://install-config?url=<subscription-url>
```

The generic `clash://` and `clashmeta://` schemes are accepted as well.

### Linux

Make sure the following dependency is installed:

```bash
sudo apt-get install libayatana-appindicator3-dev
```

## Build

1. Install the **Flutter**, **Go** and **Rust** toolchains.

2. Fetch dependencies:

   ```bash
   flutter pub get
   ```

3. Build — the Go core and the Rust helper are compiled automatically by the
   setup build hook:

   ```bash
   dart setup.dart windows
   ```

   Other targets: `android`, `linux`, `macos`.

   Platform prerequisites:

   - **Android** — Android SDK plus the NDK version pinned in
     `android/gradle/libs.versions.toml`
   - **Windows** — Visual Studio C++ build tools and
     [Inno Setup 6](https://jrsoftware.org/isinfo.php). If Inno Setup is not in
     its default location, point `INNO_SETUP_PATH` at it.

## Credits

- **[FlClash](https://github.com/chen08209/FlClash)** — the upstream application
  this project is forked from. Licensed under GPL-3.0.
- **[Clash.Meta / mihomo](https://github.com/MetaCubeX/mihomo)** — the proxy core
  that powers the tunnel.

## License

Licensed under the [GNU General Public License v3.0](LICENSE), the same licence
as the upstream project. Distributing binaries of this application obliges you
to make the corresponding source code available.
