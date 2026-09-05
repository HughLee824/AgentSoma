# observe 与 AX 树实例

这些是需求讨论样例，来自 2026-09-04 已保存的 iPhone 12 Pro / iOS 26.6 真机数据。用户于 2026-09-05 同意“截图 + 紧凑界面文本”的方向，具体语法与规则尚未定为产品协议，也未实现或重新运行手机测试。

## 从哪个文件看起

| 文件 | 内容 | 来源与处理 |
| --- | --- | --- |
| [observe.compact.example.txt](observe.compact.example.txt) | 已认可紧凑方向的格式样例，具体语法待定 | 根据同一份 40 节点数据手工编排；不是已实现的转换器输出。 |
| [observe.example.json](observe.example.json) | 第一版 observe 返回对象，包含完整 40 个节点，约 13.3 KiB | 从下项真实数据转换；用户指出其过于冗长，保留作字段对照，不作为默认阅读格式。 |
| [spike-observe.json](spike-observe.json) | 当前实验工具保存的完整响应，40 个节点 | 原样复制 `spikes/ios-xctest/evidence/live-20260904T152254Z/004-observe.json`。 |
| [spike-system-alert.json](spike-system-alert.json) | 真实系统通知权限弹窗响应，38 个节点 | 原样复制同一会话的 `006-observe.json`。 |
| [xctest-debug-description.txt](xctest-debug-description.txt) | XCTest 原始调试文本，约 4.1 KiB | 原样复制较早一轮 `evidence/pmd-20260904T150445Z/device/AgentSomaEvidence/fixture-text.tree.txt`。它与上述快照不是同一次采集。 |

三份原样副本都做了逐字节比对。原始 evidence 目录继续按实验设置忽略；这些小型示例方便在需求文档旁查看。示例中的截图路径指向本机已有 PNG，不含会话 token。

## 面向 agent 的紧凑表示提案

用户反馈：逐节点 JSON 即使减少字段，仍不适合 agent 阅读。第一版确实只做了属性选择与字段组织，40 个节点全部保留，未精简容器层级。用户随后同意默认输出截图与紧凑界面文本、采用短元素引用、保留内容与状态、按需读取详细属性，以及限制默认输出长度并明确未展开区域。转换采用确定性规则，无需引入模型或任务规划。用户也已接受动作发出后旧引用失效、下一次按引用操作前重新观察。以下语法、字段取舍和引用解析细节仍是待完善的提案。

[紧凑样例](observe.compact.example.txt) 展示同一个页面的候选阅读密度。它保留按钮、输入框、正文和结果状态，折叠多层空 Other、重复 WebView 包装及滚动条装饰；独立的 Web input 标签在输入框名称中只展示一次。它不是无损格式，源节点 22 的 other / value="2" 等细节未在默认文本中展开。尚未实现通用过滤器，也未验证这种表示对各种 App 的操作效果。

候选规则及边界：

- 一行表达角色、名称及必要的值或状态；已知 enabled=true 等默认状态不重复写。disabled、selected、focused 等会影响理解的状态在数据可取得时保留，未采集不能当作 false。当前样例没有采集 selected / focused。
- 保留阅读内容，不只输出可点击控件；列表项、弹窗、分组等有助于区分相同名称目标的关系不能一律拍平。两个同名按钮不能仅因名称相同而合并。
- 容器只有在不承载独立语义、交互或必要分组时才可折叠。样例的手工取舍不能直接变成对所有 Other / WebView 节点的删除规则；滚动区域仍需可定位。
- 短引用方向已确认，`o4`、`e1`–`e6` 的具体命名仍是样例。样例映射为 e1→10、e2→11、e3→13、e4→15、e5→26、e6→27，数字是原 JSON 的 index。当前 Runner 不支持这些引用。实际实现需要绑定会话、观察与来源节点，并在操作前检查对应关系；不能仅凭 index 重查或盲用旧坐标。已确认动作发出后旧引用失效，下一次按引用操作前需重新观察；动作结果未知时也适用。
- 样例的 `ax_value="Web text"` 原样保留 XCTest 的值，不把它改写成已输入文本或占位符。Fixture 源码显示它在此处是占位文本，但当前 JSON 未单独导出 placeholderValue，通用转换器不能依赖这一额外知识。
- 样例 `source_truncated=false` 仅表示源快照未触及 Runner 的 200 节点上限，不表示紧凑输出无损或取得了 App 的所有内容。本例没有测试屏幕外过滤、遮挡判断或大树的输出预算；不能把 frame 与屏幕相交等同于可见、把 enabled 等同于可点击。
- 大树即使改成文本仍可能过长。已确认限定默认输出长度并标明哪些区域未展开，允许 agent 按需展开节点或子树；具体预算、展开入口与优先规则待讨论，不静默丢弃超限内容。
- 已确认展开详情读取同一份已采集快照，保留观察 ID 与元素引用；获取最新界面需要重新 `observe`。读取旧快照不会恢复已失效的操作引用。展开只能取得本次采集已有的数据，不能补出采集阶段就被截断或未取得的节点；快照不可用时应明确返回，不能用新采集的数据冒充原观察。

截图仍应以图像内容送达 agent。样例只展示配套文本，没有把截图路径或 base64 塞入文本。时间、来源、采集错误等信息仍属于观察契约，最终哪些放在接入层元数据、哪些简写给模型尚未决定。

## 第一版 observe JSON 字段对照

逻辑上返回截图和结构化数据。此处的 JSON 文件用 `screenshot.path` 指向已有图像；这是本地展示方式，尚未决定最终传输协议，也不表示只给 agent 一个路径就完成了图像传递。接入层需要让 agent 实际获得图像内容。

| 字段 | 具体含义 |
| --- | --- |
| `observation_id` | 标记这一次观察。本例用已记录的会话 ID 和请求序号组合得到；不是永久缓存或元素标识。 |
| `session_id` | 设备会话 ID。 |
| `context.target_bundle_id` | agent 选择的目标 App。 |
| `context.foreground_bundle_id` | 本例已知目标 App 的状态为 `runningForeground`，因此可填入该 App；不能确认时应为 null。这不代表独立发现任意前台 App 的功能已经实现。 |
| `screen` | 本例全屏 Application 根节点的逻辑尺寸 390×844，单位为屏幕点。其他方向与界面的尺寸获取尚需产品实现。 |
| `screenshot.width`、`height` | 原始 PNG 的像素尺寸 1170×2532；与屏幕点不同。此例对应 3 倍比例。 |
| `screenshot.capture_completed_at` | 当前代码在截图调用返回后记录的时间，转换为 UTC ISO 8601 字符串；不是硬件精确曝光时间。 |
| `ax.status` | 本例 available，表示成功取得结构；后续协议也要能表达结构获取失败，不能把失败伪装成没有节点。 |
| `ax.scope`、`source_bundle_id` | 结构覆盖的界面和来源 App。本例 app / Fixture；系统弹窗样例来自 SpringBoard，并不把它当作业务 App。 |
| `ax.snapshot_started_at` | 读取 XCTest 快照前记录的时间，与截图时间分别标记。 |
| `ax.truncated` | 是否触发 Runner 的节点数裁剪。当前实验上限 200；本例 40 个，没有截断。false 不保证 App 的所有页面或全部 Web DOM 都存在于 AX 树中。 |
| `ax.nodes` | 带父节点索引的节点数组。遍历顺序和父子关系与实际响应一致；没有过滤空容器、合并重复节点或补写缺失标签。 |

节点字段：

- `index`、`parent`：本次快照内的位置及父节点位置；根节点 parent 为 null。不能直接将 index 当成下一次操作的稳定元素 ID。
- `type`：建议使用可读名称，如 button、text_field、static_text。原响应使用 XCTest 数字枚举，本机 SDK 中分别为 9、49、48。
- `identifier`：App 暴露的 accessibility identifier，可能为空。
- `label`：辅助功能名称，可能为空或不唯一。
- `value`：XCTest 返回的值，保留实际类型及 null；空输入框有时也会返回占位文本，本例 Web input 的 `Web text` 就是占位文本，不能直接视为已输入内容。
- `enabled`：是否启用，不保证当前可见或可点击；本例没有输出 isHittable。
- `frame`：屏幕点坐标中的 x、y、width、height。原数据中的浮点数和屏幕外范围全部保留。

此例对原响应只进行了字段分组/命名、数字类型到名称映射、时间格式转换，以及添加一个示例 observation_id。40 个节点的所有其余属性及父子关系逐项比对一致。默认精简、短引用方向及动作后引用失效已确认；具体裁剪规则、上限、引用语法和解析方式仍待讨论。

## “原始 AX 树”具体指什么

当前路线通过 XCTest 的 `snapshot()` 得到 `XCUIElementSnapshot`。它是含属性和 children 的结构化对象，也提供 `dictionaryRepresentation`；不是由系统直接交给我们一份已经固定格式的 JSON。[Apple 快照说明](https://developer.apple.com/documentation/xcuiautomation/xcuielementsnapshot)

本项目的 `LiveSessionTests.swift` 遍历 children，只取 type、identifier、label、value、enabled、frame，再自行添加 index / parent，生成当前 JSON。它没有保存完整 dictionaryRepresentation 或底层 AX 通信数据，所以不能把这份 JSON 称为未经处理的全部 AX 数据。SDK 还声明了 placeholderValue、selected、hasFocus 等属性，当前节点 JSON 没有导出它们。

现有最接近“直接看 XCTest 输出”的文件是 `app.debugDescription` 的原始文本。节选如下，未改写这一段内容：

```text
              TextField, 0x15d7f7700, {{16.0, 112.7}, {358.0, 34.0}}, identifier: 'input', placeholderValue: 'Test text', value: AgentSoma hello 你好
              Button, 0x15d7f75c0, {{128.0, 162.7}, {134.3, 20.3}}, identifier: 'dismiss', label: 'Dismiss keyboard'
              Button, 0x15d7f7480, {{156.7, 199.0}, {76.7, 20.3}}, identifier: 'increment', label: 'Increment'
              StaticText, 0x15d7f7340, {{162.3, 235.3}, {65.3, 20.3}}, identifier: 'counter', label: 'Count: 0'
```

缩进表示层级；`{{x, y}, {width, height}}` 是边界；`0x...` 是这次调试输出中的对象地址，不是 accessibility identifier 或跨请求稳定句柄。完整文件还保留了 Application、Window、多层 Other、ScrollView、屏幕外列表行，以及查询链。

Apple 明确将 debugDescription 定位为调试输出，不保证其格式可供测试逻辑依赖。因此建议 agent 的结构化输入来自 snapshot 属性，而不是解析这段文本。[Apple 调试文本说明](https://developer.apple.com/documentation/xcuiautomation/xcuielement/debugdescription)
