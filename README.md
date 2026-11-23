# KuroCat with Sound

一只会打字的小黑猫 —— **键盘桌宠 + 按键音效**。

本项目是在 [chanke17/KuroCat](https://github.com/chanke17/KuroCat) 的基础上，移植了 [longyijdos/KeyFoley](https://github.com/longyijdos/KeyFoley) 的按键音效引擎的衍生版本。原版 KuroCat 只有视觉动画，此版本让小黑猫打字时同时发出键盘声音。

> 这是个人改造的衍生项目，与 KuroCat、KeyFoley 原作者无关。

## ✨ 相比原版 KuroCat 的改动

- **按键音效**：打字时按不同键播放对应样本（普通键 / 空格 / 回车 / 删除 / Esc / 方向键 / 修饰键）
- **7 套可切换音效主题**：剪刀脚、机械键盘、青轴 · ABS、黑轴 · PBT、经典打字机、桌面点击、铅笔笔记
- **音量控制**：静音 ～ 200%，设置自动保存在本地
- 以上功能全部通过 macOS 菜单栏小图标操作（「按键音效」「音效主题」「音效音量」）

KuroCat 原有的功能全部保留：黑猫/暹罗猫皮肤、打字键帽跳跃、2.5D 转头、捕猎大圆眼、摸头互动、全键无冲监听、鼠标穿透、开机自启等。

## 📦 下载与安装

从 [Releases](../../releases) 下载 `KuroCat-macOS-universal.zip`（若尚未提供，可按下方源码编译），解压后将 `KuroCat.app` 拖入「应用程序」。

- 支持 macOS 13+，Apple Silicon 与 Intel 通用二进制
- 首次打开需授予「输入监控」权限：系统设置 → 隐私与安全性 → 输入监控 → 开启 KuroCat，之后从菜单栏点击「重启 KuroCat」

### 从源码编译

```bash
chmod +x build.sh
./build.sh
open KuroCat.app
```

编译需要 Swift 编译器与 macOS 13+ SDK，无需完整 Xcode。

## ⚠️ 关于 ad-hoc 签名与权限

本项目使用 ad-hoc 签名（无 Apple 开发者证书）。**每次重新编译都会改变代码签名，导致 macOS 已授予的「输入监控」权限失效**。遇到编译安装后按键无反应的情况，请到 系统设置 → 隐私与安全性 → 输入监控，将 KuroCat 的开关关闭后再打开，并重启应用即可恢复。

## 🔊 音效实现来源

音效引擎（AVAudioEngine 播放、峰值限制、按键分类）移植自 KeyFoley 的 `Sources/KeyFoley/Sound/` 模块，并针对 KuroCat 的 `PhysicalKey` 做了适配；音效样本为 KeyFoley 内置的那 7 套主题。

## 📄 许可与归属

- **KuroCat** 原项目：MIT License，Copyright (c) 2026 chanke17 —— 见 [LICENSE](LICENSE)
- **KeyFoley** 音效引擎及样本：MIT License，Copyright (c) 2026 longyijdos
- **音效样本涉及第三方许可**（FilmCow 自定义许可、Mechvibes MIT 等）：完整声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，再分发时请务必保留

本衍生项目的新增代码遵循 MIT License。原作者保留各自作品的权利，本项目不代表其立场。

## 🙏 致谢

感谢 [chanke17](https://github.com/chanke17) 和 [longyijdos](https://github.com/longyijdos) 开源了这么有趣的项目。
