# Release 与 setup

状态：2026-09-06 已完成已有付费开发签名条件下的真机验证；已接入 GitHub Release 草稿、Homebrew Tap 与手动下载分发流程，当前尚未发布公共 release。项目采用 MIT，发布仓库为 `HughLee824/AgentSoma`，Tap 为 `HughLee824/homebrew-tap`。

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
  LICENSE                   # 项目 MIT
  licenses/SwiftArgumentParser.txt
  build-info.json           # 版本、架构、源码提交、工作区状态、构建工具版本
```

CLI 从自身真实路径定位配套资源，支持搬移整个目录和软链接入口。manifest 记录格式版本、release 版本、CLI SHA-256、Runner 内容版本、最低 iOS 版本和逐文件 SHA-256。CLI/Runner 混装、文件缺失、额外文件、符号链接和外部测试产物路径均拒绝。文件摘要用于发现错误和混装，不替代可信下载来源或维护者签名。

发布 Runner 不包含 provisioning profile、嵌入的 XCTest 框架、调试符号包或源码。发布构建将 iOS 编译下限设为 17，使用设备提供的 XCTest；最低版本检查只排除已知不兼容，不证明所有 iOS/Xcode 组合都可用。XCTest 的断言和跳过报告使用 `#fileID`，打包时检查二进制是否残留源码仓库的绝对路径。

setup 将包复制到用户状态目录，改写为保存的 App bundle ID、嵌入用户 profile，由本机 codesign 对测试 bundle 和 Runner 签名并校验。随后使用 `test-without-building` 做真机握手、截图和退出验证，成功后原子更新按 UDID 保存的记录。安装目录不写入用户签名资料。设备能力握手仍是最终兼容性检查；本地文件存在和签名校验成功不能替代它。

相同设备重复 setup 复用有效产物，续签时扫描 Xcode profile 和已保存 profile。相同签名配置选择较晚到期的有效 profile；跨团队或证书有歧义时明确报错，不猜测。Runner 内容摘要不包含 CLI release 版本和 CLI 摘要，因此同一 Runner 原样随 CLI 更新时可复用。新的重签目录不会覆盖旧目录，活跃会话继续持有自己的文件。

## 维护者构建

在 macOS/Xcode 主机的源码目录执行，需要 Python 3.9+；Python 仅用于维护者打包，不是用户运行依赖：

```sh
swift test
python3 -m unittest discover -s scripts/tests -v
python3 scripts/build-release.py --version 0.1.0-rc.1 --require-clean
python3 scripts/verify-release.py .build/releases/agentsoma-0.1.0-rc.1-macos-arm64.tar.gz --require-clean
python3 scripts/generate-homebrew.py .build/releases/agentsoma-0.1.0-rc.1-macos-arm64.tar.gz --output .build/releases/agentsoma.rb
```

脚本构建 release CLI、在隔离目录 `build-for-testing` 构建无开发签名的 Runner，移除二进制调试信息，整理固定相对路径的测试清单，附带许可证及构建记录，然后生成目录、tar.gz 和 SHA-256 文件。CLI 仅作本机运行所需的 ad-hoc 签名。产物默认位于 `.build/releases`，也可用 `--output-dir` 指定；已有同名产物会拒绝覆盖。打包和清单检查在临时目录完成，失败不会留下同名的半成品包。CLI 与 Runner 构建日志分开保存。脚本不创建 tag、不上传文件、不操作 Apple 账号、不使用维护者的 iOS profile。

`--require-clean` 要求构建前后源码已提交且工作区干净；公开 formula 生成也拒绝工作区有未提交修改的包。本地开发验收可省略此选项，formula 生成添加 `--local` 使用 `file://` 下载地址。含本机地址的 formula 不上传到 Tap。

`verify-release.py` 校验外层 SHA-256、归档路径、许可证、构建记录、CLI 与 Runner 逐文件摘要及测试清单，拒绝软链接、越界路径、签名资料和嵌入框架。默认还在含空格的新目录解压搬移，通过软链接执行版本和帮助命令并检查 CLI 签名；其他系统可用 `--no-execute` 仅检查归档。

AgentSoma 仍是 macOS CLI。Mac Developer ID 签名、公证是下载渠道与系统信任体验的选择，不代表需要制作 Mac GUI App，也不是所有 CLI 分发渠道统一的前置条件。当前流程未使用 Developer ID 或 notarization。若以后接入，签名必须先于 CLI 摘要及最终归档，不能沿用旧摘要。见 Apple 的 [Developer ID](https://developer.apple.com/developer-id/) 和 [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。浏览器下载后及全新 Mac 的安装体验仍需单独验收。

## GitHub Releases 与 Homebrew Tap

首次分发只生成已验证的 `macos-arm64` 安装包。工作流使用 GitHub 的 `macos-15` ARM64 runner 和 Xcode 16.0；Intel 发布不在当前矩阵内。构建不需要维护者的 Apple 签名证书、profile 或 iPhone。

1. 将本次发布源码提交到 `HughLee824/AgentSoma` 的 `main`，让 CI 通过。
2. 在 Actions 中运行 **Draft release**，填写未使用过的版本，不含 `v`。工作流只允许从主仓库的 `main` 执行，运行 Swift/Python 测试，构建干净源码，验证归档、搬移和 Homebrew 安装后的全部 CLI/Runner 摘要。
3. 验收通过后，独立的写入任务创建 GitHub Release **草稿**，附上 tar.gz、SHA-256 和从同一归档生成的 `agentsoma.rb`。已有 tag 拒绝复用，不覆盖旧版本。包含 `-` 的版本自动标记 prerelease。
4. 检查草稿及对应版本的设备验收证据后发布。CI 没有 iPhone，不能替代 setup 和业务任务的真机验收。
5. 稳定版发布后，在 `HughLee824/homebrew-tap` 的 Actions 运行 **Update AgentSoma**，填写相同版本。它拒绝草稿和预发布版，校验归档、源码提交与 tag，再生成并对比 release 中的 formula，最后提交到 Tap 的 `main`。重复同版本不产生空提交。

Tap 初始文件位于 `packaging/homebrew-tap`，另复制仓库根目录的 `LICENSE`。其更新工作流只需要 Tap 自身的 `GITHUB_TOKEN`，不需要跨仓库写入 PAT；AgentSoma 源码与 Release 需公开可读。首次稳定版之前不放置指向不存在资产的 formula。预发布版本通过 GitHub Releases 手动安装。

远程准备状态（2026-09-06）：已创建公开的 `HughLee824/AgentSoma` 空仓库，并将本项目 `origin` 配置到该仓库；`HughLee824/homebrew-tap` 的 MIT、README 和更新工作流已初始化，提交为 `31084c2`。AgentSoma 源码尚未推送，公共 Release 与稳定 formula 尚未创建。推送源码后，按上面的顺序运行首次发布。

formula 将原包的 `bin` 与 `libexec` 一起放在 Homebrew keg 的 `libexec` 下，并创建 `bin/agentsoma` 软链接，保持 CLI 的相对资源定位规则。安装与升级不执行 setup，不编译、不在 iPhone 上操作。每次 release 的 `brew test` 检查安装后的 CLI 与 Runner 全部文件摘要，以发现 Homebrew 清理或二进制处理引入的修改。

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

分发流程补充验收（2026-09-06）：92 项 Swift 测试和 16 项 Python 发布工具测试通过；actionlint 1.7.11 检查三份工作流通过。`0.1.0-dev.7` 候选包通过归档、搬移、软链接执行和签名检查，SHA-256 为 `3b78d21f86fe62740003cf7030f3c397fc1213a5e4d972969b2ec1f3fd5a3f1b`。Homebrew 6.0.12 从本地临时 Tap 安装成功，`brew test` 通过；CLI 和 Runner 的 6 个文件摘要全部与原包一致。该候选包记录 `sourceDirty:true`，不用于公共发布。测试后已卸载临时 Homebrew 包、移除临时 Tap 并恢复原开发模式设置，原用户级 `0.1.0-dev.6` 安装保留。证据位于本机 `/private/tmp/agentsoma-distribution-acceptance-20260906`，不随发布包分发。此轮没有重新操作 iPhone，也未运行 GitHub 托管 CI。

## 尚未验收的发布条件

- 免费 Apple 账号是否列为首发正式支持，以及首次 provisioning 和七天到期后的续签恢复。
- 全新 Mac 从无证书/profile 到完成 setup；更多 Xcode/iOS 组合与 Intel Mac。
- 免 Xcode 启动。
- GitHub 托管 runner 上的首轮发布工作流、公共下载后的全新 Mac / Gatekeeper 安装体验；是否增加 Developer ID 签名与公证根据渠道验收决定。

这些条件不由本机已有付费开发团队的成功结果推断，也不阻塞当前预编译路线的代码与本机验收。
