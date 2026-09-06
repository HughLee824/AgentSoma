# Release 与 setup

状态：2026-09-06 已实现并完成已有付费开发签名条件下的真机验证；当前生成本地候选包，尚未发布公共 release。

用户选择的路线为“预编译 CLI + 预编译 Runner，本机重签部署”。保留 Xcode 和用户自己的开发签名前提，日常使用不依赖源码仓库或 `.build` 目录。用户流程见[首次接入](onboarding.md)，发布包附带的独立说明见[安装说明](install.md)。

## 包结构与信任边界

```text
agentsoma-<version>-macos-<architecture>/
  bin/agentsoma
  libexec/agentsoma/runner/
    manifest.json
    Runner.xctestrun
    AgentSomaRunner.app/
  README.md
  LICENSE…                  # 仓库确定许可证后随包复制
```

CLI 从自身真实路径定位配套资源，支持搬移整个目录和软链接入口。manifest 记录格式版本、release 版本、CLI SHA-256、Runner 内容版本、最低 iOS 版本和逐文件 SHA-256。CLI/Runner 混装、文件缺失、额外文件、符号链接和外部测试产物路径均拒绝。文件摘要用于发现错误和混装，不替代可信下载来源或维护者签名。

发布 Runner 不包含 provisioning profile、嵌入的 XCTest 框架、调试符号包或源码。发布构建将 iOS 编译下限设为 17，使用设备提供的 XCTest；最低版本检查只排除已知不兼容，不证明所有 iOS/Xcode 组合都可用。XCTest 的断言和跳过报告使用 `#fileID`，打包时检查二进制是否残留源码仓库的绝对路径。

setup 将包复制到用户状态目录，改写为保存的 App bundle ID、嵌入用户 profile，由本机 codesign 对测试 bundle 和 Runner 签名并校验。随后使用 `test-without-building` 做真机握手、截图和退出验证，成功后原子更新按 UDID 保存的记录。安装目录不写入用户签名资料。设备能力握手仍是最终兼容性检查；本地文件存在和签名校验成功不能替代它。

相同设备重复 setup 复用有效产物，续签时扫描 Xcode profile 和已保存 profile。相同签名配置选择较晚到期的有效 profile；跨团队或证书有歧义时明确报错，不猜测。Runner 内容摘要不包含 CLI release 版本和 CLI 摘要，因此同一 Runner 原样随 CLI 更新时可复用。新的重签目录不会覆盖旧目录，活跃会话继续持有自己的文件。

## 维护者构建

在 macOS/Xcode 主机的源码目录执行，需要 Python 3.9+；Python 仅用于维护者打包，不是用户运行依赖：

```sh
swift test
python3 scripts/build-release.py --version 0.1.0-dev.6
```

脚本构建 release CLI、在隔离目录 `build-for-testing` 构建无开发签名的 Runner，移除二进制调试信息，整理固定相对路径的测试清单，然后生成目录、tar.gz 和 SHA-256 文件。CLI 仅作本机运行所需的 ad-hoc 签名。产物默认位于 `.build/releases`，也可用 `--output-dir` 指定；已有同名产物会拒绝覆盖。CLI 与 Runner 构建日志分开保存。脚本不创建 tag、不上传文件、不操作 Apple 账号、不使用维护者的 iOS profile。

当前脚本只生成**未经 Mac 发布签名和 notarization 的候选包**。公开发布还需确定许可证和发布位置，并接入维护者 Developer ID 签名、公证和下载渠道。Mac 签名必须先于 CLI 摘要及最终归档，签名后不能继续使用旧的 `cliSHA256` 或压缩包校验值。Apple 发布要求见 [Developer ID](https://developer.apple.com/developer-id/) 和 [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。不要把现有开发者本机候选包视作已通过公共安装验收的 release。

## 当前验收

环境：Apple Silicon、macOS 15.0.1、Xcode 16.0 / Swift 6.0、iPhone 12 Pro / iOS 26.6，已有付费开发团队的证书和 profile。没有申请新的 Apple 签名资源。

| 检查 | 结果 |
| --- | --- |
| Swift 回归测试 | 92 项通过；新增 11 项覆盖发布包搬移/软链接入口、CLI 混装、文件缺失/改动/额外文件、profile/Frameworks 泄漏、外部 xctestrun 路径、最低 iOS 版本、profile 授权与到期、签名选择及设备准备状态。 |
| 预编译技术验证 | 先将现有预编译 Runner 去除签名资料和内嵌框架，再本地重签、安装启动；重签前后两个可执行文件的 `__TEXT,__text` 摘要一致。 |
| 首次 setup | 全新维护者构建的候选包从仓库外、含空格的搬移目录及软链接入口执行成功，返回 `compiled:false`、`reused:false`。 |
| 重复 setup | 省略 profile、identity 和 team，成功发现保存的签名配置，返回 `compiled:false`、`reused:true`。 |
| 最终归档与升级 | `0.1.0-dev.6` 从经过 SHA-256 校验的 tar.gz 解压、搬移并设为只读；旧准备记录返回 `setup_update_required`，随后 setup、重复 setup 和新连接均通过，安装目录内容未改变。两个可执行文件重签前后的 `__TEXT,__text` 摘要一致。 |
| 文件损坏 | 改动实际发布包的 Runner 后，setup 在查询设备前返回 `runner_package_invalid`。 |
| 日常连接 | 不传 `.xctestrun`，connect、打开系统设置、observe 和 disconnect 均成功；截图 1170×2532，AX 可用，Runner 显示为 AgentSoma Runner。 |
| 清理 | 正常 shutdown 确认，xcodebuild 退出 0，没有强制终止，观察缓存移除。 |

本次证据保存在本机 `/private/tmp/agentsoma-release-acceptance-20260906`，技术探针在 `/private/tmp/agentsoma-prebuilt-probe-20260906`。目录包含用户本机数据，不随发布包分发；自动化测试不依赖这些目录。

验收用候选包同时安装在用户级 `~/.local/share/agentsoma/releases/0.1.0-dev.6`，入口为 `~/.local/bin/agentsoma`。这只是当前本机的安装位置，不硬编码到 CLI 或发布格式中。

## 尚未验收的发布条件

- 免费 Apple 账号是否列为首发正式支持，以及首次 provisioning 和七天到期后的续签恢复。
- 全新 Mac 从无证书/profile 到完成 setup；更多 Xcode/iOS 组合与 Intel Mac。
- 免 Xcode 启动。
- 开源许可证、公开发布位置、Mac 发布签名与公证、下载后 Gatekeeper 安装体验。

这些条件不由本机已有付费开发团队的成功结果推断，也不阻塞当前预编译路线的代码与本机验收。
