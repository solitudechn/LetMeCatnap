<div align="center">
  <img src="assets/icon.png" width="128" height="128" alt="LetMeCatnap 图标"/>
  <h1>LetMeCatnap</h1>
  <p><em>我要小喵一下</em></p>
  <p><strong>该休息就休息，开会的时候不打扰。</strong></p>
  <a href="https://github.com/solitudechn/LetMeCatnap/releases/latest/download/LetMeCatnap.dmg">
    <img src="assets/download-button.svg" alt="下载 macOS 版">
  </a>
  <p><sub>免费开源 · 需要 macOS 13 或更高 · 中文 / English</sub></p>

  [![Release](https://github.com/solitudechn/LetMeCatnap/actions/workflows/release.yml/badge.svg)](https://github.com/solitudechn/LetMeCatnap/actions/workflows/release.yml)

  <sub><a href="README.md">English</a></sub>
</div>

<div align="center">
  <img src="assets/break-overlay.png" alt="LetMeCatnap 休息界面" width="480"/>
</div>

LetMeCatnap 住在菜单栏里，倒数你的工作间隔，时间到了就把屏幕压暗，提醒你看看别处。你开会的时候它不打扰，休息开始之后也不会把你困住。名字就是「我要小喵一下」——干一会儿活，再让眼睛眯一下，也就是这么回事。

## 和原版有什么不同

它最初只是 [deseven/iCanHazRepose](https://github.com/deseven/iCanHazRepose) 的 fork，而那个项目又基于 [fikrikarim/repose](https://github.com/fikrikarim/repose)。会议检测、纯菜单栏的设计、全屏应用上方那块点击穿透的小面板，都来自上游。下面这些是本项目自己加的、或者有意改掉的：

|  | iCanHazRepose | LetMeCatnap |
| --- | --- | --- |
| 界面语言 | 只有英文 | 中英双语，默认跟随系统，也能在菜单里随时切换，不用重启 |
| 自动更新 | 「检查更新…」是空实现 | Sparkle 2 + Ed25519 签名的订阅源，每天后台检查一次 |
| 身份 | `wtf.d7.icanhazrepose` | `io.github.solitudechn.letmecatnap` 加独立更新源，可与原版并存，设置互不干扰 |
| 番茄节奏 | 无 | 每 N 轮工作安排一次长休息；手动休息不计轮次；离开 4 小时后计数归零 |
| 什么时候暂停 | 只有「空闲 5 分钟」一个开关 | 默认锁屏或显示器休眠，另有空闲、两者、从不 |
| 休息界面 | 固定一句话 | 标明是哪种休息、还剩多久；长休息换青绿色；22 条轮换的工效学提示；倒计时淡出 |
| 休息之前 | 无 | 提前一分钟沙漏图标加一声轻响 |
| 代码结构 | 计时逻辑在 app target 里，没有测试 | 状态机抽到 `CatnapCore`，不依赖 AppKit 就能测（86 项测试） |

## 安装

去 [Releases](https://github.com/solitudechn/LetMeCatnap/releases) 页面下载 DMG。安装包没有做公证，所以首次启动可能被 Gatekeeper 拦下（提示「已损坏」或「无法验证开发者」）。清除一次隔离标记即可：

```sh
xattr -dr com.apple.quarantine /Applications/LetMeCatnap.app
```

也可以自己编译——见 [开发](#开发)。

## 它是怎么工作的

- 设定工作间隔（5–90 分钟）和休息时长（20 秒–10 分钟）。其余全在菜单栏里：暂停、继续、重新开始、番茄节奏、所有设置，没有单独的首选项窗口。
- 时间到了，屏幕压暗，你看到的是「该做点什么」，而不是一个跳动的数字。**Esc 永远能结束一次休息**——提醒不该把人困住。
- **正在开会时，休息会等。** 检测直接看硬件：CoreMediaIO 查摄像头，CoreAudio 查麦克风。所以它对 Zoom、腾讯会议、FaceTime、Teams、飞书，以及明年才出现的那个新应用都成立，既不用连日历，也不用为每个应用单独配置。
- **你离开，它就暂停。** 默认等的是屏幕锁定或显示器休眠，解锁之后是全新一轮。基于空闲的暂停需要手动开启——「五分钟没敲键盘」同样可以是在读文档，而读文档正是最需要提醒的时候。
- **全屏应用不会被挡住。** 看电影或打游戏时，屏幕中央出现一个小面板，点击穿透，按 Esc 关掉。

休息时的提示都是普通的用眼与工效学常识：20 秒远眺、收下巴、夹肩胛骨，以及「别掰脖子」。值得照做，但不算医疗建议。

<div align="center">
  <img src="assets/menu.png" alt="LetMeCatnap 菜单" width="280"/>
</div>

## 更新

更新交给 [Sparkle 2](https://sparkle-project.org)，订阅源是 `https://github.com/solitudechn/LetMeCatnap/releases/latest/download/appcast.xml`，所以「发一个 Release」就是发布更新的全部动作。后台每天检查一次，菜单里的「检查更新…」可以随时手动触发；跳过某个版本之后，它不再拿那个版本烦你。每个更新包都带签名，公钥写在 `Info.plist` 的 `SUPublicEDKey` 里，对不上直接拒绝。

## 两个看起来像 bug 的行为

- **菜单栏出现三位数。** 工作间隔内部允许到 120 分钟，菜单只提供到 90。旧版本存过 120 的话，菜单栏会显示成 `120:00`。
- **后台放着全屏视频时会变成小面板。** 全屏判定看的是「有没有一个和屏幕一样大的窗口」，而不是「哪个应用在前台」。

如果遇到别的怪事，先看日志：`~/Library/Logs/LetMeCatnap/LetMeCatnap.log` 记录了每次状态变化、每次检查更新和每次失败，提 issue 时也请附上它。

## 开发

```sh
git clone https://github.com/solitudechn/LetMeCatnap.git
cd LetMeCatnap
./build.sh            # 编译调试版并直接运行
./scripts/verify.sh   # 格式检查 + 文案检查 + 单元测试 + shell 语法
```

`./build.sh ci` 产出与发布完全相同的产物（通用二进制、`LetMeCatnap.zip`、`LetMeCatnap.dmg`），但不上传、不启动。

需要完整的 **Xcode**：Command Line Tools 里既没有 XCTest 也没有 `swift format`。装完 Xcode 后 `xcode-select` 仍指向 CLT 的话，`build.sh` 会自己挑最新的 `/Applications/Xcode*.app`；直接跑 `swift test` / `swift format` 则需要先 `sudo xcode-select -s /Applications/Xcode.app`，或者加 `DEVELOPER_DIR=…` 前缀。

时间规则、状态机、设置和文案表都在 `CatnapCore` 里，所以不需要 AppKit 就能测。每一句面向用户的文字都是 [`core/L10n.swift`](core/L10n.swift) 里的一个 `LocKey`，两种译文都在 [`core/StringTable.swift`](core/StringTable.swift)：写错键名是编译错误，漏翻、译文为空、占位符（`%@` / `%ld`）对不上则由测试拦下。发版工作流在打包之前会把所有检查跑一遍，测试不过就不会生成安装包。

## 许可证

MIT，见 [LICENSE](LICENSE)。两位上游作者的版权声明原样保留，本应用的声明追加在其后。
