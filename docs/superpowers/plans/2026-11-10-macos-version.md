# macOS Version Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task by task in this session.

**Goal:** Deliver a native, runnable Mac version of 牛马脱敏器 on `codex/macos-version-20261110`.

**Architecture:** Separate Foundation-only settings/calculation/digit logic from AppKit windows. The app owns its panel, menu bar item, hotkey registrations and timers. Build a Universal app bundle with shell tools already installed on macOS.

**Tech Stack:** Swift, AppKit, Carbon, UserNotifications, ServiceManagement; macOS 13+.

**Spec:** `docs/superpowers/specs/2026-11-10-macos-design.md`

## Global Constraints

- Windows 源码、资源及编译脚本保持原样。
- macOS 13+，构建 arm64/x86_64 Universal `.app`。
- 配置原子写入；无效配置报告错误，不能自动覆盖损坏的原文件。
- 不注册登录启动、不请求通知权限，除非用户在设置中启用。

## Review Focus

- 输入 NaN/无穷、错误午休、零月计薪天数不能进入计算或破坏旧设置。
- 月末、跨年、休息日和已过期调休应使用当地日历规则。
- 开启穿透后菜单栏和快捷键应能够恢复；设置窗口应保持可点击。
- 断开显示器、修改缩放或切换迷你后，窗口应留在可用屏幕内。
- 防窥、设置取消、后台隐藏和终止清理不能泄漏金额或误写用户配置。

## Task 1: Foundation model and regression checks

**Files:** `macos/Sources/Settings.swift`, `Engine.swift`, `Digits.swift`, `macos/Tests/CoreTests.swift`, `test-macos.sh`.
**Interfaces:** `AppSettings`, `SettingsStore.load/save`, `Engine.compute/monthEarned/monthTotal/daysToPayDay/wishText`, `DigitRoller.offsets`.

- [x] Write executable checks with hand-derived expected values and run to establish missing implementation.
- [x] Implement the original calculation rules and strict settings validation with atomic JSON storage.
- [x] Verify six states, salary modes, lunch, overtime, date overrides, paydays, malformed settings, persistence and digit carry.

## Task 2: Native desktop application

**Files:** `macos/Sources/MainWindow.swift`, `SettingsWindow.swift`, `App.swift`, `macos/Info.plist`, `macos/Tests/AppTests.swift`.
**Consumes:** Task 1 types and computations.
**Produces:** `NiuMa` executable with panel, menu bar, settings and platform actions.

- [x] Add native smoke checks for actual window actions, privacy and settings transactions.
- [x] Implement NSPanel, accessible controls, rolling digits, all status fields and background.
- [x] Implement settings validation/save/cancel, menus, hotkeys, opt-in notifications/login and single-instance recovery.
- [x] Run native checks using a temporary settings directory and close all owned resources.

## Task 3: Bundle and handoff

**Files:** `build-macos.sh`, `README.md`, `docs/macos-validation.md`.
**Consumes:** Task 2 executable and existing `beij.png`/`src/app.ico`.

- [x] Compile both architectures, embed icon/background/plist, ad-hoc sign, create distributable zip.
- [x] Launch the real app, inspect native UI and exercise interactions; close owned test processes.
- [x] Run full test scripts, verify bundle/signature/architectures and unchanged Windows files.
- [x] Record actual validation limits and deliver artifact and branch; leave remote publication untouched.

## Completion evidence

Implementation tasks completed. Actual verification and remaining device/permission checks are recorded in `docs/macos-validation.md`; global key registration is not claimed as physical-key acceptance. The feature branch stays separate from main.
