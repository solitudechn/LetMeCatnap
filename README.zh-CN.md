<div align="center">
  <img src="assets/icon.png" width="128" height="128" alt="LetMeCatnap 图标"/>
  <h1>LetMeCatnap</h1>
  <p><strong>该休息就休息，开会的时候不打扰。</strong></p>
  <a href="https://github.com/solitudechn/LetMeCatnap/releases/latest/download/LetMeCatnap.dmg">
    <img src="assets/download-button.svg" alt="下载 macOS 版">
  </a>
  <p><sub>免费开源，需要 macOS 13 或更高版本。中文 / English 双语界面。</sub></p>

  [![CI](https://github.com/solitudechn/LetMeCatnap/actions/workflows/ci.yml/badge.svg)](https://github.com/solitudechn/LetMeCatnap/actions/workflows/ci.yml)
  [![Release](https://github.com/solitudechn/LetMeCatnap/actions/workflows/release.yml/badge.svg)](https://github.com/solitudechn/LetMeCatnap/actions/workflows/release.yml)

  <sub><a href="README.md">English</a></sub>
</div>

<br/>

<div align="center">
  <img src="assets/break-overlay.png" alt="LetMeCatnap 休息界面" width="480"/>
</div>

<br/>

<div align="center">
  <a href="https://github.com/fikrikarim/repose">原始代码 Fikri Karim</a> ·
  <a href="https://github.com/deseven/iCanHazRepose">上游作者 deseven</a> ·
  <a href="https://github.com/solitudechn/LetMeCatnap">本项目</a>
</div>

<br/>

> **它起于一个 fork，后来长成了自己的应用。** LetMeCatnap 基于
> [deseven/iCanHazRepose](https://github.com/deseven/iCanHazRepose)，加了中英双语界面，
> 并有意改掉了几处行为（休息随时可以退出、暂停时机由你选、更新交给 Sparkle）。
> 它有自己的名字、自己的 bundle id（`io.github.solitudechn.letmecatnap`）和签名的更新源，
> 因此可以和原版并存，而不是覆盖它。这个构建的问题请提到这里，原版的问题请找上游。

<br/>

LetMeCatnap 住在菜单栏里，倒数你的工作间隔，时间到了就把屏幕压暗，提醒你看看别处。休息结束，下一轮自动开始。

和其他休息提醒最大的不同：**它会发现你正在开会，然后安静地等到会议结束。** 不需要连日历，也不需要为每个应用单独配置——摄像头或麦克风被占用，它就知道你在通话。

它同样尊重全屏应用。看电影或打游戏时，屏幕中央会出现一个小面板，不拦截任何操作，按 Esc 就能关掉。

## 它是怎么工作的

1. 设定工作间隔（5–90 分钟）和休息时长（20 秒–10 分钟）
2. 菜单栏显示倒计时
3. 时间到了，温和地提醒你把视线移开——需要的话也可以随时点「立即休息」
4. 可选「番茄节奏」：每完成 N 轮工作安排一次长休息（手动休息不计入轮次）
5. 正在通话时，休息会等到通话结束
6. 锁屏离开，计时自动暂停；解锁后开始全新一轮（**提醒 → 暂停时机**：锁屏 / 空闲 / 两者 / 从不）
7. 休息前一分钟，菜单栏图标变成沙漏并轻声提示，遮罩不会突然出现
8. 休息时看到的是一句简短引导（「看向 20 英尺外」「转一转肩膀」），而不是跳动的数字——全屏遮罩上的倒计时三秒后淡出，点一下圆环可以叫回来。（全屏应用上方的那个小面板例外，它是点击穿透的，倒计时一直显示。）

<div align="center">
  <img src="assets/menu.png" alt="LetMeCatnap 菜单" width="280"/>
</div>

所有功能都在菜单里——暂停、继续、重新开始、全部设置。没有单独的首选项窗口。

## 会议检测为什么真的有效

大多数休息类应用会读你的日历，或者盯着某几个应用有没有在跑。这两种都很容易失效——日历不知道领导刚刚临时拉了个会，而「Zoom 开着」也不等于你在开会。

LetMeCatnap 直接看硬件。用 CoreMediaIO 查摄像头有没有被占用，用 CoreAudio 查麦克风。如果有程序正在用它们，你多半是在通话，于是它就让路。

所以它对你用 Zoom、腾讯会议、FaceTime、Teams、飞书，以及明年才出现的那个新应用都成立。零配置。

## 计时什么时候会暂停

多数休息类应用靠「键盘多久没动」来判断，但「两分钟没敲键盘」同样可以是在读文档——而读文档正是最需要提醒的时候。默认情况下，LetMeCatnap 等的是真正说明你离开了的信号：屏幕锁定，或显示器休眠。解锁之后是全新一轮，因为锁屏本身就是一次真正的休息。

如果你从不锁屏，**提醒 → 暂停时机** 里还有基于空闲的选项：只在空闲时暂停（`空闲 5 分钟`）、两种信号都暂停（`锁屏或空闲`），或者从不自动暂停。空闲默认不开启，因为它最吵——五分钟没有输入就判定为离开，读文档就不会被误伤了。

休息界面三秒后会把倒计时藏起来，把引导语放到正中间——盯着跳动的数字看，正好是把眼睛往坏处用。全屏遮罩上点一下圆环可以把剩余时间叫回来。**Esc 永远能结束一次休息**——提醒不该把人困住，而在全屏应用上方，Esc 是唯一的出路（那个小面板故意做成点击穿透，按钮根本点不到）。**提醒 → 显示跳过按钮** 只决定屏幕上那个按钮显不显示。

## 安装

### 下载

**稳定版**——去 [Releases](https://github.com/solitudechn/LetMeCatnap/releases) 页面下载。

安装包没有做公证，所以首次启动可能被 Gatekeeper 拦下（提示「已损坏」或「无法验证开发者」）。清除一次隔离标记即可：

```sh
xattr -dr com.apple.quarantine /Applications/LetMeCatnap.app
```

**开发版**——每次推送到 `main` 都会由 CI 编译，产物在
[最近一次 CI 运行](https://github.com/solitudechn/LetMeCatnap/actions/workflows/ci.yml) 里。
*（只有想尝鲜或帮忙测试时才建议用）*

### 从源码构建

```
git clone https://github.com/solitudechn/LetMeCatnap.git
cd LetMeCatnap
./build.sh
```

需要 macOS 13 以上，以及完整的 **Xcode**（只装 Command Line Tools 无法展开 SwiftUI 宏）。如果装完 Xcode 后 `xcode-select` 仍指向 CLT，`build.sh` 会自己挑最新的 `/Applications/Xcode*.app`。

`./build.sh` 编译调试版并直接运行；`./build.sh ci` 产出与发布完全相同的产物（通用二进制、`LetMeCatnap.zip`、`LetMeCatnap.dmg`），但不上传、不启动。

## 更新

更新交给 [Sparkle 2](https://sparkle-project.org)，不是自己手写的一套：

- 订阅源是 `https://github.com/solitudechn/LetMeCatnap/releases/latest/download/appcast.xml`，所以「发一个 Release」就是发布更新的全部动作；
- 每个更新包都带 Ed25519 签名，公钥写在 `Info.plist` 的 `SUPublicEDKey` 里，对不上 Sparkle 直接拒绝；
- `/Applications` 不可写时 Sparkle 会弹管理员授权，而不是等应用退出之后才默默失败。

后台每天检查一次，菜单里的「检查更新…」可以随时手动触发。跳过某个版本之后，Sparkle 不再拿它烦你。

## 测试与检查

时间规则、计时器状态机、设置和文案表都在 `CatnapCore` 模块里，所以不需要 AppKit 就能测：

```
./scripts/verify.sh                 # 格式检查 + 文案检查 + 单元测试 + shell 语法
```

分开跑（这几条用的是 `xcode-select` 当前指向的工具链，所以要么先
`sudo xcode-select -s /Applications/Xcode.app`，要么加前缀
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`——Command Line Tools
里既没有 XCTest 也没有 `swift format`，直接跑会报
`unable to resolve module dependency: 'XCTest'`）：

```
swift test --filter CatnapCoreTests   # 需要完整 Xcode（XCTest）
python3 scripts/check-l10n.py         # 每个键都有翻译，没有漏网的硬编码
swift format lint --recursive --strict src core Tests
```

这些在每次 push 时都会由 CI 跑一遍。

## 排错

应用会写一份滚动日志：`~/Library/Logs/LetMeCatnap/LetMeCatnap.log`——每次状态变化、每次检查更新、每次失败都在里面。觉得哪里不对，先看这个文件，提 issue 时也请附上它。

```sh
tail -f ~/Library/Logs/LetMeCatnap/LetMeCatnap.log
```

## 两个看起来像 bug 的行为

- **菜单栏出现三位数。** 工作间隔内部允许到 120 分钟，菜单只提供到 90。旧版本存过 120 的话，菜单栏会显示成 `120:00`。
- **后台放着全屏视频时会变成小面板。** 全屏判定看的是「有没有一个和屏幕一样大的窗口」，而不是「哪个应用在前台」，所以后台的全屏视频也会让休息变成小面板。

## 界面语言

界面自带 **中文** 和 **English**，默认跟随系统语言。随时可以在菜单栏切换：**语言 → 跟随系统 / English / 简体中文**。切换立即生效，不用重启。

每一句面向用户的文字都是 [`core/L10n.swift`](core/L10n.swift) 里的一个 `LocKey`，两种语言的译文都在 [`core/StringTable.swift`](core/StringTable.swift)。写错键名是编译错误；漏翻、译文为空、占位符（`%@` / `%ld`）对不上，`StringTableTests` 会失败。

唯一的例外：Sparkle 自己的更新对话框跟随**系统**语言，而不是应用内的「语言」开关——它们来自框架内部，不读 `StringTable`。

## 许可证

MIT，见 [LICENSE](LICENSE)。两位上游作者的版权声明原样保留，本应用的声明追加在其后。
这三个名字也显示在关于窗口的 **作者 / 上游作者 / 原始代码** 里。
