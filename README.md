# Pico

Pico 是一款暗黑冰蓝风格、键盘优先的 macOS 剪贴板工具。

## 安装

Pico 只通过 GitHub Release 分发，不上 Mac App Store。

### Homebrew

```bash
brew tap linjunc/pico
brew install --cask pico
```

### curl

```bash
curl -fsSL https://raw.githubusercontent.com/linjunc/pico/main/scripts/install.sh | sh
```

安装脚本会下载最新 GitHub Release DMG，将 Pico 安装到 `/Applications`，不会覆盖用户数据。

### DMG

从 [GitHub Releases](https://github.com/linjunc/pico/releases) 下载最新 `Pico-*.dmg`，打开后将 Pico 拖入“应用程序”。

## 开发要求

- macOS 14+
- Xcode 26.6+
- XcodeGen

```bash
brew install xcodegen
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project Pico.xcodeproj -scheme Pico \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

默认快捷键：`⌘ ⇧ V` 打开历史，`⌥ ⇧ T` 翻译当前剪贴板。面板中使用 `← / →` 切换、Return 粘贴、T 翻译、Esc 关闭。

## 隐私

历史只保存在本机。AI API Key 写入 macOS Keychain；网络请求仅在用户主动触发翻译或连接测试时发送。

## 文档

- [产品需求](docs/product/pico-v1-prd.md)
- [交互规格](docs/product/pico-interaction-spec.md)
- [交互原型](docs/prototypes/pico-interaction-prototype.html)

## 发布渠道

- GitHub Release：DMG、ZIP、SHA-256 校验文件
- Homebrew Cask：由独立 `linjunc/homebrew-pico` tap 维护
- curl：调用仓库内 `scripts/install.sh`
- 不提交 Mac App Store，不实现 App Store 收据或沙盒同步
