# 设备/App 发现与完整 CLI 调用

设备发现通过 Mac 上的 `xcrun devicectl list devices`，App 发现通过 `devicectl device info apps --include-all-apps`。读取 Apple 工具的 JSON 文件，不解析显示表格，不增加第三方运行工具。Xcode 16 所带工具的本地 `help` 明确将 JSON 文件列为脚本消费接口；本轮字段依据实际设备输出。

## CLI 契约

```sh
agentsoma devices
agentsoma connect --device "$DEVICE_ID" --xctestrun "$SIGNED_XCTESTRUN"
agentsoma --session "$SESSION" apps
agentsoma --session "$SESSION" apps --offset 50
agentsoma --session "$SESSION" apps --query Settings
agentsoma --session "$SESSION" open com.apple.Preferences
agentsoma --session "$SESSION" observe
# agent 读取返回的 PNG，使用本次实际返回的元素引用执行动作，再 observe。
agentsoma --session "$SESSION" disconnect
```

`devices` 无需会话，返回 CoreDevice 已知的设备，并不等于所有设备此刻都能建立会话。`id` 优先使用 UDID，缺失时使用 CoreDevice identifier；它们都可用于 connect。名称、系统版本、平台、设备类型、连接方式、隧道和配对状态只映射原生返回值，缺失字段为 `null`。不推测锁屏或会话就绪状态，也不把曾配对设备排除出列表。

示例节选（设备 ID 为占位值）：

```json
{"ok":true,"result":{"devices":[{"id":"DEVICE_UDID","name":"iPhone 12 Pro","osVersion":"26.6","platform":"iOS","deviceType":"iPhone","connection":{"transport":"wired","tunnelState":"disconnected","pairingState":"paired"}}]}}
```

`apps` 使用会话已确认的规范 UDID，由 Mac 查询安装元数据。每项仅返回 `name` 和 `bundleId`，名称未知为 `null`。按 bundle ID 排序，每页最多 50 项；`--query` 对名称或 bundle ID 做不区分大小写的子串匹配，`--offset` 用于同一查询的后续页。`total` 为匹配总数，末页 `nextOffset` 为 `null`，无匹配返回空数组。字段映射和分页是工程默认值，不是新的用户产品要求。

实际筛选响应的 result：

```json
{"apps":[{"bundleId":"com.apple.Preferences","name":"Settings"}],"nextOffset":null,"offset":0,"total":1}
```

每次 apps 都重新查询安装列表；它不是 AX 观察，也不缓存 App 清单快照。查询之间发生安装或卸载可能改变后续分页位置。成功查询在完成时续期，参数错误、越界或底层查询失败不续期；所有查询均保留已有观察引用。只读查询不会向 Runner 发命令，也不会操作设备 UI。临时原生 JSON 和日志在调用结束后删除；连接预检仍保留在会话诊断目录。

## 打开已安装 App

open 已移除 Fixture/Calculator 白名单。Mac 在派发前重新查询安装列表，按 bundle ID 精确核对。未列出的 App 返回 `app_not_installed`、`outcome=not_dispatched`、`requiresObservation=false`，原引用保留；查询失败同样不能冒充已派发或已完成。

Runner 只检查 bundle ID 格式，封装 XCTest 的 activate/launch、前台状态和执行事实。已运行则 activate，未运行则 launch；open 不隐含安装或重启。启动握手要求 `launchVersion=1`，避免旧白名单 Runner 被当成新版使用。

安装列表不保证某个 App 一定能启动、暴露可用 AX 或接受全部输入方式。若安装检查后设备/App 状态变化，仍由既有执行阶段与三态结果表达，不自动重发，也不扩大兼容性承诺。观察与动作继续沿用 [观察契约](observations.md) 和 [动作契约](actions.md)。

## 验收记录

本轮使用 macOS 15.0.1 / Xcode 16.0 / iPhone 12 Pro、iOS 26.6；源码和真机原始结果位于 git 忽略的 `spikes/ios-xctest/evidence/discovery-cli-20260905-01/`。该目录用于开发验收，不是产品任务历史功能。

本地 `swift test` 的 29 项测试通过，覆盖设备缺失字段和离线状态、格式错误与空列表的区别、分页与名称筛选、精确安装检查、成功/失败查询的续期和引用保留，以及已有生命周期、观察和动作回归。

真机共 26 次独立 CLI 调用、5 次观察，始终复用 Runner PID 8916 / UUID `40CC5186-569E-4602-82A5-9293C30EB44B`：

- 从 devices 返回的 UDID 建立会话；apps 四页分别返回 50、50、50、37 项，合并后与原生 187 项清单一致，无遗漏/重复。Fixture bundle 筛选及混合大小写的 Settings 名称筛选均通过。
- 查询不存在的 App 返回空列表；open 同一 bundle 返回明确的派发前拒绝。两次 status 的 Runner sequence 仅增加一次，证明夹在中间的 apps、拒绝和 inspect 没有发出 Runner 请求。inspect 显示原引用仍 current，随后同一引用点击成功。
- Fixture 的 Count 从 0 变为 1；再次 open 后仍为 1，没有隐含重启。o1/o2 截图与 AX 核对一致。
- 从发现结果打开原白名单外的 Settings，读取 o4 截图后按引用点击 General；o5 的页面标题和截图确认已进入 General。只进行页面导航，没有修改设置值。两个系统页都达到 200 节点源上限，输出如实区分未展开内容和源截断，已采集目标仍能正常校验。
- 持续会话 XCTest 为 1 通过、0 失败、0 跳过。disconnect 收到 shutdown 确认，xcodebuild 正常退出，无强制终止；socket 和观察缓存删除。Mac 宿主 PID 188、xcodebuild PID 194 和设备 Runner 均确认退出。

证据包含 commands.json、o1–o5 的文本/PNG/源节点、原生发现结果、XCTest 摘要与 run.xcresult，以及 verification.json 的断言、源码 SHA256 和清理核对。调用 agent 实际读取了 o1、o2、o4、o5 图片；命令记录脚本仅记录传入的 CLI 调用，不解释任务或选择动作。

## 当前边界

默认发现入口、按会话调用和通用 App 打开已实现。本轮验收时接入仍使用预构建 `--xctestrun`；后续已增加独立 Runner 的 build-runner 命令并验证首次安装，见 [接入说明](onboarding.md)。仍需要本机 Xcode 签名环境。当前结果不证明免 Xcode 部署、完全移除 Runner、物理重连自动恢复或任意 App 的全部操作兼容性；后续仍按已接受的优先级推进。
