# macOS 版本验证记录

日期：2026-11-10。分支：`codex/macos-version-20261110`。Windows 基线：`4e93c73`。

## 交付

- `dist/牛马脱敏器.app`
- `dist/NiuMa-macOS-universal-1.0.0.zip`（同时保留本地中文文件名副本）
- `dist/NiuMa-macOS-arm64-1.0.0.dmg`（Apple 芯片）
- `dist/NiuMa-macOS-x86_64-1.0.0.dmg`（Intel 芯片）
- `dist/SHA256SUMS.txt`
- 系统最低版本标记为 macOS 13.0，包含 arm64 和 x86_64。
- 本地 ad-hoc 签名；不是 Developer ID 签名、公证或 App Store 发布。
- 不依赖第三方库；动态链接检查只显示 Apple 系统框架和系统 Swift 库。

## 已通过

1. `bash test-macos.sh --app`：59 项计算与持久化检查，以及原生 AppKit 交互检查通过。
   - 六种状态与上下班边界、午休暂停、加班倍率、日薪/月薪、临时补班/休息及到期。
   - 月累计/满勤估算、闰年及短月发薪日、跨年、心愿单解析。
   - 非有限/越界输入、折算日薪溢出、超大心愿 ETA、零计薪天数、非法作息、午休占满全天。
   - UTF-8/多行配置、默认字段合并、保存失败不覆盖旧文件、读取损坏文件不覆盖。
   - 滚轮数字整百进位与暂停、设置控件实际宽度、全部薪资防窥。
   - 真实面板置顶、迷你/完整切换、穿透与恢复、显示/隐藏、设置保存/取消、主屏位置和菜单入口。
   - 重新创建控制器后，普通和迷你窗口均恢复保存的坐标。
2. 相同的 59 项核心检查编译为 x86_64，并在本机 Rosetta 下执行通过。
3. `bash build-macos.sh` 成功；`lipo` 确认两种架构，`vtool` 确认两种架构均为最低 macOS 13.0。
4. 真实 `.app` 已在本机 Apple 芯片 Mac 打开并检查：纸张背景、中文排版、金额、防窥、迷你和双击恢复、设置滚动、滑块与输入错误提示。
5. 通过设置临时将下班改为 23:00，真实窗口进入“上班中”，金额从 `76.00792` 递增至 `76.01896`，倒计时和进度同步更新；测试后恢复为 19:00。
6. `codesign --verify --strict` 通过；ZIP CRC 完整，二进制/元数据/背景/图标与 `.app` 匹配；用 macOS `ditto` 解压后再次验证签名与二进制通过。
7. Windows `src/`、`build.ps1`、`beij.png` 和 `LICENSE` 与基线完全一致。
8. 真实桌面测试退出后，已确认本任务的应用和测试进程结束；没有创建浏览器测试会话。
9. 两个 DMG 均通过镜像校验，并分别只读挂载检查：二进制恰好为对应的单一架构，版本为 1.0.0、最低系统标记为 13.0；签名、背景、MIT 许可证、安装说明与 `/Applications` 拖入入口均正确。检查后均已卸载镜像。
10. `SHA256SUMS.txt` 的两个 DMG 和 Universal ZIP 三个校验值均通过本地核对。发布说明位于 `docs/releases/macos-v1.0.0.md`。

## 未完成的实机验证

- **全局快捷键**：Carbon 注册没有报告冲突；UI 自动化注入的 Control+Option 组合键没有触发全局动作，尚未验证真实键盘事件。显示、迷你、防窥、穿透及其恢复逻辑通过原生调用和菜单检查。
- **通知、登录启动**：未开启系统权限或改变真实登录项；通知发送、重新登录后的启动和系统批准流程尚未实测。
- **多显示器/全屏空间**：已实现按屏幕缩放与位置约束；未做外接屏插拔、不同缩放显示器切换和全屏应用实测。
- **Intel 实机/macOS 13**：已编译 Universal 并通过 Rosetta 核心检查，未在 Intel 硬件或 macOS 13 机器上执行 GUI。
- **单实例**：实现了按 bundle identifier 发现现有进程并唤回；没有做同时冷启动竞争测试。
- 未执行长时间运行、睡眠唤醒或能耗基准，未重新测试 Windows 可执行程序。

## 平台实现参考

- [Apple：窗口鼠标事件穿透](https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents)
- [Apple：SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Apple：注册登录服务](https://developer.apple.com/documentation/servicemanagement/smappservice/register())
