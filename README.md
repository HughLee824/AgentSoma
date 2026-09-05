# AgentSoma

AgentSoma 为外部 agent 提供操作真实 iPhone 的眼睛和手。自然语言理解、任务规划和结果判断由调用 agent 负责。

当前已进入 Swift CLI 与会话宿主实现阶段。调用链为：

```text
agent → agentsoma CLI → 按会话运行的 Swift 宿主 → CoreDevice IPv6 → 薄 XCTest Runner
```

## 构建与使用

当前开发环境为 macOS 15.0.1、Xcode 16.0 / Swift 6.0，真机为 iOS 26.6。Swift 包的 macOS 13 部署目标是编译下限，尚不代表完整设备链路在 macOS 13 上经过验证。

```sh
swift build
swift test
.build/debug/agentsoma --help
```

唯一源码库依赖是锁定为 1.5.0 的 [Swift ArgumentParser](https://github.com/apple/swift-argument-parser/tree/1.5.0)，可由当前工具链编译；没有 iproxy、pymobiledevice3、Python 或 Node 运行依赖。

本阶段复用 [XCTest 探针工程](spikes/ios-xctest/README.md) 已签名的构建。先在 Xcode 配置自己的开发团队并构建 Runner，保持设备解锁、USB 连接。CLI 暂时通过 `--xctestrun` 接收构建路径，自动构建与首次安装引导留待后续实现。

```sh
.build/debug/agentsoma connect \
  --device "$IOS_UDID" \
  --xctestrun "$SIGNED_XCTESTRUN"

# 使用 connect 实际返回的 session。
.build/debug/agentsoma --session "$SESSION" status
.build/debug/agentsoma --session "$SESSION" open com.somnus.agentsoma.spike.fixture
.build/debug/agentsoma --session "$SESSION" disconnect
```

`connect` 在宿主和 Runner 均可响应后返回，agent 不需要单独启动后台服务。每条 CLI 命令结束后，宿主继续持有原 XCTest 会话。会话结束后，宿主释放自己的 xcodebuild/Runner 资源并退出。

当前提供 `connect`、`status`、`open`、`disconnect`。`open` 激活已运行的 App，未运行时启动；临时复用的探针 Runner 仍只允许 Fixture 与 Calculator。这个限制不属于计划中的产品 App 范围。紧凑 `observe`、`inspect`、引用与完整动作接口按 [实现计划](docs/v0.1-plan.md) 接着开发。

## 生命周期与输出

- 默认空闲 **30 分钟**；建立连接时可用 `--idle-timeout 60m` 调整，也接受 `s`、`m`、`h`，便于用短时间验收。
- 有效 `open` 请求完成后续期，包括执行结果未知的请求。参数检查失败不续期。后续观察、动作与详情读取使用同一生命周期规则。
- 已接收、排队或执行中的命令不被空闲回收；`disconnect` 等待已经接收的命令结束，再清理会话。
- `status` 检查 Runner 并返回剩余空闲时间，不续期。当前没有额外内部保活轮询。
- 运行结果为单行 JSON，成功退出码为 0，运行失败为 1；参数语法错误由 ArgumentParser 输出到 stderr 并非零退出。
- `open` 返回 `completed`、`not_dispatched` 或 `unknown`。当前探针没有完整执行阶段信息，Runner 错误保守归为 `unknown`；连接中断或丢失响应不自动重发。

状态目录默认为 `/private/tmp/agentsoma-<uid>`，目录权限 0700；可通过 `AGENTSOMA_STATE_DIR` 设置较短的替代路径。每个会话包含本地 Unix socket、启动配置和诊断文件。设备 token 只保存在宿主内存及 XCTest 子进程环境，不写入配置文件或 CLI 输出。相同状态目录内对设备规范 UDID 使用系统文件锁，拒绝重复占用；锁文件保留，锁本身随持有进程退出而释放。

断开或到期后 socket 删除，原 session 不能继续调用。诊断文件暂时保留供开发排查，清理这些文件不负责断开活跃会话。当前不承诺宿主遭 SIGKILL、Mac 重启、物理断线或设备锁屏后的自动恢复；也不依据磁盘里的 PID 自动重连或重放请求。

需求与边界见 [alignment.md](alignment.md)，接口语义见 [接口草案](docs/agent-interface.md)。
