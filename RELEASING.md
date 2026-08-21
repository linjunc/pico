# Pico 发布

本地 Debug 构建不需要签名。正式发布需要 Apple Developer ID Application、Apple 公证凭据和 Sparkle Ed25519 公钥/私钥。

```bash
export RELEASE_TAG=v1.0.0
export SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export APPLE_TEAM_ID=TEAMID
scripts/build-release-dmg.sh
```

GitHub Actions 发布前需要配置 `SIGNING_IDENTITY`、`APPLE_TEAM_ID`、证书导出密码、公证 API Key 和 Sparkle 私钥。`Info.plist` 中的 `SUPublicEDKey` 必须替换为对应公钥；当前占位值只用于本地构建。

Homebrew Cask 应指向 GitHub Release 中的公证 DMG，并在每个版本发布时更新版本号和 SHA-256。

