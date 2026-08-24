# Pico 发布

Pico 只发布 GitHub Release，不提交 Mac App Store。每次正式版本至少上传 DMG、ZIP 和 SHA-256 文件；Homebrew Cask 在发布后更新版本与校验值。

## v1.0.0 未签名发布

没有 Apple Developer 账号时使用：

```bash
RELEASE_TAG=v1.0.0 scripts/build-unsigned-dmg.sh
```

产物位于 `build/release/`：

- `Pico-v1.0.0.dmg`
- `Pico-v1.0.0.zip`
- `Pico-v1.0.0.dmg.sha256`

在 GitHub 创建 `v1.0.0` Release 后上传上述三个文件。用户首次启动需要右键 `Pico.app` → “打开” → “打开”。这属于未签名版本的正常 Gatekeeper 行为。

也可以使用一键上传脚本：

```bash
brew install gh
gh auth login
RELEASE_TAG=v1.0.0 scripts/publish-github-release.sh
```

脚本会自动创建或更新 GitHub Release，并上传 DMG、ZIP 和 SHA-256 文件。没有 `gh` 时可以设置具有仓库写权限的 `GITHUB_TOKEN`，脚本会自动切换到 GitHub API。

未签名版本可以通过 Homebrew Cask 安装，但不能绕过 Gatekeeper；正式签名和公证需要 Developer ID Application。

本地 Debug 构建不需要签名。正式发布需要 Apple Developer ID Application、Apple 公证凭据和 Sparkle Ed25519 公钥/私钥。

```bash
export RELEASE_TAG=v1.0.0
export SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export APPLE_TEAM_ID=TEAMID
scripts/build-release-dmg.sh
```

GitHub Actions 发布前需要配置 `SIGNING_IDENTITY`、`APPLE_TEAM_ID`、证书导出密码、公证 API Key 和 Sparkle 私钥。`Info.plist` 中的 `SUPublicEDKey` 必须替换为对应公钥；当前占位值只用于本地构建。

Homebrew Cask 应指向 GitHub Release 中的公证 DMG，并在每个版本发布时更新版本号和 SHA-256。

## 发布检查清单

1. 更新 `CFBundleShortVersionString` 和 `CFBundleVersion`。
2. 运行 `xcodegen generate`，确认 Debug 构建和单元测试。
3. 用 Developer ID 签名并公证 App，确认 `spctl --assess` 通过。
4. 运行 `scripts/build-release-dmg.sh`，生成 DMG、ZIP、SHA-256。
5. 在 GitHub 创建 `vX.Y.Z` Release，上传全部产物。
6. 将 `packaging/homebrew/pico.rb` 中的版本和 SHA-256 同步到独立 tap。
7. 用以下三种方式做干净机器验收：

   ```bash
   brew install --cask linjunc/pico/pico
   curl -fsSL https://raw.githubusercontent.com/linjunc/pico/main/scripts/install.sh | sh
   ```

   以及手动打开 DMG 拖入 `/Applications`。

8. 首次启动检查辅助功能授权、`⌘⇧V`、粘贴、登录启动和卸载残留。
