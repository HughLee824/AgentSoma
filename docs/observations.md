# 宿主观察与引用验收

2026-09-05 已实现 `observe`、`inspect`、确定性 AX 精简和会话内缓存。本记录保留第 3 阶段的 18 项本地测试及一次原生 CoreDevice 真机证据；同日第 4 阶段已接通按引用点击、滑动、输入与实时目标校验，新增证据见 [动作验收](actions.md)。

## 当前调用

```sh
agentsoma --session "$SESSION" observe
agentsoma --session "$SESSION" inspect o2:e9
agentsoma --session "$SESSION" inspect o2
agentsoma --session "$SESSION" inspect o2 --offset 20
```

`observe` 成功时直接输出多行文本及 PNG 路径；agent 需要用本地读图能力打开 PNG。`inspect` 成功时输出缓存上下文及按需展开的节点属性。失败仍为单行 JSON，退出码为 1。本地 IPC 保留 JSON 结构，CLI 不把逐节点 JSON 作为默认观察输出。

[完整 CLI 输出样例](examples/observe/observe.cli.example.txt) 来自本次 Calculator 的 o4，未经改写。文件里的临时路径随会话关闭已失效；实验副本在下方证据目录。实际采集的部分正文如下：

```text
[e16] scroll_view "Last Expression"
  [e18] text "‎2‎+‎3"
[e19] scroll_view "Edit field"
  [e22] text "‎5"
[e23] key "Delete"
[e24] key "All Clear"
```

显示为 `[e24]` 的节点，其完整引用是该会话的 `o4:e24`。引用只标识已采集的来源节点，不能据此认定设备目标唯一、可点击或仍在原位置。`refs=current` 只表示它尚未被宿主失效；type/press 执行前校验实时 AX 目标，tap/swipe 执行前校验上下文和分区画面。画面相似不延长引用，见 [动作前画面校验](screen-guard.md)。

## 本阶段收敛的实现值

这些是可调整的工程默认值，沿用已确认的产品语义，不代表用户逐项指定了数值。

- 默认观察最多 60 行、8 KiB；长属性在文本中缩短到 160 个字符并显示 `detail_clipped=true`，原值留在缓存。
- 省略无内容、无状态、无 identifier 的普通容器，折叠重复 WebView 包裹与可确认重复的普通容器表示。保留控件、文字、原始 `ax_value`、禁用状态、命名分组；同名控件不合并，有 identifier 时显示以便区分。
- 不依据控件在屏幕内、enabled 或名字推断可见性/可点击性，不把输入框的 AX value 猜成“已输入内容”。屏幕外的已采集节点仍可能出现在文本中。
- 每个原始节点均有观察内引用，包含默认文本折叠掉的节点；`inspect oN` 可读取它们。引用分配和表示规则都在宿主，Runner 没有观察 ID、短引用或缓存策略。
- 只缓存最近两次成功观察。新观察不会修改旧快照；第三次成功观察删除最早的 PNG 和 JSON。有效会话结束或空闲到期时删除观察缓存，诊断文件保持原有清理策略。
- `inspect` 默认每页最多 20 个节点、8 KiB，`--offset` 是所选已采集子树内的节点偏移，下一页命令随输出返回。单个节点的详细 JSON 超过 4 KiB 时，输出指向完整缓存文件的提示。
- 文本预算未展开的数据标明 `unexpanded`，可继续 inspect。Runner 的源采集仍最多 200 节点；`source_truncated=true` 和 `source_missing=true` 表示原快照没有采集到剩余节点，inspect 不能补取。
- PNG 与保留全部已导出节点属性的 snapshot.json 写入会话目录，文件 0600、目录 0700。JSON 不是完整 XCTest dictionaryRepresentation；缓存文件也不独立证明引用当前有效。

## 引用与生命周期

所有操作在宿主工作队列串行执行。`open` 和通过本地引用解析的设备动作调用后端前先标记当前引用为 pending；正常完成或结果 unknown 后失效。明确未发送且没有其他失效原因的错误恢复此前仍有效的引用，参数检查失败不改变引用；发现目标变化时仍须失效。unknown 不重发。

开始一次新观察会使旧引用失效，即使新采集失败也要求重新 observe；成功后仅最新观察拥有 current 引用。旧快照只要仍在缓存就可 inspect，但不会恢复操作资格。已淘汰的快照返回 `observation_unavailable`；未采集的节点返回 `node_not_captured`；旧 session 无法再 inspect。当前动作已使用这些状态，并从原快照构造设备校验所需的目标描述。

成功的 observe / inspect 完成后续期，失败的 inspect 不续期，status 保持不续期。已接收的操作和关闭仍沿用原有串行化与空闲规则。

## 采集事实与限制

薄 Runner 检查 SpringBoard 是否有唯一 Alert；否则采集已经 open 且确认 runningForeground 的目标 App；前台不能确认时返回截图，AX 标记 unavailable、foreground 标记 null。第 4 阶段增加 App 内唯一 Alert 的独立 `appAlert` 范围。唯一系统 Alert 的结构属于 SpringBoard，不能把目标 App 当成该系统界面的前台身份。没有独立发现任意前台 App 的能力，也没有自动选择允许/拒绝权限的动作。

AX 开始/结束时间与截图后的时间分别返回；屏幕点坐标框来自采集 App 的 frame，未知时返回 null，PNG 像素尺寸由 Mac 解码图像验证。截图与 AX **不是原子快照，也不保证界面已稳定**。

本次直接在 open 后采集，o2 Fixture 和 o3 Calculator 的截图拍到了切换动画，AX 已是目标 App 内容。后续独立的 o4 截图显示稳定 Calculator `2+3=5`，与它的 AX 文本一致。保留这组差异作为时序证据；没有给 Runner 增加固定等待或自动重拍策略，调用 agent 可根据截图再 observe。

当前仍需传入新构建、已签名的 `--xctestrun`；旧 Runner 缺少观察版本标记会提示重建。open 仍受探针 Fixture/Calculator 范围限制。自动系统 Alert 采集路径本轮只用历史真实权限 AX 样本验证精简，未再次制造权限弹窗；广泛前台发现与不同系统弹窗覆盖仍未完成。

## 验证记录

环境未变：macOS 15.0.1 / Xcode 16.0 / iOS 26.6、iPhone13,3；没有 WDA、iproxy 或 pymobiledevice3 运行依赖。

- `swift test`：18 项通过，覆盖既有生命周期、真实 Unix IPC、历史 WebView/系统权限 AX 样本、同名目标保留、长字段/200 节点预算、inspect 分页与原属性一致性、旧引用拒绝、未派发保留、unknown 不重放、缓存淘汰和空闲清理。
- 真机 15 次独立 CLI 调用：同一宿主 PID 85837、Runner PID 8814 / UUID `7CBD782D-67DE-4CC2-8983-D8FEA943BCC9`。四次 observe、原快照详情、App 切换后的引用失效、两份缓存上限、旧 session 拒绝全部通过。
- Fixture 37 个源节点，默认文本共 1198 字节（包含元信息和路径）；完整节点属性另存。两次 Calculator 观察各为 42 个节点。
- inspect 前后各一次 status 的 Runner sequence 差为 1，证明中间 inspect 没有请求 Runner；详情读自对应快照。
- 三次有 AX 的 observe 为 0.453–0.800 秒；首次未知前台的 observe 为 1.699 秒；inspect 为 0.015–0.031 秒。这些是单次会话样本，包含进程启动与序列化，不是性能保证。
- disconnect 返回正常；本轮 XCTest 1 通过、0 失败、0 跳过。宿主、xcodebuild 和设备 Runner 均已退出，Unix socket 和观察缓存已删除。

本地证据目录（git 忽略）：`spikes/ios-xctest/evidence/observe-cli-20260905-01/`。其中 commands.json 保留独立调用、退出码和耗时；o1–o4 的 txt/png/json 是关闭前保存的实验副本；verification.json 记录断言及源码 SHA256；xcode-summary.json 与 run.xcresult 记录实际 Runner 结果。这些是开发验收证据，不是 AgentSoma 的任务历史功能。
