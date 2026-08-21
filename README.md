# Pico

Pico 是一款暗黑冰蓝风格、键盘优先的 macOS 剪贴板工具。

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

