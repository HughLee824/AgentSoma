# AgentSoma 最小 agent 接口草案

状态：需求与接口草案，完整协议尚未实现。2026-09-05 已实现 connect、status、open、observe、inspect、tap、swipe、type、disconnect 及会话宿主；生命周期、观察、缓存、引用失效、实时目标校验和动作结果经过本地与真机验证。设备/App 发现仍待开发。当前契约见 [观察验收](observations.md)、[动作验收](actions.md) 和 [使用说明](../README.md)。下文逻辑能力与历史 JSON 示例仍用于解释语义，不代替实际 CLI 参数。

已确认的职责是：用户用自然语言提出任务，外部 agent 调用设备操作，AgentSoma 返回观察或执行结果。测试只是调用场景之一。MVP 接受首次在 Xcode 配置签名。当前讨论的 CLI 面向 agent；日常不要求人手工敲命令，并不排除 agent 执行 CLI。

已确认采用 CLI + 按会话运行的 Mac 宿主进程 + 薄 Runner 的结构，保留将来移除 Runner 的可能。面向 agent 的观察表示、短引用及其有效期放在 Mac 宿主端，Runner 是可替换设备后端的一部分。以下观察 ID、引用与动作结果语义不应直接成为 XCTest Runner 的协议职责。具体职责划分见 [最小结构建议](cli-vs-mcp.md#最小结构建议)。

## 七项逻辑能力

| 能力 | 输入 | 返回与行为 |
| --- | --- | --- |
| `list_devices` | 无 | 可发现的设备 ID、名称、系统版本及能确认的连接状态；未知状态明确标注。 |
| `connect` | `device_id` | 检查运行前提并建立设备会话，返回 `session_id`；锁屏、签名或服务未就绪时给出具体原因。 |
| `disconnect` | `session_id` | 结束该会话并释放 AgentSoma 持有的 Runner 和连接资源。 |
| `list_apps` | `session_id` | 已安装 App 的名称和 bundle ID，供 agent 选择目标。 |
| `open_app` | `session_id`、`bundle_id` | 将目标 App 带到前台；运行中时优先激活，未运行时启动，不把重启隐含在“打开”中。 |
| `observe` | `session_id` | 当前屏幕图像、由可取得的 AX 结构生成的紧凑界面文本、上下文与采集状态。只观察，不替 agent 处理弹窗。 |
| `act` | `session_id`、一个明确动作 | 执行该动作，返回执行结果或错误；一次调用不接收自然语言任务或多步骤计划。 |

连接会话用于复用 Runner。当前宿主已串行处理会话命令，并按规范设备 UDID 拒绝重复占用；这些是设备资源语义，不引入任务、测试用例或工作流对象。

已实现默认空闲 30 分钟自动回收，通过 connect 的 `--idle-timeout` 调整。计时和回收由 Mac 宿主负责；有效会话命令结束后重新计时，已接收 / 执行中的命令不算空闲，status 健康检查不续期。回收后旧会话不可用，观察模块现已实现引用失效与缓存清理。真机以缩短为 8 秒的期限验证，未进行完整 30 分钟等待。详见 [宿主验收](session-host.md)。

## 观察返回什么

用户指出第一版逐节点 JSON 仍过于冗长，不适合 agent 阅读。以下先列出观察涉及的信息，不再把它理解为每次都向模型展开的字段清单。原 JSON 样例保留为数据来源与字段讨论材料。

- **屏幕图像**：图像内容、像素尺寸。
- **坐标信息**：屏幕逻辑尺寸，动作统一使用当前屏幕的点坐标；agent 可结合图像尺寸换算截图位置。
- **界面节点**：底层保留类型、identifier、label、value、enabled、边界和父子关系；默认阅读表示压缩为角色、名称、内容、状态及必要分组，详细属性按需取得。节点序号不充当跨快照稳定 ID。
- **上下文**：已知目标 App、能确认的前台身份、结构所覆盖的 App 或系统弹窗。前台身份无法确认时返回未知，不把目标 App 当作事实上的前台 App。
- **采集情况**：截图与结构各自的时间、结构是否可用及是否截断。截图和结构不宣称为原子快照。

有系统弹窗时，建议观察优先返回该弹窗的结构，并明确它属于系统界面。若结构无法取得而截图可用，仍返回截图，同时标明结构缺失；调用方决定下一步。

图像的传输编码由后续接入协议决定。本接口不要求生成报告、历史列表或自动归档。

已确认默认返回“图像内容 + 紧凑界面文本”：通过确定性规则折叠无语义的容器层，保留可操作控件、阅读内容、状态以及用于区分目标的层级；省略重复字段和每个节点的完整坐标。不引入模型总结，也不根据自然语言任务猜测哪些内容重要。过大的结果采用有界输出、明确的未展开提示与按需读取方式，不能仅截取前若干节点后声称完整。当前实现采用 60 行 / 8 KiB 默认预算，规则与证据见 [观察验收](observations.md)。

已确认详情展开读取同一份已采集快照，保留观察 ID 和元素引用；获取最新界面则重新调用 `observe`，形成新的一轮观察。展开旧快照不会恢复已失效的操作引用。由此，展示层未展开的数据可以继续读取，源采集时未取得的数据不能假装从原快照补出；原快照已不可用时应明确返回不可用，不能在相同观察 ID 下偷偷换成新采集的数据。展开入口 `inspect oN[:eN] --offset N` 已实现，读取最近两次成功观察的缓存。

具体字段与真机数据样例见 [observe 与 AX 树实例](examples/observe/README.md)，另有 [紧凑阅读样例](examples/observe/observe.compact.example.txt)。紧凑样例是根据现有数据手工编排的讨论稿，实际过滤和输出已由宿主实现，另见 [真实 CLI 输出](examples/observe/observe.cli.example.txt)；CLI 采用 `inspect` 展开详情，并返回本地图片路径供 agent 读取。内部图像暂用 JSON 中的 PNG base64，宿主解码、验证尺寸并写入 PNG，不把 base64 展开给 agent。现有实验 JSON 是 Runner 自行序列化的选定属性，不是完整原始 AX 数据。

## 动作的最小集合

| 动作 | 参数语义 |
| --- | --- |
| `tap` | 点击一个点，或一个明确的元素目标。 |
| `swipe` | 在指定元素区域按明确方向滑动。 |
| `type_text` | 向指定输入目标执行明确的插入或替换；不自动发送提交动作。 |

已确认文本输入具有两种语义：`insert` 在输入框当前光标位置输入文本；`replace` 将整个输入框内容替换为指定文本。输入后不会自动附加回车或点击提交按钮，回车或点击“搜索”等提交操作由 agent 单独发出动作。回车动作的具体接口尚未确定。

当前 insert 直接使用已有键盘焦点，不点击而改变光标位置；需要聚焦时由 agent 先 tap、再 observe。replace 聚焦、全选，再覆盖选区或清空。文本当前限制为 4096 UTF-8 字节，拒绝换行/控制键；独立 Return、长文本/stdin 尚未实现。这些是本阶段的工程边界，原语证据与限制见 [动作契约](actions.md)。

CLI 已确认由 agent 显式填写 `--mode`。以下 JSON 仅描述动作语义，不是 CLI 要求提交的参数对象；内部字段组织仍是草案：

```json
{
  "type": "type_text",
  "target": { "ref": "o4:e5" },
  "mode": "replace",
  "text": "北京"
}
```

两种输入都沿用已确认的引用失效规则：动作发出后旧引用失效，后续按引用点击提交按钮前需要重新观察。

元素目标现在使用分开的 `identifier`、`label`、`type` 条件共同精确匹配，并核对源路径、值、状态和位置。没有匹配或存在多个匹配时返回错误，交由 agent 重新观察或使用明确坐标；不使用实验代码中 identifier 同时匹配 label 的行为。

已确认采用短元素引用的方向，让 agent 无需重复填写长 identifier 或坐标。引用绑定观察与来源节点，不是现有 index，也不自动解决匹配歧义或保证目标仍存在；执行前必须能确认目标对应关系，不能确认则拒绝。宿主引用生成、解析、失效，以及后端实时目标定位均已接入动作并通过验收；发现目标变化会要求重新观察。

已确认的 v0.1 引用规则：一次可能改变界面的动作已发送后，旧引用失效；下一次按引用操作前，由 agent 再观察。即使是连续点击两个按钮，中间也需要观察。动作结果为 unknown 时同样失效，因为动作可能已经产生影响；仍须检查 App、系统弹窗和目标对应关系，因为界面也可能自行变化。

当前配套实现：仅最新一次观察的引用可用于动作；确认在发送前拒绝且无其他失效原因时保留引用。读取同一观察的详情已确认为只读展开，既不因读取而改变引用的有效性，也不恢复已失效引用。发现目标已变化时，即使未派发也会拒绝并使引用失效。

目标同时注明它属于当前目标 App 还是系统弹窗。系统权限弹窗沿用观察和点击能力；允许或拒绝由 agent 明确选择。

例子：agent 从系统弹窗快照看到拒绝按钮后，发送一个结构化动作；这里没有“帮我处理权限”这样的业务指令。

```json
{
  "session_id": "example-session",
  "action": {
    "type": "tap",
    "scope": "system_alert",
    "target": {
      "element": { "type": "button", "label": "Don’t Allow" }
    }
  }
}
```

当前 CLI 已独立验证引用点击、竖向滑动、现有光标位置插入、Unicode 完整替换和清空；具体受控原生/WebView 证据见 [动作验收](actions.md)。其他手势或系统按键可在具体使用场景提出需求后补充，不在本草案中推定为已实现。

## 动作结果的含义

已确认 `act` 使用下列三种执行结果；它们描述设备动作的执行情况，界面结果由 agent 再观察。当前 open/tap/swipe/type 已返回请求 ID、session、ok、outcome 及 result 或 error，具体 JSON 示例见 [动作结果](actions.md#执行结果)。

| `outcome` | 含义 | 例子 |
| --- | --- | --- |
| `completed` | 底层动作调用正常完成。它不等于用户目标达成。 | 点击返回成功；登录是否成功仍需 agent 再观察。 |
| `not_dispatched` | 能确认在输入事件发送之前已拒绝执行。 | 目标不唯一、参数无效、会话未建立。 |
| `unknown` | 无法确认动作的最终执行情况，可能已经产生全部或部分效果。 | 发送点击后连接断开，或聚焦已完成但后续输入失败。 |

返回对应的请求 ID、必要的错误码和原因。请求 ID 用于关联请求与结果，不自动构成去重或“恰好执行一次”的保证。

已确认不自动重发结果未知的动作，由 agent 重新观察后决定下一步。这一约束来自真机实验：客户端收到零字节时，点击实际上已经执行。可确认的预检失败才归入 `not_dispatched`，不能把所有异常一概说成未执行。

当前动作只返回执行结果，由 agent 显式调用 `observe` 获取下一次观察。截图采集时机由调用方控制；没有等待业务目标成功或连续执行步骤的策略。

## Agent 接入方式对比

用户已接受由 agent 调用 CLI 作为首版入口，并要求将 daemon 是否必要作为独立问题分析。[CLI 与本地 MCP 对比](cli-vs-mcp.md) 记录了调用契约、图片读取、会话状态和安装维护的取舍。前述七项是逻辑能力；直接动词与显式会话的 CLI 组织已获接受，下方记录具体形式与尚未完成的参数细节。

CLI 当前输出方式是：`observe` 返回紧凑文本与本次 PNG 的路径，agent 再用本地读图能力获取截图；只读到路径还不算取得图像内容。动作返回已确认的三态结果，详情展开读取同一份快照。CLI 调用方式不意味着由人手工操作，也不意味着每次命令都重启 Runner。

MCP 的原生图像结果、工具发现和结构化参数仍是可比较的优势；本地 stdio 本身只要求客户端启动一个子进程，不强制 HTTP、OAuth 或系统开机常驻。[stdio 规范](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports#stdio)、[工具结果规范](https://modelcontextprotocol.io/specification/2025-11-25/server/tools#tool-result)

最小 Swift CLI 现已通过本地 Unix IPC 复用按会话运行的宿主及原 Runner；两种进程角色来自同一个可执行文件。宿主管理命令串行化、设备会话和空闲回收，快照、引用及失效规则现已实现。Runner 保留必要的请求认证、参数检查、目标定位与底层执行状态，不维护面向 agent 的引用协议。详见 [职责划分](cli-vs-mcp.md#最小结构建议) 和 [宿主验收](session-host.md)。

已确认的依赖原则是尽量少依赖第三方工具，设备通信采用 CoreDevice 原生 IP 通道。`iproxy`、`pymobiledevice3` 等实验工具没有进入产品运行依赖。Runner 绑定本次发现的具体 IPv6 地址，Apple xcodebuild 持有 XCTest 会话；连接、显式断开和空闲回收已有证据，物理断线及异常恢复仍待实现。首版继续接受 Xcode 签名环境。详见 [原生直连报告](../spikes/ios-xctest/NATIVE.md) 与 [依赖原则](cli-vs-mcp.md#coredevice-直连与依赖原则)。

## CLI 调用形式提案

用户已接受以 `agentsoma` 的直接动词子命令和显式 `--session` 组织调用，以及下方 `inspect`、`type --mode/--text` 和 `--idle-timeout` 的形式。完整协议仍未实现；尖括号内容需要替换，`s1`、`o4:e2` 等是假定返回的会话和观察引用，不代表已确定 ID 生成规则或本轮设备结果。

七项逻辑能力映射成直接的 CLI 子命令：设备发现建议用 `devices`，App 发现建议用 `apps`；已展示并接受的调用使用 `connect`、`open`、`observe`、`tap`、`type`、`inspect` 与 `disconnect`，滑动命令建议用 `swipe`。会话参数统一用 `--session`，在命令中显式选择会话。

```sh
agentsoma devices
agentsoma connect --device <device-id>        # 假设返回 session=s1；默认空闲 30 分钟
agentsoma --session s1 apps
agentsoma --session s1 open <bundle-id>
agentsoma --session s1 observe               # 假设返回 observation=o4 和元素引用
# agent 使用本地读图能力读取 observe 返回的截图路径，再决定动作
agentsoma --session s1 tap o4:e2
agentsoma --session s1 observe               # 点击后重新观察，获得新的引用
agentsoma --session s1 disconnect
```

已接受的配套入口如下，均沿用已有能力而非增加任务层功能：

| 命令示意 | 语义 |
| --- | --- |
| `agentsoma --session s1 inspect o4:e2` | 按需查看 o4 中这个节点的详细属性及相关已采集结构；不刷新设备或恢复失效引用。 |
| `agentsoma --session s1 type o5:e5 --mode replace --text '北京'` | 使用新观察中的字段引用执行整段替换；`--mode insert` 表示在当前光标处插入。两者都不自动提交。 |
| `agentsoma connect --device <device-id> --idle-timeout 60m` | 为建立的会话调整空闲回收时长；未指定时采用已确认的 30 分钟默认值。 |

`observe` 的默认输出继续采用紧凑文本和图片文件路径；动作输出保留请求关联与 completed / not_dispatched / unknown 语义。截图进入视觉上下文需要 agent 读取图片。坐标现使用 `tap oN --x X --y Y`（屏幕点），滑动使用 `swipe oN:eN --direction up|down|left|right`；长文本/stdin 尚未展开，具体调用见 [动作接口](actions.md)。

## 证据与后续实现的区别

已有实验验证了 Runner 长驻、动态指令、截图与有界界面结构、点击、双语输入、滑动、跨 App 操作、系统通知权限弹窗，以及丢失响应后的结果核对。详见 [持续会话](../spikes/ios-xctest/LIVE.md) 和 [扩展验证](../spikes/ios-xctest/EXTENDED.md)。

本草案不是对现有 spike API 的直接改名。当前 open 激活运行中的 App；open 和设备动作均根据 Runner 执行阶段提供三态结果，缺失或矛盾的事实保守归为 unknown。观察已整合可确认的已打开 App、唯一 App/SpringBoard Alert 及未知前台时的截图；动作会检查对应上下文与实时目标。设备/App 发现仍待实现，独立的未知前台身份识别尚未解决，应如实暴露限制。

首版 agent 入口为 CLI，最小 Swift 宿主已使用 Foundation 进程管理、Unix 域套接字与 JSON、ArgumentParser 落地；CoreDevice 直连及生命周期已在当前环境验证。自有薄 XCTest Runner 是当前设备后端。宿主观察、引用、动作与目标校验已通过；接下来完成发现入口、移除探针 App 白名单及完整调用验收，见 [v0.1 实现计划](v0.1-plan.md)。
