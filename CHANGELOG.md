# Changelog

## v01.00.27 (2026-09-29)

**Features**

- **backup** Backup and sync parity: proxy chains and favorite stars are now part of every backup and come back on a full restore, profiles can be backed up automatically on add/remove with a rolling local history (the remote WebDAV copy is never overwritten), and a backup zip can be shared to another device over the LAN via a QR code or a plain address (0ec7072)
- **Android** AdMob banner integration: the application ID ships in the manifest, the home shell mounts the banner slot, and placement/switch decisions stay in the remote config - plus the build-time NDK clang lookup works on Windows hosts and the stray background-location permission is stripped (88a5b3d)

**Bug Fixes**

- **core** The injected default rules no longer carry an ad-block rule: GEOSITE CATEGORY-ADS-ALL previously routed AdMob, googlesyndication and doubleclick into a hidden REJECT group, so AdMob itself was unreachable while connected - a regression test now forbids ad-block rules in defaults (9fddbe7)
- **scan** Scanning a QR code now returns any non-empty content: custom-scheme share links decoded as plain text used to close the scanner with no result (569b0ce)

## v01.00.26 (2026-09-29)

**Bug Fixes**

- **proxies** The selected node shows a check mark at the top-right corner of its card in every group (select groups previously only changed the card background, which is invisible on dark themes), and the proxy-chain tab now mirrors the selection that actually takes effect - the chain is highlighted and marked only while the node-selection group (rule mode) or GLOBAL (global mode) points at it, and tapping a chain there switches the real exit instead of writing a no-op selection (95b62b3)

## v01.00.25 (2026-09-28)

**Features**

- **proxies** Proxy chains are now selectable directly in the node-selection group and in GLOBAL, so exactly one choice is active at a time in either mode: picking a chain routes traffic through it, picking a plain node bypasses it, and the chain tab stays as the management panel (0875096)

## v01.00.24 (2026-09-28)

**Features**

- **settings** Settings sections are now grouped into rounded cards across all settings pages (basic/network/dns config, access, about, dns leak, proxies settings and quick options) instead of flat dividers (34b9b9a)
- **dashboard** Connected state on the home hero card gains a subtle primary gradient; subscription cards color the traffic bar amber at 75% and red at 90% usage and fall back to a short expiry date on narrow cards (b1cb28c)

## v01.00.23 (2026-09-28)

**Features**

- **connections** Connections page structured filters: filter the live list by process, node or rule via dropdown chips, close every filtered connection at once, and see process and rule directly on each row instead of inside the details sheet (process values require find-process-mode=always) (60eff6c)

## v01.00.22 (2026-09-28)

**Features**

- **dashboard** New Connections stat widget: active connection count, cumulative upload/download traffic and the top traffic target host; add it from the dashboard edit mode - it is not in the default layout and shows silent zeros while the core is down (36922af)
- **proxies** Group tabs use a filled pill indicator matching the region filter chips instead of the underline, and the selected node card draws a thin primary border so the active node is easy to spot (f2bc169)
- **proxies** Per-node download speed test: the button next to the delay test pulls a sample file through that node and shows the real bandwidth (transfer time only, color-graded like the delay readout); results are session-scoped and favorite stars now show in amber (589254e)

## v01.00.21 (2026-09-28)

**Features**

- **ads** Remote ads config framework: a static JSON on biloom.top is fetched on startup within a 12h freshness window and cached; any network or parse failure keeps the previous state, so ads can never disturb the main flow (3721643)
- **Windows** New Activities page: an embedded WebView loading our own promo page on biloom.top, with an open-in-browser button handing monetization to the real browser; the entry only appears when the remote config carries a valid promo URL and can be turned off remotely without rebuilding (baa8a44)

## v01.00.20 (2026-09-27)

**Bug Fixes**

- **proxies** Group tabs list nodes only now: the auto-select and fallback groups plus DIRECT no longer appear as cards mixed into the node list (they remain selectable at the config level and the GLOBAL tab keeps its own behavior) (283ee3a)

## v01.00.19 (2026-09-27)

**Bug Fixes**

- **core** Nodes referenced by dialer-proxy (the front nodes injected for proxy chains) are no longer healed into the selector groups on every config load, so the proxy page no longer shows nodes from other subscriptions under the node-selection and auto-select tabs (ace752f)

## v01.00.18 (2026-09-27)

**Features**

- **proxies** Proxy chains are now a global index instead of belonging to the profile they were created in: the chain tab is always present in every profile (with a DIRECT placeholder when empty), every chain shows up and works under every profile, numbering is global, and chain creation/deletion no longer depends on which profile the panel was opened from (94efe51)

## v01.00.17 (2026-09-26)

**Bug Fixes**

- **proxies** The GLOBAL tab now lists only nodes - strategy groups no longer appear as cards in it, and chain-proxy nodes plus their injected front nodes stay in the chain tab; the chain dialer picker labels its sections with 策略组/节点 suffixes (49d2278)
- **core** Xray outbounds with multiple server entries now import every server instead of silently keeping only the first one (edbf916)
- **proxies** Chain injection hardening: residue rules with trailing params (no-resolve/src) and sub-rules are now cleaned too; group dialers are validated against the groups that survive custom-overwrite replacement; previewing another profile no longer pollutes the GLOBAL display filter; the node form keeps reality-opts when editing subscription Reality nodes, requires a vless public key, and no longer crashes on dropdown values outside the option list; fingerprint rotation no longer stalls permanently on stale records (7be6630)
- **core** Kernel cleanups: both exit-IP echo urls now use https so the result cannot be rewritten in plaintext; auto-generated node names skip suffixes genuinely taken in the same batch; removing nodes also honors the src trailing rule param; the never-called copyProxyNode / addProxyChain methods are gone (8735298)
- **proxies** P2 backlog: landing batch no longer re-probes everything after a cold start and cannot run concurrently with itself; manual landing probes persist like batch ones; pending landing writes are flushed on exit; the method timeout covers the kernel two-echo worst case; the chain-proxy name is fixed at the config layer so switching UI language no longer renumbers chains; residue cleanup no longer touches user nodes that merely share the name; fingerprint writes are serialized; the region whitelist now covers 74 more real landing codes (3118ffe)

## v01.00.16 (2026-09-26)

**Features**

- **proxies** Stop injecting the chain-proxy tab when there are no valid chains, so the empty untouchable tab disappears; stale leftovers from older models (链式代理 / 链式代理N / 链式代理-N) are still cleared before injecting, so a residue never forces a duplicate "-2" tab (5bb737a)
- **ui** The chain picker shows each section's profile name as a bold accent title, so it is clear which profile a node belongs to (5bb737a)

**Bug Fixes**

- **proxies** Creating the first proxy chain always failed with "Cannot add to an unmodifiable list" - the chain store appended to a const list decoded from empty storage; also the chain picker sections are now collapsible via tappable headers (item count + rotating chevron), and search ignores collapse state (87b7351)

<!-- changelog:frozen -->
<!-- Entries below predate the structured pipeline. Their wording is kept as written; only the heading and list style were normalized. -->

## v0.8.98 (2026-09-14)

**Bug Fixes**

- **resources** Refresh the geo file size and time after an update finishes (c5bf5bd)
- **core** Keep the core running while Windows sleeps with the app suspended (60f371a)

## v0.8.97 (2026-09-10)

**Features**

- **ui** Rework the app UI and refresh the localization (26cfbaf)
- **app** Rework the app layer and window handling, and add proxy authentication (aaf934c)
- **desktop** Rework the desktop runners, packaging, and native build (c0fcbc0)
- **android** Rework the Android VPN service and lifecycle handling (ae29f38)
- **plugins** Rework the desktop plugins and add the Helper service and Rust bridge (adf715f)
- **core** Rework the core IPC and process lifecycle (c6eaa0a)

## v0.8.96 (2026-08-17)

- Optimize commented policy
- Fix whole group delay test failing on Windows
- Optimize package icon loading and connections polling

## v0.8.95 (2026-08-14)

- Optimize core service
- Optimize Android TV launcher icon
- Optimize back navigation
- Optimize more details
- Fix some issues
- Optimize app layout
- Optimize focus control
- Adjust android process

## v0.8.94 (2026-07-11)

- Fix macos performance issue
- Support custom global-ua
- Update core
- Optimize some details
- Fix linux silent launching not working

## v0.8.93 (2026-05-29)

- Support custom overwrite
- Support run on demand
- Optimize windows ipc
- Optimize windows arm64
- Optimize build
- Optimize some details
- Update core

## v0.8.92 (2026-02-02)

- Add sqlite store
- Optimize android quick action
- Optimize backup and restore
- Optimize more details

## v0.8.91 (2025-12-12)

- Fix windows some issues
- Optimize overwrite handle
- Optimize access control page
- Optimize some details

## v0.8.90 (2025-10-08)

- Fix android tile service
- Support append system DNS
- Fix some issues
- Update changelog

## v0.8.89 (2025-09-27)

- Fix some issues
- Optimize Windows service mode
- Update core
- Update changelog

## v0.8.88 (2025-09-23)

- Add android separates the core process
- Support core status check and force restart
- Optimize proxies page and access page
- Update flutter and pub dependencies
- Update go version
- Optimize more details
- Update changelog

## v0.8.87 (2025-07-29)

- Optimize desktop view
- Optimize logs, requests, connection pages
- Optimize windows tray auto hide
- Optimize some details
- Update core
- Update changelog

## v0.8.86 (2025-06-15)

- Fix windows tun issues
- Optimize android get system dns
- Optimize more details
- Update changelog

## v0.8.85 (2025-06-07)

- Support override script
- Support proxies search
- Support svg display
- Optimize config persistence
- Add some scenes auto close connections
- Update core
- Optimize more details

## v0.8.84 (2025-05-01)

- Fix windows service verify issues
- Update changelog

## v0.8.83 (2025-05-01)

- Add windows server mode start process verify
- Add linux deb dependencies
- Add backup recovery strategy select
- Support custom text scaling
- Optimize the display of different text scale
- Optimize windows setup experience
- Optimize startTun performance
- Optimize android tv experience
- Optimize default option
- Optimize computed text size
- Optimize hyperOS freeform window
- Add developer mode
- Update core
- Optimize more details
- Add issues template
- Update changelog

## v0.8.82 (2025-04-18)

- Optimize android vpn performance
- Add custom primary color and color scheme
- Add linux nad windows arm release
- Optimize requests and logs page
- Fix map input page delete issues
- Update changelog

## v0.8.81 (2025-04-08)

- Add rule override
- Update core
- Optimize more details
- Update changelog

## v0.8.80 (2025-03-10)

- Optimize dashboard performance
- Fix some issues
- Fix unselected proxy group delay issues
- Fix asn url issues
- Update changelog

## v0.8.79 (2025-03-07)

- Fix tab delay view issues
- Fix tray action issues
- Fix get profile redirect client ua issues
- Fix proxy card delay view issues
- Add Russian, Japanese adaptation
- Fix some issues
- Update changelog

## v0.8.78 (2025-03-05)

- Fix list form input view issues
- Fix traffic view issues
- Update changelog

## v0.8.77 (2025-03-05)

- Optimize performance
- Update core
- Optimize core stability
- Fix linux tun authority check error
- Fix some issues
- Fix scroll physics error
- Update changelog

## v0.8.75 (2025-02-09)

- Add windows storage corruption detection
- Fix core crash caused by windows resource manager restart
- Optimize logs, requests, access to pages
- Fix macos bypass domain issues
- Update changelog

## v0.8.74 (2025-02-03)

- Fix some issues
- Update changelog

## v0.8.73 (2025-02-02)

- Update popup menu
- Add file editor
- Fix android service issues
- Optimize desktop background performance
- Optimize android main process performance
- Optimize delay test
- Optimize vpn protect
- Update changelog

## v0.8.72 (2025-01-10)

- Update core
- Fix some issues
- Update changelog

## v0.8.71 (2025-01-09)

- Remake dashboard
- Optimize theme
- Optimize more details
- Update flutter version
- Update changelog

## v0.8.70 (2024-12-09)

- Support better window position memory
- Add windows arm64 and linux arm64 build script
- Optimize some details

## v0.8.69 (2024-12-06)

- Remake desktop
- Optimize change proxy
- Optimize network check
- Fix fallback issues
- Optimize lots of details
- Update change.yaml
- Fix android tile issues
- Fix windows tray issues
- Support setting bypassDomain
- Update flutter version
- Fix android service issues
- Fix macos dock exit button issues
- Add route address setting
- Optimize provider view
- Update changelog
- Update CHANGELOG.md

## v0.8.67 (2024-11-09)

- Add android shortcuts
- Fix init params issues
- Fix dynamic color issues
- Optimize navigator animate
- Optimize window init
- Optimize fab
- Optimize save

## v0.8.66 (2024-10-26)

- Fix the collapse issues
- Add fontFamily options

## v0.8.65 (2024-10-26)

- Update core version
- Update flutter version
- Optimize ip check
- Optimize url-test

## v0.8.64 (2024-10-12)

- Update release message
- Init auto gen changelog
- Fix windows tray issues
- Fix urltest issues
- Add auto changelog
- Fix windows admin auto launch issues
- Add android vpn options
- Support proxies icon configuration
- Optimize android immersion display
- Fix some issues
- Optimize ip detection
- Support android vpn ipv6 inbound switch
- Support log export
- Optimize more details
- Fix android system dns issues
- Optimize dns default option
- Fix some issues
- Update readme

## v0.8.60 (2024-09-17)

- Fix build error2
- Fix build error
- Support desktop hotkey
- Support android ipv6 inbound
- Support android system dns
- fix some bugs

## v0.8.59 (2024-09-09)

- Fix delete profile error

## v0.8.58 (2024-09-08)

- Fix submit error 2
- Fix submit error
- Optimize DNS strategy
- Fix the problem that the tray is not displayed in some cases
- Optimize tray
- Update core
- Fix some error

## v0.8.57 (2024-09-02)

- Fix tun update issues
- Add DNS override
- Fixed some bugs
- Optimize more detail
- Add Hosts override

## v0.8.56 (2024-08-26)

- fix android tip error
- fix windows auto launch error

## v0.8.55 (2024-08-25)

- Fix windows tray issues
- Optimize windows logic
- Optimize app logic
- Support windows administrator auto launch
- Support android close vpn

## v0.8.53 (2024-08-15)

- Change flutter version
- Support profiles sort
- Support windows country flags display
- Optimize proxies page and profiles page columns

## v0.8.52 (2024-08-11)

- Update flutter version
- Update version
- Update timeout time
- Update access control page
- Fix bug

## v0.8.51 (2024-08-05)

- Optimize provider page
- Optimize delay test
- Support local backup and recovery
- Fix android tile service issues

## v0.8.49 (2024-07-31)

- Fix linux core build error
- Add proxy-only traffic statistics
- Update core
- Optimize more details
- Merge pull request #140 from txyyh/main
- 添加自建 F-Droid 仓库相关 workflow
- Rename readme fingerprint
- Rename workflow deploy repo name
- Add download guide to README
- Add push release files to fdroid-repo

## v0.8.48 (2024-07-25)

- Optimize proxies page
- Fix ua issues
- Optimize more details

## v0.8.47 (2024-07-22)

- Fix windows build error

## v0.8.46 (2024-07-22)

- Update app icon
- Fix desktop backup error
- Optimize request ua
- Change android icon
- Optimize dashboard

## v0.8.44 (2024-07-18)

- Remove request validate certificate
- Sync core

## v0.8.43 (2024-07-18)

- Fix windows error

## v0.8.42 (2024-07-18)

- Fix setup.dart error
- Fix android system proxy not effective
- Add macos arm64

## v0.8.41 (2024-07-17)

- Optimize proxies page
- Support mouse drag scroll
- Adjust desktop ui
- Revert "Fix android vpn issues"
- This reverts commit 891977408e6938e2acd74e9b9adb959c48c79988.

## v0.8.40 (2024-07-15)

- Fix android vpn issues
- Fix android vpn issues
- Rollback partial modification

## v0.8.39 (2024-07-15)

- Fix the problem that ui can't be synchronized when android vpn is occupied by an external
- Override default socksPort,port

## v0.8.38 (2024-07-14)

- Fix fab issues

## v0.8.37 (2024-07-14)

- Update version
- Fix the problem that vpn cannot be started in some cases
- Fix the problem that geodata url does not take effect

## v0.8.36 (2024-07-13)

- Update ua
- Fix change outbound mode without check ip issues
- Separate android ui and vpn
- Fix url validate issues 2
- Add android hidden from the recent task
- Add geoip file
- Support modify geoData URL

## v0.8.35 (2024-07-07)

- Fix url validate issues
- Fix check ip performance problem
- Optimize resources page

## v0.8.34 (2024-07-04)

- Add ua selector
- Support modify test url
- Optimize android proxy
- Fix the error that async proxy provider could not selected the proxy

## v0.8.33 (2024-07-01)

- Fix android proxy error
- Fix submit error
- Add windows tun
- Optimize android proxy
- Optimize change profile
- Update application ua
- Optimize delay test

## v0.8.32 (2024-06-28)

- Fix android repeated request notification issues

## v0.8.31 (2024-06-28)

- Fix memory overflow issues

## v0.8.30 (2024-06-27)

- Optimize proxies expansion panel 2
- Fix android scan qrcode error

## v0.8.29 (2024-06-27)

- Optimize proxies expansion panel
- Fix text error

## v0.8.28 (2024-06-26)

- Optimize proxy
- Optimize delayed sorting performance
- Add expansion panel proxies page
- Support to adjust the proxy card size
- Support to adjust proxies columns number
- Fix autoRun show issues
- Fix Android 10 issues
- Optimize ip show

## v0.8.26 (2024-06-22)

- Add intranet IP display
- Add connections page
- Add search in connections, requests
- Add keyword search in connections, requests, logs
- Add basic viewing editing capabilities
- Optimize update profile

## v0.8.25 (2024-06-19)

- Update version
- Fix the problem of excessive memory usage in traffic usage.
- Add lightBlue theme color
- Fix start unable to update profile issues
- Fix flashback caused by process

## v0.8.23 (2024-06-16)

- Add build version
- Optimize quick start
- Update system default option

## v0.8.22 (2024-06-16)

- Update build.yml
- Fix android vpn close issues
- Add requests page
- Fix checkUpdate dark mode style error
- Fix quickStart error open app
- Add memory proxies tab index
- Support hidden group
- Optimize logs
- Fix externalController hot load error

## v0.8.21 (2024-06-13)

- Add tcp concurrent switch
- Add system proxy switch
- Add geodata loader switch
- Add external controller switch
- Add auto gc on trim memory
- Fix android notification error

## v0.8.20 (2024-06-12)

- Fix ipv6 error
- Fix android udp direct error
- Add ipv6 switch
- Add access all selected button
- Remove android low version splash

## v0.8.19 (2024-06-10)

- Update version
- Add allowBypass
- Fix Android only pick .text file issues

## v0.8.18 (2024-06-09)

- Fix search issues

## v0.8.17 (2024-06-09)

- Fix LoadBalance, Relay load error
- Fix build.yml4
- Fix build.yml3
- Fix build.yml2
- Fix build.yml
- Add search function at access control
- Fix the issues with the profile add button to cover the edit button
- Adapt LoadBalance and Relay
- Add arm
- Fix android notification icon error

## v0.8.16 (2024-06-08)

- Add one-click update all profiles
- Add expire show

## v0.8.15 (2024-06-06)

- Temp remove tun mode
- Remove macos in workflow
- Change go version

## v0.8.14 (2024-06-06)

- Update Version
- Fix tun unable to open

## v0.8.13 (2024-06-06)

- Optimize delay test2
- Optimize delay test
- Add check ip
- add check ip request

## v0.8.12 (2024-06-06)

- Fix the problem that the download of remote resources failed after GeodataMode was turned on, which caused the
  application to flash back.
- Fix edit profile error
- Fix quickStart change proxy error
- Fix core version

## v0.8.10 (2024-06-05)

- Fix core version

## v0.8.9 (2024-06-05)

- Update file_picker
- Add resources page
- Optimize more detail
- Add access selected sorted
- Fix notification duplicate creation issue
- Fix AccessControl click issue

## v0.8.7 (2024-05-31)

- Fix Workflow
- Fix Linux unable to open
- Update README.md 3
- Create LICENSE
- Update README.md 2
- Update README.md
- Optimize workFlow

## v0.8.6 (2024-05-31)

- optimize checkUpdate

## v0.8.5 (2024-05-30)

- Fix submit error

## v0.8.4 (2024-05-30)

- add WebDAV
- add Auto check updates
- Optimize more details
- optimize delayTest

## v0.8.2 (2024-05-15)

- upgrade flutter version

## v0.8.1 (2024-05-15)

- Update kernel
- Add import profile via QR code image

## v0.8.0 (2024-05-11)

- Add compatibility mode and adapt clash scheme.

## v0.7.14 (2024-05-07)

- update Version
- Reconstruction application proxy logic

## v0.7.13 (2024-05-06)

- Fix Tab destroy error

## v0.7.12 (2024-05-06)

- Optimize repeat healthcheck

## v0.7.11 (2024-05-06)

- Optimize Direct mode ui

## v0.7.10 (2024-05-06)

- Optimize Healthcheck
- Remove proxies position animation, improve performance
- Add Telegram Link
- Update healthcheck policy
- New Check URLTest
- Fix the problem of invalid auto-selection

## v0.7.8 (2024-05-05)

- New Async UpdateConfig
- add changeProfileDebounce
- Update Workflow
- Fix ChangeProfile block
- Fix Release Message Error

## v0.7.7 (2024-05-04)

- Update Selector 2

## v0.7.6 (2024-05-04)

- Update Version
- Fix Proxies Select Error

## v0.7.5 (2024-05-03)

- Fix the problem that the proxy group is empty in global mode.
- Fix the problem that the proxy group is empty in global mode.

## v0.7.4 (2024-05-03)

- Add ProxyProvider2

## v0.7.3 (2024-05-03)

- Add ProxyProvider
- Update Version
- Update ProxyGroup Sort
- Fix Android quickStart VpnService some problems

## v0.7.1 (2024-05-01)

- Update version
- Set Android notification low importance
- Fix the issue that VpnService can't be closed correctly in special cases
- Fix the problem that TileService is not destroyed correctly in some cases
- Adjust tab animation defaults
- Add Telegram in README_zh_CN.md
- Add Telegram

## v0.7.0 (2024-04-30)

- update mobile_scanner
- Initial commit
