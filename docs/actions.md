# 设备动作与引用校验

本阶段提供按引用的点击、滑动、光标插入和整段替换，以及基于当前观察的点坐标点击。用户或调用 agent 负责选择动作并观察结果；AgentSoma 不解释自然语言任务。

## CLI 形式

下面的会话和引用需要替换为实际返回值，每次派发动作后重新 observe。

```sh
agentsoma --session "$SESSION" tap o4:e10
agentsoma --session "$SESSION" swipe o5:e18 --direction up
agentsoma --session "$SESSION" type o6:e8 --mode insert --text '北京'
agentsoma --session "$SESSION" type o7:e8 --mode replace --text '完整的新内容'
agentsoma --session "$SESSION" type o8:e8 --mode replace --text ''
agentsoma --session "$SESSION" tap o9 --x 100 --y 200
```

- tap 元素用完整 `oN:eN`。点坐标形式用 `oN --x --y`，单位为屏幕点；不是 PNG 像素，不能同时指定元素引用。点击范围限制在当前已确认的 App 或弹窗内。
- swipe 的 up/down/left/right 描述手指移动方向，调用 XCTest 的对应手势，当前没有自定义速度或距离参数。
- insert 直接向指定输入框发送文字，保留已有光标位置，不额外点击字段。它需要现有键盘焦点；需要聚焦时由 agent 先 tap、再 observe。公开 hasFocus 在本设备中不反映键盘焦点，不能据此预检。
- replace 聚焦输入框后发送 Command-A，非空文本直接覆盖选区；空文本通过 `typeText(XCUIKeyboardKey.delete.rawValue)` 删除选区。没有按 AX value 长度连续退格，也没有自动 Return 或点击提交。
- 当前文本上限是 4096 UTF-8 字节，拒绝换行及控制键；insert 不接受空字符串，replace 空字符串表示清空。这是本阶段的工程边界，多行文本/stdin 和独立按键接口尚未展开。

## 宿主与 Runner 的职责

宿主解析参数、验证会话与当前引用，从原快照构造目标路径。路径包含来源节点和祖先的类型、identifier、label、value、enabled、frame，以及每层在父节点内的位置；不向 Runner 发送面向 agent 的观察 ID 或短引用。

这些检查与动作在同一个宿主串行队列执行。两个并发 CLI 命令即使使用同一份当前引用，第一个动作完成后，第二个在解析目标时仍会因引用失效而被拒绝。

薄 Runner 在发送输入前检查：

1. 对应的目标 App 身份与前台状态；SpringBoard Alert 和 App 内 Alert 的存在与数量必须符合观察时的范围。
2. 当前 AX 中的目标路径和每层属性；frame 允许最多 0.5 点的浮点变化。位置、名称或值等变化会要求重新观察，不盲用旧序号或旧坐标。
3. 元素按 type、identifier、label 分别精确匹配并且唯一，不使用早期 matching(identifier:) 同时匹配 identifier/label 的含混行为。同名同标识按钮不会通过选择第一个来消除歧义。
4. 目标仍启用且 isHittable。输入目标必须是 text field、secure text field、text view 或 search field。

App 内唯一 Alert 现在单独作为 `scope=appAlert` 采集，SpringBoard Alert 使用 `scope=systemAlert`。原来没有弹窗的观察不会被用于点击后来出现的弹窗。

Runner 没有缓存、短引用、续期计时或任务策略。它只处理当前请求的验证与 XCTest 调用，并返回执行事实。它也不等待业务状态成功或自动重拍；截图与 AX 的非原子采集限制继续成立。

## 执行结果

成功及错误均为单行 JSON，并保留请求 ID 和 session。

```json
{"id":"example-request","session":"example-session","ok":true,"outcome":"completed","result":{"kind":"tap"}}
```

| outcome | 判定 | 引用处理 |
| --- | --- | --- |
| completed | 本动作的 XCTest 调用正常返回；不等于业务目标达成 | 旧引用失效，agent 再 observe |
| not_dispatched | 参数、引用或设备目标校验在任何输入 API 调用前拒绝 | 无其他失效原因时保留；若已发现目标或上下文变化则失效 |
| unknown | 已进入可能发送输入的 API 后出错、缺失/矛盾的执行事实，或丢失响应 | 旧引用失效；不重发，agent 先 observe |

每次调用可能发送输入的 API 前，Runner 标记 execution.started；任一步骤记录 XCTest 错误就停止，不再继续聚焦后的选区/删除/输入等剩余步骤。只有全部调用正常结束才返回 completed。App 打开也沿用该事实协议。

XCTest 的命令错误经 Runner 转成响应；不再把已经返回给调用方的正常运行时错误一并算作 Runner 整个持续会话的 XCTest 失败。会话外的测试断言和异常结束仍由 XCTest 记录。

无焦点的 typeText 本轮确实发生了 XCTest 内部重试，最终没有写入文字。AgentSoma 的宿主与 Runner 不重新调用结果未知的动作，但单次调用不构成 Apple 内部严格只发送一次底层事件的保证。请求 ID 同样不是去重承诺。

## 验证边界

原始输入探针和修正经过见 [输入原语记录](../spikes/ios-xctest/INPUT.md)。最初“全选、Delete、再输入”的探针没有单独断言清空，非空输入覆盖选区掩盖了 `typeKey(.delete)` 在本设备上不删除选区的问题。现已改为文本删除字符，并在固定测试中加入删除后的即时断言。

当前仍使用预构建且签名的 Runner，open 仍限于探针 Fixture/Calculator；发现设备/App 和移除该范围限制是下一阶段。支持证据来自当前 iOS 26.6 的受控 Fixture，不代表所有输入法、自定义编辑器或 App 已完成验证。执行前检查也不构成与 App 自行变化原子隔离的事务。

## 验收结果

2026-09-05，macOS 15.0.1 / Xcode 16.0 / iPhone13,3、iOS 26.6：

- `swift test`：24 项通过、0 失败。覆盖既有观察/生命周期、动作参数、来源路径、缺失或矛盾的执行事实、拒绝与 unknown 的引用处理，以及排队动作不能重复使用同一引用。
- 完整真机流程：39 次独立 CLI 调用（包含 connect/disconnect）、17 次观察，始终复用 Runner PID 8853 / UUID `9ED8E711-7EF5-41D2-AE32-2C64E94720C7`。持续会话 XCTest 为 1 通过、0 失败、0 跳过。
- 无焦点 insert 返回 unknown，没有隐式点击或写入；重新观察后继续。Fixture 独立将光标放在 `ABCDE` 的 B 后，CLI 插入 `北京` 得到 `AB北京CDE`；Unicode 整段替换、空字符串清空均通过，提交计数始终为 0。截图核对了插入与清空结果。
- 引用点击使计数增加一次，重复使用旧引用被宿主拒绝；向上滑动改变列表位置。Fixture 自行将目标标签从 Mutable A 改为 Mutable B 后，旧引用在设备校验时被拒绝，计数未增加。
- App 原生 Alert 返回独立范围，同名同标识的重复 Confirm 按钮被拒绝；同一观察下明确坐标点击成功，后续状态为 Confirmed。受控 WKWebView 替换为 `Web 北京🙂`，字段值、页面 JavaScript 回显和截图一致。没有再次请求系统权限。
- 修正后的独立输入原语测试补跑通过（1/0/0），包含删除选区后立即为空的断言。
- disconnect 收到 shutdown 确认，xcodebuild 正常退出，socket 和观察缓存删除；宿主、xcodebuild 及设备 Runner 均确认退出。

测试 Fixture 增加了光标位置、提交计数和延迟改名控件，均只用于验收。首次 CLI 尝试发现激活已安装的旧 Fixture 不会更新这些控件，因此显式安装了本轮构建；产品 open 仍只按运行状态激活或启动。第二次尝试暴露清空问题，修正后第三次完整流程通过。前两次的部分结果不计为完整验收成功。

完整本地证据（git 忽略）为 `spikes/ios-xctest/evidence/actions-cli-20260905-03/`：commands.json、o1–o17 的文本/截图/原始节点、verification.json（断言、清理、源码 SHA256）、swift-tests.log、两份 XCTest 摘要及 run.xcresult。修正后的固定测试结果另存于 `input-primitives-20260905-02.xcresult`。这些文件是开发验收证据，不构成产品任务历史功能。
