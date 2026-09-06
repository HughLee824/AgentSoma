# AgentSoma 发布包安装

AgentSoma 为外部 agent 提供真实 iPhone 的观察和操作能力。本包包含 macOS CLI 和配套预编译 iOS Runner；setup 在本机重签，不编译源码。

## 前置条件

- 完整 Xcode，已选为当前开发工具链。
- USB 连接且已信任 Mac 的 iPhone，开启 Developer Mode 并保持解锁。
- Keychain 中可用的 Apple Development 证书及对应私钥，以及授权该证书、iPhone 和 Runner bundle ID 的 iOS development profile。

当前实测组合为 Apple Silicon / macOS 15.0.1 / Xcode 16.0 / iPhone 12 Pro / iOS 26.6，使用已有付费开发团队的签名。免费 Personal Team 的首次配置与续签尚未验收。

## 安装和连接

解压完整目录并进入它，将其中的 bin 加入 PATH；也可为 bin/agentsoma 创建软链接。保留 bin 与 libexec 的相对位置。

```sh
export PATH="$PWD/bin:$PATH"
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

升级时先断开旧会话，安装完整新包。若 Runner 内容改变、profile 到期或文件被改动，connect 会明确要求重新 setup。在 Xcode 更新签名资料后重跑 setup；无需寻找 `.xctestrun`。不要将包含个人 provisioning profile 的本机准备目录上传到公开 issue。
