# KuroCat with Sound & Music Pulse

一只会打字的小黑猫 —— **键盘桌宠 + 按键音效 + 真实音频律动**。

本项目是在 [chanke17/KuroCat](https://github.com/chanke17/KuroCat) 的基础上衍生改造的版本，移植了 [longyijdos/KeyFoley](https://github.com/longyijdos/KeyFoley) 的按键音效引擎，并新增了由系统真实音频驱动的「音乐律动」模式。原版 KuroCat 只有视觉动画，这个版本让小黑猫打字时发出键盘声音，播放音乐时还会随节奏摆动。

> 这是个人改造的衍生项目，与 KuroCat、KeyFoley 原作者无关。

## ✨ 相比原版 KuroCat 的改动

### 键盘音效
- **按键音效**：打字时按不同键播放对应样本（普通键 / 空格 / 回车 / 删除 / Esc / 方向键 / 修饰键）
- **7 套可切换音效主题**：剪刀脚、机械键盘、青轴 · ABS、黑轴 · PBT、经典打字机、桌面点击、铅笔笔记
- **音量控制**：静音 ～ 200%，设置自动保存在本地

### 音乐律动（Music Pulse）
- **真实音频驱动**，不是预设节奏或模拟动画：直接分析系统正在播放的声音
- **6 段实时频谱**：通过级联滤波器把音频拆成 6 个频段，驱动猫咪右侧的发光胶囊光柱
- **全身参与律动**：头部随低频起伏、耳朵抖动、开心眯眼、尾巴加速、头顶浮动音符；节拍触发时整组光柱冲高并留下缓缓回落的峰值帽
- **拾音器光柱颜色跟随瞳色主题**（黄绿色 / 暹罗蓝等自动适配）
- **完全无干扰叠加层**：音乐模式不影响打字动画与键盘音效；打字时前爪始终优先回到打字动作
- 通过菜单栏「🎵 音乐律动（拾音器 + 音符）」开关

KuroCat 原有的功能全部保留：黑猫/暹罗猫皮肤、打字键帽跳跃、2.5D 转头、捕猎大圆眼、摸头互动、全键无冲监听、鼠标穿透、开机自启、尺寸缩放等。

## 🖥️ 平台支持

| 平台 | 状态 |
|------|------|
| **macOS** | ✅ 当前版本仅支持 macOS |
| Windows | 🚧 计划中，尚未实现 |
| Linux | 🚧 暂无计划 |

**为什么目前只有 macOS？** 本项目新增的三块能力都依赖 Apple 专属技术：

- 音乐律动使用 **Core Audio Process Tap**（macOS 14.2+ 独占 API）
- 按键音效使用 **AVAudioEngine / AVFAudio**
- 全局键鼠监听使用 **CGEventTap + IOHIDManager**，权限基于 macOS TCC

渲染层（Core Graphics 矢量绘制）理论上可以移植，但音频捕获、音效播放和按键监听这三块在 Windows 上需要分别改用 WASAPI loopback、DirectSound/XAudio2 和 Windows Hook 重写，不是改个编译目标就能跑的。Windows 端已列入后续计划。

### 系统版本要求

- **macOS 13.0+**：键盘音效、打字动画等全部基础功能
- **macOS 14.2+**：音乐律动模式（Core Audio Tap 的最低要求）

本项目编译为 Apple Silicon + Intel 通用二进制（universal）。

## 📦 下载与安装

从 [Releases](../../releases) 下载 `KuroCat-macOS-universal.zip`（若尚未提供，可按下方源码编译），解压后将 `KuroCat.app` 拖入「应用程序」。

### 首次授权

1. **输入监控**（打字动画 + 音效必需）：系统设置 → 隐私与安全性 → 输入监控 → 开启 KuroCat。第一次打开时会提示，授权后从菜单栏点击「重启 KuroCat」刷新。
2. **仅录制系统音频**（音乐律动必需）：打开音乐律动模式时，系统会弹出「系统音频录制」权限请求，请允许。音频**只在内存中实时分析，不会录音、保存或上传**。

> 音乐律动使用 Core Audio Tap 而不是屏幕录制，因此**不需要屏幕录制权限**，也不会出现录屏标志。macOS 可能会在控制中心显示一个系统音频使用提示，这是系统行为，无法从应用侧关闭。

### 从源码编译

```bash
chmod +x build.sh
./build.sh
open KuroCat.app
```

编译需要 Swift 编译器与 macOS 13+ SDK，无需完整 Xcode。

## ⚠️ 关于 ad-hoc 签名与权限

本项目使用 ad-hoc 签名（无 Apple 开发者证书）。**每次重新编译都会改变代码签名，导致 macOS 已授予的「输入监控」权限失效**。遇到编译安装后按键无反应、动画音效消失的情况，请到 系统设置 → 隐私与安全性 → 输入监控，将 KuroCat 的开关关闭后再打开，并重启应用即可恢复。

如果你有 Apple Development 证书，`build.sh` 会自动优先使用它签名，从而跨重编译保持权限。

## 🔊 实现来源

- **音效引擎**（AVAudioEngine 播放、峰值限制、按键分类）移植自 KeyFoley 的 `Sources/KeyFoley/Sound/` 模块，并针对 KuroCat 的 `PhysicalKey` 做了适配；音效样本为 KeyFoley 内置的那 7 套主题。
- **音乐律动**为本项目新增，基于 Apple 的 Core Audio Process Tap API 自行实现频谱分析与动画驱动，未使用第三方代码。

## 📄 许可与归属

- **KuroCat** 原项目：MIT License，Copyright (c) 2026 chanke17 —— 见 [LICENSE](LICENSE)
- **KeyFoley** 音效引擎及样本：MIT License，Copyright (c) 2026 longyijdos
- **音效样本涉及第三方许可**（FilmCow 自定义许可、Mechvibes MIT 等）：完整声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，再分发时请务必保留

本衍生项目的新增代码遵循 MIT License。原作者保留各自作品的权利，本项目不代表其立场。

## 🙏 致谢

感谢 [chanke17](https://github.com/chanke17) 和 [longyijdos](https://github.com/longyijdos) 开源了这么有趣的项目。
