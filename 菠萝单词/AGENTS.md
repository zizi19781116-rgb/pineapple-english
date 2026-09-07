# 菠萝单词维护约定

本项目为 iPad 优先、兼容 iPhone 的个人原生学习应用。默认最低系统 iOS / iPadOS 17，不增加网页端或服务器。

- 先读《开发说明.md》和《测试与验收.md》。修改底层学习规则必须运行对应核心测试。
- `Sources/PineappleCore` 只依赖 Foundation；界面、SwiftData、Keychain、语音和网络适配放在 `PineappleWords`。
- SwiftData V1 的持久化结构不能就地破坏性修改。新结构通过 `StoreMigrationPlan` 增加版本，备份转换在 `BackupMigrator` 中单独实现。
- 学习操作先落盘再发布界面状态。AI 不能直接修改正确答案或将导入结果写入数据库。
- 任何迁入必须经过 ZIP、SHA-256、关联和计数校验；先写新数据库、完整读回，再原子切换索引。不要删除旧库来“修复”启动问题。
- 每年学习记录长期保留。禁止为了性能删除旧答题记录、计时、笔记或收藏。
- API Key 只能保存在本机 Keychain，不可加入日志、备份、样例或仓库。
- Collins 需要获得授权接口后才接入，不抓取、不伪造标准词典内容。
- 新增 Swift 文件后，运行 `python3 工具/生成工程.py` 更新工程；该生成器也用于检查文件引用。
- 在 Mac 上执行 `bash 工具/验证Mac.command`，并按验收清单完成 iPad 真机、分屏和语音检查。Windows 的语法解析结果不能写成 Xcode 编译通过。
- 测试数据仅用于测试目标和手动导入样例，不作为普通启动数据。
