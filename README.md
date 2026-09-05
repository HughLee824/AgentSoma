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

Runner 使用仓库内的[独立 Xcode 工程](Runner/AgentSomaRunner.xcodeproj/project.pbxproj)，只构建会话测试，不带 Fixture 或固定探针测试，也不需要 XcodeGen。首次使用需在 Xcode 配置自己的开发团队和签名，并让设备信任 Mac、启用 Developer Mode。具体步骤与错误处理见[首次接入](docs/onboarding.md)。以下命令由外部 agent 执行；用户不需要手动操作截图、点击或输入命令。

```sh
.build/debug/agentsoma build-runner --team "$APPLE_TEAM_ID"
# 将结果中的 xctestrun 完整路径用于下面的 SIGNED_XCTESTRUN。
.build/debug/agentsoma devices
.build/debug/agentsoma connect \
  --device "$IOS_UDID" \
  --xctestrun "$SIGNED_XCTESTRUN"

# 使用 connect 实际返回的 session。
.build/debug/agentsoma --session "$SESSION" status
.build/debug/agentsoma --session "$SESSION" apps --query Settings
.build/debug/agentsoma --session "$SESSION" open com.apple.Preferences
.build/debug/agentsoma --session "$SESSION" observe
# agent 读取返回的 PNG；使用实际返回的观察 / 元素引用。
.build/debug/agentsoma --session "$SESSION" inspect o1:e9
# 每次动作使用最新观察中实际取得的引用，完成后再次 observe。
.build/debug/agentsoma --session "$SESSION" tap o1:e9
.build/debug/agentsoma --session "$SESSION" observe
.build/debug/agentsoma --session "$SESSION" disconnect
```

`build-runner` 使用当前选中的 Xcode 构建并验证签名，返回实际 SDK 对应的 `.xctestrun` 路径。每次构建使用独立目录，已有构建可供后续会话复用。`connect` 通过 Xcode 安装并启动该 Runner，在宿主和 Runner 均可响应后返回，agent 不需要单独启动后台服务。每条 CLI 命令结束后，宿主继续持有原 XCTest 会话。会话结束后，宿主释放自己的 xcodebuild/Runner 资源并退出。

当前提供 `build-runner`、`devices`、`connect`、`status`、`apps`、`open`、`observe`、`inspect`、`tap`、`swipe`、`type`、`press`、`disconnect`。`devices` 返回 CoreDevice 已知设备和原生连接状态，connect 检查是否能建立会话；`apps` 查询已安装 App 的名称和 bundle ID，支持 `--query` 筛选，每页最多 50 项，按返回的 `nextOffset` 继续读取。见 [发现接口与完整调用验收](docs/discovery.md)。

`open` 已移除临时 App 白名单；宿主先检查安装状态，再由 Runner 激活已运行的 App，未运行时启动。未安装的 App 在派发前拒绝。`observe` 返回截图路径及紧凑 AX 文本，`inspect` 展开同一缓存快照；动作在设备端确认目标后执行。见 [观察契约](docs/observations.md) 和 [动作接口与验收](docs/actions.md)。

`type oN:eN --mode insert --text ...` 保留现有光标，需要输入框已有键盘焦点；需要聚焦时先 tap、再 observe。`--mode replace` 聚焦并替换全部内容，空字符串表示清空，两种模式都不自动提交。文本源也可选 `--stdin < text.txt`，与 `--text` 互斥，按原文读取 UTF-8 至 EOF；仍限制 4096 字节并拒绝末尾换行。`press oN:eN --key return` 使用已有焦点发送独立 Return，完成后重新 observe 核对效果。`swipe oN:eN --direction up` 的方向表示手指移动方向；坐标点击使用 `tap oN --x X --y Y`，单位为屏幕点。

`tap/swipe` 在输入前检查 App/弹窗及屏幕上下文，并比较整屏与操作区域的截图指纹；通过后直接执行宿主提供的坐标，不再依赖 identifier/label 唯一性。可用 `--max-screen-change`、`--max-region-change` 设置变化比例阈值，用 `--protect oN:eN` 增加最多三个保护区域。明确端点滑动为 `swipe oN --from-x X --from-y Y --to-x X --to-y Y`。变化超限时返回 `not_dispatched` 并要求重新 observe。参数、算法和启发式限制见 [动作前画面校验](docs/screen-guard.md)。

`tap/swipe/type/press` 在全部输入调用结束后自动检测画面稳定：约每 200ms 采样，至少 3 帧的全帧像素 SHA-256 一致且覆盖至少 400ms，才返回 `completed`。结果包含 `execution.inputCompleted`、`stability` 和 `frame.screenshot` 本地路径。5 秒检测预算内未稳定则返回 `unknown` / `frame_stability_timeout`，保留输入事实与最后一帧；调用 agent 先观察，不重发，也不额外猜测“等待 Lark 动画”。当前协议为 `actionVersion=4`、`observationVersion=2`、`screenGuardVersion=1`，已有旧 Runner 需重新构建。

调用 agent 的命令执行工具若提前返回后台任务 ID（例如 `exec_command` 的 `session_id`），必须保留完整返回对象，并通过对应的续读工具（例如 `write_stdin`）取得原命令的退出码和输出。这个 ID 属于命令执行工具，与 AgentSoma 的设备 `session` 不同。不能只打印 `output` 而丢弃任务 ID，也不能用固定 sleep 加重复 `status` 来猜测原命令是否结束。

## 生命周期与输出

- 默认空闲 **30 分钟**；建立连接时可用 `--idle-timeout 60m` 调整，也接受 `s`、`m`、`h`，便于用短时间验收。
- 有效 `open` 和通过本地引用解析的动作请求完成后续期，包括执行结果未知的请求。参数检查或本地引用解析失败不续期。成功的 apps / observe / inspect 也在完成后续期，失败的查询或 inspect 不续期；apps 保留观察引用。
- 已接收、排队或执行中的命令不被空闲回收；`disconnect` 等待已经接收的命令结束，再清理会话。
- `status` 检查 Runner 并返回剩余空闲时间，不续期。当前没有额外内部保活轮询。
- observe / inspect 成功时输出多行文本，其余结果与运行错误为单行 JSON。成功退出码为 0，运行失败为 1；参数语法错误由 ArgumentParser 输出到 stderr 并非零退出。
- `open`、`tap`、`swipe`、`type`、`press` 返回 `completed`、`not_dispatched` 或 `unknown`。Runner 在进入可发送输入的 API 前记录执行阶段，宿主据此区分执行前拒绝与可能已产生影响；缺失事实、连接中断或丢失响应按保守结果处理，不自动重发。

状态目录默认为 `/private/tmp/agentsoma-<uid>`，目录权限 0700；可通过 `AGENTSOMA_STATE_DIR` 设置较短的替代路径。每个会话包含本地 Unix socket、启动配置和诊断文件。设备 token 只保存在宿主内存及 XCTest 子进程环境，不写入配置文件或 CLI 输出。相同状态目录内对设备规范 UDID 使用系统文件锁，拒绝重复占用；锁文件保留，锁本身随持有进程退出而释放。

观察默认最多 60 行、8 KiB，超预算内容明确提示并可 inspect；源采集最多 200 个节点，未采集部分不能从旧快照补取。宿主只缓存最近两次观察和最后一次动作的结果帧。open 或设备动作正常完成、结果 unknown 后旧引用失效；确认目标已变化时同样失效，读取旧快照不恢复引用。动作的稳定帧不生成 AX 或引用，后续按引用操作仍须 observe；独立 observe 的截图与 AX 分开采集，不保证原子一致或持续稳定。

断开或到期后 socket 和观察缓存删除，原 session 不能继续调用。诊断文件暂时保留供开发排查，清理这些文件不负责断开活跃会话。当前不承诺宿主遭 SIGKILL、Mac 重启、物理断线或设备锁屏后的自动恢复；也不依据磁盘里的 PID 自动重连或重放请求。

需求与边界见 [alignment.md](alignment.md)，接口语义见 [接口草案](docs/agent-interface.md)。
