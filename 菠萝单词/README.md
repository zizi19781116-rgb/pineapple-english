# 菠萝单词

一个 iPad 优先、兼容 iPhone 的个人英语学习 App。使用 Swift、SwiftUI、SwiftData、Keychain、系统英式语音和 DeepSeek；没有自建服务器，没有内置教材，没有自动上传学习库。

**交付状态：已创建完整 Xcode 工程和功能源码，附自动测试与 Mac 验证脚本。当前开发环境是 Windows，没有 Xcode、Apple SDK 或 iOS 模拟器，因此尚未实际通过 Xcode 编译、模拟器运行或真机安装验收。请先完成下面的 Mac 验证，再将它作为唯一的正式学习库。**

## 在 Mac 上开始

1. 将整个“菠萝单词”文件夹复制到 Mac 的本地磁盘。保持目录结构完整。
2. 安装完整 Xcode，建议 Xcode 16 或更新版本，并下载 iOS 模拟器运行时。工程最低系统是 iOS / iPadOS 17。
3. 双击 **菠萝单词.xcodeproj**，选择 **菠萝单词** Scheme 和一个 iPad 模拟器。
4. 先按 **Command + B** 编译，再按 **Command + U** 执行测试；按 **Command + R** 运行。
5. 安装到自己的 iPad / iPhone 时，在 Target `PineappleWords` → Signing & Capabilities 中选择自己的开发团队。必要时将 Bundle Identifier 改为自己的唯一标识。连接并信任设备，在设备中启用开发者模式后运行。

本项目不需要 CocoaPods、XcodeGen 或第三方 Swift 包。`PineappleCore` 是工程目录里的本地 Swift Package。

也可以在终端进入项目目录，运行：

```bash
bash 工具/验证Mac.command
```

脚本会依次运行纯逻辑测试、iOS 模拟器编译、iPad 和 iPhone 的单元测试与界面测试，并将日志及 `.xcresult` 保存到 `验证结果/日期时间/`。缺少对应模拟器时会明确停止；不会把跳过的检查标记为通过。

## 第一次使用

应用启动时词库和统计均为空。先到“词书 → 导入词书”选择自己的资料。

想先验证离线流程，可以手动导入 `导入样例/原创入门体验词书.json`。其中只有 8 个原创编写的体验词条，分为 2 课；它不会自动装入学习库，也不代表新概念或任何其他教材。选择 JSON 文件后默认采用本地解析，无需 API Key。

导入流程是：读取资料 → 本地或 AI 整理 → 字段、去重和来源检查 → **可编辑的预览** → 勾选已检查 → 确认写入。标准 CSV / JSON 默认离线解析；非结构化文本和 PDF 可以选择 DeepSeek 深度整理。关闭 AI 时，TXT 使用“每行一个词”或“英文 + Tab + 中文”的约定；`Lesson 1` 为章节行。

进入“设置”填写 DeepSeek API Key 并保存后，才可使用联网功能。快速和深度模型可在“模型配置”中修改。Key 仅存本机 Keychain，迁入另一台设备后需要重新填写。

## 已实现的功能

| 范围 | 实际实现 |
|---|---|
| 导航与界面 | iPad `NavigationSplitView`；宽屏词表与详情并排；iPhone `NavigationStack`；浅色与深色；系统字体与可伸缩布局 |
| 首页 | 今日有效学习时间、新词、复习词、正确率、到期数量、连续天数、主词书与当前 Lesson 进度 |
| 词书 | 通用 Book → Chapter → Vocabulary 模型；主词书；按课筛选；手动编辑词条全部资料 |
| 学习 | 四选一、拼写、困难模式、例句填空、英文释义、英音听写；提交防重复；答错本轮末尾再练一次 |
| 单词状态 | 独立错题本、易错词、薄弱词、收藏；手动调整优先于自动算法；错题连续正确移除可配置 |
| 笔记与搜索 | 自动保存与手动保存；按日期或单词查笔记；全局搜索单词、词组、笔记和词书 |
| 复习 | 动态间隔、掌握等级、连续表现、近期错误、逾期判断；提前刷题不跳升间隔 |
| 统计与计时 | 日、周、月、年、全部；永久原始记录；跨年时间拆分；闲置暂停；后台停止；计时写入保护 |
| 英式语音 | 系统 en-GB 男声 / 女声偏好；按可用声音回退；单词和例句播放；播放结束解除音频压低 |
| AI | 自动 / 快速 / 深度；上下文问答与历史对话；独立词条解析；基于已有资料的困难语境题 |
| 导入 | TXT、CSV、JSON、PDF、粘贴；PDF 本地提取 / OCR；分段深度整理；非法 JSON 修复一次；预览可改可删 |
| 备份 | 标准 ZIP；CRC32 + SHA-256；版本、关联和计数校验；V0 开发格式迁移；新库读回比对与原子切换；保留旧库 |
| Collins | 独立协议和显示开关，未配置时隐藏；授权 API 适配器尚未实现 |

键盘支持：`Command + F` 全局搜索，拼写框 `Enter` 提交，`Command + Enter` 提交 / 下一题，`Command + R` 在词卡和支持播放的题目中朗读。

## 数据与备份

App 自己的学习数据位于应用沙盒 `Application Support/PineappleWords`。SwiftData 禁用 CloudKit，设置保存在同一学习库，API Key 保存在设备专属 Keychain。不会用“打不开就重建空数据库”的方式处理故障。

“设置 → 数据迁出 / 迁入”可生成 `菠萝单词备份_日期_时间.zip`。备份包含词书、Lesson、单词、进度、全部答题事件、错题状态、易错与薄弱覆盖状态、收藏、笔记、计时、AI 对话、词条 AI 解析和设置。统计及复习计划可从这些原始记录完整恢复。**API Key 不在备份中；备份本身未加密。**

迁入是一份完整学习库的恢复，不进行两台设备之间的增量同步或混合合并。迁入前先保护当前库；新库通过读回比对后才切换。每日首次有数据时创建一份本机保护副本。**本机保护副本会随 App 删除或设备损坏而丢失，定期将手动备份保存到文件 App、iCloud Drive、AirDrop 或另一台设备。**

## 当前边界

- **尚无 Mac 编译 / 模拟器 / 真机通过结果。** 已执行的 Windows 检查详见 `交付检查记录.md`。
- Collins 只有独立接口，等待合法授权服务的接口合同和凭据；不会显示伪造的词典结果。
- DeepSeek 尚未使用你的真实 API Key 联调。单词解释、OCR 和 AI 识别的语义准确性仍需要在预览和实际使用中核对。
- 不附带新概念、雅思等完整教材。请使用你提供的资料，不通过 AI 凭记忆还原教材。
- 同课同词去重；同词跨课出现时保留各课词条并提醒，**各课词条的学习进度独立**。跨课合并记忆尚未设计为同一个词条实体。
- 当前导入边界为每份文件 30 MB、PDF 200 页、提取文本 50 万字符；完整备份最大 256 MB，采用无压缩 ZIP。大规模多年日志的真机性能尚未压测。
- 答题立即保存；笔记停止输入约 0.6 秒保存并在离开时再次保存。计时每 15 秒落盘，强制杀进程或断电最多可能损失尚未到达检查点的约 15 秒计时；已写入计时保护文件的片段会重放恢复。
- 不包含账户、服务器、多设备自动同步、Excel 导入、Android、Windows、macOS 或网页应用。

更详细的设计和真实验收步骤见 **开发说明.md**、**测试与验收.md**。继续修改时，请一并保留整个项目和这些文档。

## 官方接口核对

DeepSeek 的当前模型与请求格式参照 [首次 API 调用](https://api-docs.deepseek.com/)、[思考模式](https://api-docs.deepseek.com/guides/thinking_mode/) 和 [JSON 输出](https://api-docs.deepseek.com/guides/json_mode/)。当前默认快速模型为 `deepseek-v4-flash`，深度模型为 `deepseek-v4-pro`；快速显式关闭思考，深度启用思考并设置 high。模型名称没有散落在界面代码里。

Apple 存储与语音接口参照 [ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer)、[SchemaMigrationPlan](https://developer.apple.com/documentation/swiftdata/schemamigrationplan) 和 [AVSpeechSynthesisVoiceGender](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoicegender)。核对日期：2026-09-07。
