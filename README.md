# 牛马脱敏器

<img width="924" height="1020" alt="Windows 版预览" src="https://github.com/user-attachments/assets/f4c85b4b-0717-4797-882d-52b963491031" />

一个 Windows / macOS 桌面悬浮窗小工具：实时显示你今天上班已经赚了多少钱，数字平滑滚动，默认精确到小数点后 5 位。

上班摸鱼时看一眼，每一秒都在到账。


## 功能

- **实时薪资**：按日薪或月薪、上下班时间计算今日已赚，数字平滑递增，无跳变
- **状态显示**：还没上班 / 上班中 / 午休中 / 加班中 / 已下班 / 休息日，附下班倒计时
- **工时进度条**、当前赚钱速度（每秒 / 每分钟）、时薪、本月累计、距离发薪日天数
- **心愿单**：「今天已经赚到一件 T 恤了」，可自定义物品和价格
- **毒鸡汤语录**：每 10 分钟轮换一条，可自定义
- **原生悬浮窗**：可置顶、拖动、贴边吸附、托盘图标
- **迷你模式**：双击窗口切换
- **防窥**：一键隐藏金额，显示为 `****`
- **鼠标穿透**：窗口不挡点击
- **自适应分辨率**：窗口高度约占屏幕一半，1080p / 2K / 4K、任意系统缩放、多显示器都按当前屏幕自动适配
- **可自定义**：软件名称、背景图片、背景 / 信息卡 / 整体透明度、界面大小、小数位数、货币符号、工作日、午休、加班倍率、发薪日、开机自启、上下班提醒
- **临时调休**：右键菜单可把今天标记为请假或补班

## 快捷键

| 快捷键 | 作用 |
| --- | --- |
| `Ctrl + Alt + M` | 显示 / 隐藏窗口 |
| `Ctrl + Alt + H` | 隐藏 / 显示金额 |
| `Ctrl + Alt + T` | 开关鼠标穿透 |
| 双击窗口 | 切换迷你模式 |
| 右键窗口 | 打开菜单 |

macOS 使用 `Control + Option + M / H / T`，对应上述三个全局操作。菜单栏的钞票图标始终提供显示窗口、关闭穿透、设置和退出入口。快捷键冲突时会在菜单中提示。

## 下载使用

### macOS 版本

本分支包含独立原生 Mac 实现，要求 **macOS 13 或以上**。编译后打开 `dist/牛马脱敏器.app`；也可以将它拖入「应用程序」。应用不显示 Dock 图标，入口在屏幕顶部菜单栏。

```bash
# 只需 Apple Command Line Tools；不需要 .NET、Node 或第三方依赖
bash build-macos.sh
open "dist/牛马脱敏器.app"
```

同时生成支持 Apple 芯片和 Intel 的 `dist/牛马脱敏器-macOS-universal.zip`。当前使用本地 ad-hoc 签名，尚未经过 Apple Developer ID 签名或公证；这不是已发布的正式安装包。构建时未配置编译工具，可先运行 `xcode-select --install`。

Mac 版保留薪资计算、工作状态、进度、月累计、心愿单、语录、滚轮数字、迷你、防窥、置顶、拖动吸附、穿透、临时调休、设置、上下班通知和登录启动。设置在保存后应用，取消放弃修改；通知和登录启动默认关闭，需在设置中自行启用。登录启动采用系统登录项，建议先移动到「应用程序」。

月累计是按已过工作日满勤计算的**估算**，不记录历史考勤或历史加班。与 Windows 版一致，当前不支持跨夜班次。

### Windows 版本

到 [Releases](../../releases) 页面下载 `牛马脱敏器.exe`，双击运行即可，无需安装。

系统要求：Windows 10 / 11（自带 .NET Framework 4.8）。

## 从源码编译

不需要安装 Visual Studio，系统自带的 .NET Framework 编译器就够了。在项目目录打开 PowerShell，运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

编译完成后，项目目录下会生成 `牛马脱敏器.exe`。`beij.png` 和 `src\app.ico` 会被打包进 exe。

## 项目结构

```
├── build.ps1              编译脚本
├── build-macos.sh         macOS Universal .app / ZIP 构建
├── test-macos.sh          Mac 纯逻辑测试；--app 追加原生窗口测试
├── beij.png               默认背景图
├── macos
│   ├── Info.plist         macOS 应用元数据
│   ├── Sources           原生 Swift 计算、设置、悬浮窗、菜单栏
│   └── Tests             计算与设置回归、原生窗口交互检查
└── src
    ├── App.cs             程序入口、单实例、通用 UI 工具
    ├── Engine.cs          薪资与时间计算
    ├── MainWindow.cs      悬浮窗主界面、托盘、快捷键
    ├── Odometer.cs        滚轮翻牌数字控件
    ├── Settings.cs        设置项的读写
    ├── SettingsWindow.cs  设置窗口
    ├── app.ico            图标
    └── app.manifest       DPI 感知声明
```

## 设置文件

Windows：`%APPDATA%\NiuMaTuoMinQi\settings.ini`。

macOS：`~/Library/Application Support/NiuMaTuoMinQi/settings.json`，采用原子写入。无法读取时保留原文件并提示；用户在设置中重新保存时，先备份损坏文件。两个平台的设置不自动互相导入。

Mac 测试使用临时目录，不改动真实配置：

```bash
bash test-macos.sh        # 纯逻辑回归
bash test-macos.sh --app  # 追加真实 AppKit 窗口测试，需要图形桌面
```

项目分析与移植取舍见 [macOS 设计](docs/superpowers/specs/2026-11-10-macos-design.md)，实际验证范围见 [Mac 验证记录](docs/macos-validation.md)。

## 许可证

[MIT](LICENSE)
