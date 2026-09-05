# CLI 与本地 MCP 接入对比

状态：需求与架构对比，2026-09-05。用户已接受 CLI + 按会话运行的 Mac 宿主进程 + 薄 Runner 的结构、Swift 技术栈及空闲回收规则。CoreDevice 原生直连、CLI / 宿主 IPC / 生命周期、观察与引用、设备动作与实时目标校验现已通过验证。见 [动作验收](actions.md)、[观察验收](observations.md) 和 [宿主验收](session-host.md)。

比较前提是本机运行的 Codex / Claude Code 操作同一台 Mac 连接的 iPhone。MCP 对照方案是本地 stdio，不是远程 HTTP 服务。后端沿用自有 XCTest Runner 的已有实验作为证据，但不以这份比较代替生产后端选型。

使用关系已明确：人用自然语言提出任务，agent 执行 AgentSoma CLI 命令，AgentSoma 观察和操作设备。“人不需要敲 CLI”不排除“agent 使用 CLI”。两种接入方式的比较不要求改变这项人机分工。

## 判断

已确认 CLI 作为首版入口。当前目标调用方已有本机命令执行能力，CLI 可复用这条路径，省去 MCP 注册与协议接入层。代价主要是图片要由 agent 另行读取，以及连续命令之间的会话与引用状态必须有明确归属。

MCP 的实际优势是工具发现、结构化参数和原生图片结果，不是提供更强的 iPhone 控制能力。stdio MCP 也可以只是客户端启动的一个本地子进程，不应把 HTTP、OAuth、云端部署或系统开机常驻算作它的必需成本。[MCP stdio](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports#stdio)

## 对照

| 维度 | Agent 调用 CLI | 本地 stdio MCP |
| --- | --- | --- |
| 安装与接入 | 安装程序，让 agent 的命令工具能找到它；通过帮助或简短使用说明介绍入口。 | 同样需要安装程序，并在目标客户端注册 MCP 配置。 |
| 调用契约 | 命令、参数、stdin、stdout 和退出码；需要稳定的机器输出及长文本输入方式。 | 工具名称、参数 schema、工具结果；SDK 可处理协议初始化与消息编解码。 |
| Agent 如何发现能力 | 依靠 `--help` 或按需使用说明。 | 客户端通过 MCP 工具列表和参数 schema 发现能力。 |
| 截图进入模型上下文 | 保存 PNG 并返回路径，agent 再调用本地读图工具。stdout 中的路径或 base64 不自动成为视觉输入。 | 工具结果可同时包含图片内容和紧凑文本。 |
| 连续命令的状态 | CLI 进程退出后，快照、引用和会话身份需要保存在文件、设备 Runner 或宿主服务等位置。 | 一个服务进程中保存状态较直接；各客户端分别启动的进程仍不自动构成全局设备协调。 |
| 热调用 | 每次有命令进程启动成本，但可以复用已运行的 Runner。 | 已连接服务可接收连续请求。两种入口的 iPhone 动作成本相同来源，尚无端到端对照基准。 |
| 排查与复现 | 可直接运行同一条命令，检查退出码和输出文件。 | 可通过客户端或 MCP 调试工具复现，需同时检查协议与设备层。 |
| 上下文开销 | 有使用说明、命令输出和图片读取调用的开销。 | 有工具发现和结果内容的开销，取决于客户端加载策略。两者均可输出同一份紧凑界面文本，不能预先断言哪种必然更省 token。 |

MCP 的工具结果支持文本与图片内容。[MCP 工具结果](https://modelcontextprotocol.io/specification/2025-11-25/server/tools#tool-result) Claude Code 的 Bash 可执行命令，Read 可将本地 PNG 等作为视觉内容返回。[Claude Code 工具说明](https://code.claude.com/docs/en/tools-reference#read-tool-behavior) 当前 Codex 会话也提供本机命令与 `view_image` 能力；这是本次环境事实，不是对所有远程或受限客户端的承诺。

选择 CLI 后，已确认的观察与动作语义仍可成立：`observe` 输出紧凑文本和本次截图文件引用，agent 读取该图片后形成完整观察；详情展开读取同一份快照；动作输出明确的 completed / not_dispatched / unknown。进程退出码不能代替动作是否发出的语义判断。会话临时文件服务于观察和命令调用，不构成任务历史或报告功能。

## 现有代码已经证明什么

[live.py](../spikes/ios-xctest/live.py) 已经具有 CLI 入口：

- `start` 启动 `iproxy` 与 `xcodebuild`，保存连接信息和 token，并一直等待测试会话结束。
- `call` 是一次独立命令：读取会话文件、建立一条 TCP 连接、发出一个请求、接收结果后退出。
- 真机实验中 32 次请求复用了同一 Runner 会话 UUID 与 PID。[持续会话证据](../spikes/ios-xctest/LIVE.md)

因此，短命 CLI 进程可以服务于持久设备会话。当前证明不是“没有持续运行的进程”：`start`、`iproxy`、`xcodebuild` 和 iPhone Runner 在会话期间持续存活。这是早期 Python 探针的范围；后续 Swift CLI 已实现紧凑文本、短引用解析和跨命令失效规则，见 [观察验收](observations.md)。

这里的 `iproxy` 是历史实验的端口转发工具，不是产品必须继承的依赖。2026-09-05 新的 Swift 探针已经绕过它，经 CoreDevice 原生 IP 访问同一个薄 Runner，7 次独立调用复用会话并正常结束。[原生直连证据](../spikes/ios-xctest/NATIVE.md)

已有一次已安装且开发服务就绪的启动样本为 5.93 秒。该数据说明不能把“每次运行一个 CLI 命令”设计成“每次重启整个 XCTest 会话”；它不是 CLI 与 MCP 的性能对照。现有 hostMs 计时也不包含 CLI 解释器启动、模型思考或后续读图调用。

## CoreDevice 直连与依赖原则

用户已确认尽量少依赖第三方工具。优先使用 Apple 提供的设备工具、系统网络能力与自有 Runner；不把 spike 使用过的 `iproxy`、`pymobiledevice3` 等自动列为产品运行依赖。该原则是减少必要依赖，不是已经证明整个产品可以零第三方依赖。

在自有 XCTest Runner 候选架构下，设备通信优先经 CoreDevice 原生 IP 通道到达 iPhone Runner；CLI 和设备通道之间的产品逻辑放在按会话运行的 Mac 宿主进程中。这与 CoreDevice 直连兼容：本地 IPC 不增加 USB 端口转发工具。Runner 的启动和 XCTest 会话控制仍是独立职责，当前原生实验基线是 `xcodebuild`。

Apple 文档确认 Xcode 15 起通过网络接口与 USB 连接的设备通信。[Apple TN3158](https://developer.apple.com/documentation/technotes/tn3158-resolving-xcode-15-device-connection-issues) 作为实现参考，gstack 的源码通过 `devicectl device info details --json-output` 获取 CoreDevice IPv6 地址，再连接设备自定义服务端口；其代码还单独处理通道保活。这支持直连方向，但不是我们当前 macOS 15 / Xcode 16 环境的实测结论，也不意味着引入该项目。[地址发现与保活源码](https://github.com/garrytan/gstack/blob/main/ios-qa/daemon/src/devicectl.ts)、[直连请求源码](https://github.com/garrytan/gstack/blob/main/ios-qa/daemon/src/tunnel-bootstrap.ts)

早期 CoreDevice tunnel + RSD 访问仍由 `pymobiledevice3` 辅助建立通道。[早期实验](../spikes/ios-direct/README.md) 新验证直接使用 Apple `devicectl` JSON 发现 IPv6 地址，通过环境变量让 [Runner](../Runner/LiveSessionTests.swift) 仅绑定这个具体地址，并保留 token 认证。Swift 原生客户端已完成截图、AX 与点击闭环，约 60 秒命令间隔后仍使用同一 Runner，显式结束后本轮进程退出，XCTest 1 项通过、0 失败。[本机实测](../spikes/ios-xctest/NATIVE.md)

这轮没有引入第三方转发工具或额外保活轮询；xcodebuild 持续持有 XCTest 管理会话。该通信探针本身不证明产品空闲策略或异常恢复；后续宿主已单独验证缩短为 8 秒的回收策略，默认值为 30 分钟。CoreDevice 地址在预检与启动之间曾变化，建立新会话时必须重新发现地址。

## daemon 是另一项决定

这里的 daemon 指额外编写的 AgentSoma 宿主服务，而不是把所有持续存活的设备辅助进程都统称为 daemon。CLI 与 MCP 是调用入口；daemon 回答设备通道和状态由谁持有。

| CLI 内部候选 | 适用理由 | 需要承担的工作 |
| --- | --- | --- |
| 每次 CLI 调用运行宿主逻辑，配合会话文件访问设备后端 | 可能无需增加 AgentSoma 后台进程，仍能保持 Runner 薄。 | 通过文件协调跨命令状态、互斥和失效规则，并管理设备辅助进程；不能把这些职责转移到 Runner 来简化宿主。 |
| CLI 访问按需启动的本地 daemon | 集中持有通道、快照与引用状态，协调命令和资源释放。 | 增加本地 IPC、服务启动/退出及故障处理。可采用会话期间运行，不必开机常驻。 |

两种结构都可向 agent 暴露相同 CLI。持久会话是已确认需求，但尚不足以证明必须有独立 daemon；文件也能持有快照，当前 Runner 能接收多条独立连接。反过来，取消专用 daemon 并不会取消底层服务所需的持续进程。

当前决定：首版使用 CLI 与按会话运行的 Mac 宿主进程，保持设备会话复用，优先 CoreDevice 直连并尽量少依赖第三方工具；Runner 尽量薄且可被替换。设备通信、宿主观察与动作、设备/App 发现与完整调用验收均已完成，见 [验收结果](discovery.md)。发现与安装检查留在 Mac，Runner 保持原语职责。

### 最小结构建议

用户指出，将观察引用及其失效规则放入 Runner 会让它变重、提高未来移除它的成本。先前“由 Runner 管引用以减少宿主进程”的建议因此撤回。当前优先确定的是宿主与设备后端的边界，后台进程数量服从这个边界。

已确认结构为：`Agent → CLI → Mac 上按会话运行的宿主进程 → 设备后端`。当前后端由 Mac 端的 XCTest 适配代码、CoreDevice 通道和薄 Runner 组成。宿主与 CLI 已由同一个 Swift 程序提供，通过 Unix 域套接字传递版本化 JSON 行；启动就绪、跨命令复用、设备互斥及生命周期已验证。

| 职责 | 已确认的归属 |
| --- | --- |
| CLI 参数、面向 agent 的输出契约 | Mac 宿主端。 |
| AX 精简、观察 ID、短引用、快照缓存与详情展开 | Mac 宿主端；Runner 只返回采集到的结构及必要元数据。 |
| 引用有效性、同一设备的命令串行化、动作结果归类 | Mac 宿主端；根据后端提供的执行事实判断，不能凭宿主异常断言动作未派发。 |
| 设备通道与 XCTest 会话的启动、维持和释放 | Mac 端的后端适配代码；复用 Apple 工具与通道。 |
| 截图、AX 采集与序列化、明确的输入及 App 操作 | 薄 Runner 封装必要的 XCTest 调用，返回数据、执行阶段和底层错误。 |
| 请求认证、参数检查、执行所需的元素定位与校验 | Runner 保留必要的设备端机制；不理解供 agent 使用的短引用、产品观察 ID 或缓存规则。 |

薄 Runner 不等于完全无状态：请求关联、后端实例身份、XCTest 所需的线程/执行顺序以及一次调用所需的临时状态可以保留。具体定位与执行仍须在后端检查目标是否存在、是否唯一及调用前提；将引用管理移到宿主不能使旧坐标或旧元素自动变得可靠。

动作失效的宿主侧实现：在同一设备的串行临界区内，先校验并解析引用，将它置于不可复用的待定状态，再向后端派发。动作已派发或结果未知时旧引用失效；只有能确认未派发且没有其他失效原因时才解除待定状态。宿主进程重启后不继承旧引用的有效性，也不自动重放未完成请求。这样无需 Runner 实现面向 agent 的引用协议，仍能覆盖“点击已执行但调用方未收到响应”的情况。当前 open/tap/swipe/type/press 已接入此流程；Runner 校验来源路径和目标属性并返回执行事实。歧义拒绝保留引用、目标变化使引用失效和 unknown 不重发均有验证，见 [动作契约](actions.md)。

按会话运行的宿主进程有利于集中管理这些跨命令状态。每次 CLI 读写文件并加锁也可实现同一边界，因此薄 Runner 不在逻辑上强制 daemon；选择宿主进程来自状态归属与实现复杂度的取舍，不只来自通道保活。宿主进程仍只提供设备观察、动作及资源管理，任务规划和恢复决策由调用 agent 负责。

将来若原生设备能力足以替换 XCTest 后端，应尽量只替换 Mac 端的适配代码并移除 Runner；CLI、观察表示和引用规则保留在宿主。这是可替换性目标，不是当前系统已经支持无 Runner 的能力承诺。实现只需围绕现有必要原语建立窄边界，不预先建设多后端插件系统。

通信验证仅为 Runner 增加具体 IPv6 监听地址。后续宿主实现新增了 Runner 的宿主管理模式，禁用该模式下的实验固定上限；观察、引用或空闲策略没有移入 Runner。正常断开与空闲清理已单独验证，异常恢复仍是后续工作。

### 会话生命周期提案

以下将已确认的按会话运行方向具体化。用户已确认默认空闲 30 分钟自动回收、允许调整，并接受有效命令续期、执行中的命令不算空闲、内部保活不续期及回收后重新连接和观察的规则。逻辑操作名称沿用接口草案，不代表最终 CLI 语法。

1. **连接。** Agent 发出 `connect`，CLI 按需启动宿主进程。宿主建立设备后端会话，确认能够接收请求后返回会话标识；创建进程本身不等于连接成功。正常使用不要求人单独打开终端启动 daemon。
2. **复用。** `observe`、`act` 等独立 CLI 调用通过会话标识访问原宿主与设备后端。一次 CLI 调用退出只代表该次调用结束，不结束设备会话；命令间隔期间无需重复启动 Runner。
3. **正常结束。** Agent 发出 `disconnect` 后，宿主停止接收该会话的新动作，处理已有请求的结束状态，再释放本会话持有的后端与通道资源。设备会话结束且请求处理完毕后宿主退出；无法确认完成的动作仍按 unknown 处理，不能把清理成功当作动作完成的证据。
4. **宿主异常退出。** 旧引用失效，未确认的动作不自动重发。重建连接后由 agent 重新观察；不能只凭磁盘上残留的快照或进程号认定旧会话仍有效。具体异常资源清理实现仍待确定。
5. **空闲回收。** 已确认加入自动回收，并采用较长空闲时间。达到空闲期限后，由宿主结束设备会话并释放其持有的资源；没有会话和待处理请求时退出。空闲策略由 Mac 宿主管理，Runner 不承担这项产品规则。

已确认空闲回收默认为 **30 分钟**，允许调整；具体配置入口随 CLI 设计确定。显式 `disconnect` 仍可提前结束会话。计时规则及配套实现约束如下：

- 从连接就绪、或上一条有效会话命令处理结束时开始计时。会话中有已接收但未处理完的命令时不算空闲；命令完成后重新计时。单条命令的执行超时是另一项机制，不能用空闲回收中断执行中的动作。
- Agent 发出的有效会话请求可以续期，包括观察、动作与详情读取。宿主内部的通道保活、健康检查不续期，否则遗留会话可能永远无法回收。
- 回收与新请求接收由宿主统一协调：新请求已被接收则正常处理；会话已开始回收则拒绝新动作。回收后旧会话与旧引用失效，调用方重新连接、重新观察；不自动重连并重发旧动作。

Runner spike 的固定 900 秒上限仍用于独立探针；CLI 启动 Runner 时指定由宿主管理生命周期，不再受到它限制。宿主默认 1800 秒，通过 --idle-timeout 调整。8 秒受控真机测试已验证动作续期、健康检查不续期与正常回收，没有等待完整 30 分钟。

## 宿主实现技术提案

用户已确认 Mac 端采用 Swift：CLI 与按会话运行的宿主由同一个程序提供，使用 Foundation `Process`、Unix 域套接字与 JSON，以及 Swift ArgumentParser。最小实现已在本机 Swift 6.0 编译和验收，ArgumentParser 锁定 1.5.0，本地消息采用一连接一请求 / 响应的 JSON 行。

| 部分 | 已确认的实现方向 |
| --- | --- |
| CLI 与按会话运行的宿主进程 | 同一个 Swift 可执行程序提供两种运行入口；产品状态与设备后端适配代码留在 Mac。 |
| 参数解析与帮助 | Swift 官方的 ArgumentParser 库，已锁定 1.5.0 并由当前 Swift 6.0 工具链编译；它是源码构建依赖，不是用户需单独安装的命令行工具。 |
| 子进程管理 | Foundation `Process` 管理本会话的 Apple 工具进程，处理参数、输出和退出状态。 |
| CLI 到宿主的本地通信 | Unix 域套接字，一次连接传递一条版本化 JSON 行请求及响应，校验会话与请求 ID；已验证拒绝失效会话。 |
| 宿主到设备的通信 | CoreDevice 原生 IP 通道，通过系统 Network.framework 访问薄 Runner；地址发现、具体地址监听、正常会话通信、断开和空闲回收均已通过本机真机验证。 |
| iPhone Runner | 继续以 Swift + XCTest 封装必要设备原语；产品核心不依赖 XCTest 对象类型或 Runner 的内部状态。 |

只读检查确认本机编译器为 Apple Swift 6.0，目标为 `arm64-apple-macosx15.0`。Apple 文档中 Foundation `Process` 可启动并监控子进程，Network 的 `NWEndpoint.unix(path:)` 支持 Unix 域路径端点；Swift 官方介绍了 ArgumentParser 的子命令、参数和帮助能力。这些支持选型，但不是已经验证了后台进程存活、IPC 或 CoreDevice 到 Runner 的完整链路。[Process](https://developer.apple.com/documentation/foundation/process)、[Unix 端点](https://developer.apple.com/documentation/network/nwendpoint/unix%28path%3A%29)、[ArgumentParser](https://www.swift.org/blog/argument-parser/)

其后 Swift 探针实测 Foundation `Process` 管理 xcodebuild，以及 Network.framework 到 CoreDevice Runner 的通信。再后的最小 CLI 实现已验证后台宿主、本地 Unix IPC 与 ArgumentParser 接入；两类证据区分见 [宿主验收](session-host.md)。

依赖策略继续区分系统能力、代码库依赖和用户需安装的外部工具。当前方案不把 Python、Node、iproxy 或 pymobiledevice3 列为产品运行前提；v0.1 已接受的 Xcode、签名与 Apple 设备工具要求仍保留。跨平台宿主与完整免 Xcode 安装均不由本次语言选型承诺。后续工作顺序见 [v0.1 实现计划](v0.1-plan.md)。

独立 Runner 工程现已纳入仓库，build-runner 直接使用 Apple 构建和签名工具；正式接入无需 XcodeGen，也不构建 Fixture 或固定探针测试。构建与首次安装证据见 [首次接入](onboarding.md)。
