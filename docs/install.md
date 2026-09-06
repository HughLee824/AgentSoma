# AgentSoma 发布包安装

AgentSoma 为外部 agent 提供真实 iPhone 的观察和操作能力。本包包含 macOS CLI 和配套预编译 iOS Runner；setup 在本机重签，不编译源码。

## 前置条件

- 完整 Xcode，已选为当前开发工具链。
- USB 连接且已信任 Mac 的 iPhone，开启 Developer Mode 并保持解锁。
- Keychain 中可用的 Apple Development 证书及对应私钥，以及授权该证书、iPhone 和 Runner bundle ID 的 iOS development profile。

当前实测组合为 Apple Silicon / macOS 15.0.1 / Xcode 16.0 / iPhone 12 Pro / iOS 26.6，使用已有付费开发团队的签名。免费 Personal Team 的首次配置与续签尚未验收。

## Homebrew 安装

当前正在准备首次公共发布；以下命令在稳定版 Release 发布且 Tap 更新后可用。

```sh
brew install HughLee824/tap/agentsoma
agentsoma --version
```

首批提供 Apple Silicon / macOS 15 及以上的预编译包。Homebrew 安装 CLI 与配套资源，安装阶段不编译源码、不执行 setup、不接触 iPhone。完整 Xcode 和开发签名用于下一步设备接入。

## 手动下载安装

从 [GitHub Releases](https://github.com/HughLee824/AgentSoma/releases) 的同一个版本下载 `agentsoma-<version>-macos-arm64.tar.gz` 和同名 `.tar.gz.sha256`，放在同一目录。预发布版本也使用此方式安装。

在下载目录打开终端，将下面的版本换为实际下载版本，再校验和解压：

```sh
AGENTSOMA_VERSION=0.1.0 # 示例；替换为实际 Release 版本，不含 v
AGENTSOMA_PACKAGE="agentsoma-${AGENTSOMA_VERSION}-macos-arm64"
shasum -a 256 -c "${AGENTSOMA_PACKAGE}.tar.gz.sha256" && tar -xzf "${AGENTSOMA_PACKAGE}.tar.gz"
```

仅在校验显示 `OK` 且解压成功后继续。校验失败时重新下载，不运行包中的文件。GitHub 自动生成的 Source code 压缩包是源码，不是这里的预编译安装包。

可以将解压后的完整目录放在任意位置，把其中的 `bin` 加入 PATH。下面使用用户目录，安装前确保目标版本目录尚不存在：

```sh
AGENTSOMA_DEST="$HOME/.local/share/agentsoma/releases/$AGENTSOMA_VERSION"
(
  set -e
  test ! -e "$AGENTSOMA_DEST"
  mkdir -p "$HOME/.local/share/agentsoma/releases" "$HOME/.local/bin"
  mv "$AGENTSOMA_PACKAGE" "$AGENTSOMA_DEST"
  ln -sfn "$AGENTSOMA_DEST/bin/agentsoma" "$HOME/.local/bin/agentsoma"
)
export PATH="$HOME/.local/bin:$PATH"
agentsoma --version
```

把 `export PATH="$HOME/.local/bin:$PATH"` 加到 shell 配置（zsh 通常为 `~/.zshrc`），以便新终端使用。切换 Homebrew 与手动安装时，用 `command -v agentsoma` 核对实际入口。必须保留整个包的 `bin` 与 `libexec` 相对位置，不能只复制一个可执行文件。

包内包含项目 MIT 许可证、Swift ArgumentParser 许可证及版本/源码提交信息。当前 Mac CLI 使用 ad-hoc 签名，尚未完成 Developer ID 签名、公证或浏览器下载后的 Gatekeeper 验收；渠道发布状态与设备兼容性记录见[发布说明](https://github.com/HughLee824/AgentSoma/blob/main/docs/release-setup.md)。

## 首次连接

```sh
agentsoma --version
agentsoma devices
# IOS_UDID 使用 devices 返回的真实设备标识。
agentsoma setup --device "$IOS_UDID"
agentsoma connect --device "$IOS_UDID"
# SESSION 使用 connect 返回的设备会话标识。
agentsoma --session "$SESSION" open com.apple.Preferences
agentsoma --session "$SESSION" observe
agentsoma --session "$SESSION" disconnect
```

setup 自动发现 Xcode 缓存中的有效 development profile。有歧义时使用 `--team` 或 `--identity`（开发证书的 SHA-1）；外部 profile 可用 `--profile /path/to/development.mobileprovision`。默认手机 App bundle ID 为 `com.agentsoma.runner.xctrunner`；需要使用自己的标识时，添加 `--bundle-id com.example.agentsoma.xctrunner`，以后会保存复用。

profile 可按 Apple 的[开发 profile 流程](https://developer.apple.com/help/account/provisioning-profiles/create-a-development-provisioning-profile)准备。setup 不登录 Apple、不创建证书/profile，也不修改账号资源。

准备状态保存在 `~/Library/Application Support/AgentSoma`，私钥仍在 Keychain。setup 返回 `compiled:false`，并在设备握手、截图采集与正常退出成功后才保存记录。截图验证不代表业务任务已经通过验收。

## 升级和卸载

升级前先断开活跃会话。Homebrew 用户执行：

```sh
brew update
brew upgrade agentsoma
agentsoma --version
```

手动安装用户按上述流程校验新版本、安装到新的版本目录，再切换软链接。保留旧版本目录可以回退；不要将新旧包文件混合。

若 Runner 内容改变、profile 到期或文件被改动，connect 会明确要求重新 setup。在 Xcode 更新签名资料后重跑 setup；无需寻找 `.xctestrun`。不要将包含个人 provisioning profile 的本机准备目录上传到公开 issue。

卸载前断开会话。Homebrew 用户运行 `brew uninstall agentsoma`；手动安装用户删除自己创建的入口软链接及版本目录。卸载 CLI 会保留 `~/Library/Application Support/AgentSoma` 中的设备准备状态和手机上的 Runner；需要完全移除时，再删除该状态目录并在 iPhone 上卸载 AgentSoma Runner。不会删除 Keychain 证书或 Xcode 的签名资料。
