# Automation Memory — BiLoom 沙箱 Dart spawn 探测与自动构建

## 2026-09-29 20:31 执行记录
- probe_dart_spawn.py → SPAWN_OK（沙箱管道 bug 已随 WorkBuddy 更新恢复，dart 可正常 spawn 子进程）。
- dist 下原本无 01.00.27 产物 → 执行构建。
- `dart setup.dart windows --targets zip` 成功（49s，Flutter 构建段 27s）。
- `dart setup.dart windows --targets exe` 成功（82s，INNO_SETUP_PATH 已 export）。
- 产物：dist/BiLoom-01.00.27-windows-amd64-setup.exe（39,543,319 B ≈ 37.7 MB）、dist/BiLoom-01.00.27-windows-amd64.zip（62,872,761 B ≈ 60.0 MB）。
- 未动 git（release commit f19ef88 保持不变），未删任何文件。
- 自动化已设为 PAUSED（沙箱构建通道已打通，后续出包可直接在沙箱内跑，无需转用户本机）。

## 2026-09-30 18:09 执行记录（01.00.29）
- probe_dart_spawn.py → SPAWN_OK（沙箱 dart spawn 持续可用）。
- `dart setup.dart windows --targets zip` 成功（34s，Flutter 构建段 ~16s）。
- `dart setup.dart windows --targets exe` 成功（1m4s，Inno Setup 6.7.3 编译 37.4s）。
- 产物核对通过：dist/BiLoom-01.00.29-windows-amd64-setup.exe（39,554,030 B ≈ 37.7 MB）、dist/BiLoom-01.00.29-windows-amd64.zip（62,881,548 B ≈ 60.0 MB）。dist 下另有此前已存在的 01.00.29 android apk（57.9 MB，本次未构建）。
- 未执行任何 git 操作（release commit 530af24 保持不变），未上传官网，未构建安卓。
- 自动化已再次设为 PAUSED（01.00.29 出包完成，任务目标达成）。
