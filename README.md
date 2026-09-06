# The Second Brain

很多想法说出来比打字快，麻烦往往出在后面。中英文混着说会听错，产品名容易变形，录完以后还要找文字、复制、整理。The Second Brain（TSB）想把这段过程收进 Mac 顶部的一块小界面里。

按下 `⌥ Space` 开始录音，讲话时会出现本地实时草稿。再次按下 `⌥ Space` 或点击“停止”，TSB 会保留录音，生成本地定稿，写入记录，再把文字复制一次。按 `Esc` 代表取消，本次未完成的录音会被丢弃。

```text
录音
  -> 本地实时草稿
  -> 停止后本地复核
  -> 保存 audio.wav 和 record.json
  -> 复制一次
  -> 可选的文本润色与内容整理
```

本地处理始终先完成。网络不可用、API 没有配置或云端整理失败，都不会影响录音留存，也不能覆盖已经复制的本地文字。

## 现在做到哪一步

`main` 是经过评审的基线；进行中的改动只在 Draft PR 中推进。自动化门禁的准确数量以 GitHub Checks 和 [0.2 验收矩阵](docs/testing/tsb-v0.2-acceptance-matrix.md) 为准。

一次当前版本的真实录音复核记录到以下结果。

- 首次出现实时草稿用了 1,546 ms，暂时没有达到 800 ms 的目标。
- 停止后 613 ms 写入本地定稿，618 ms 完成复制。
- 本次录音留下了一份 `audio.wav` 和一份 `record.json`，剪贴板只改动一次。
- 云端整理失败后，本地记录和剪贴板内容保持不变。

这组结果能说明本地保存和复制已经跑通。当前版本仍是开发中的个人验证版本；尚无已验证的签名、公证的公开发布。顶部界面的视觉与 VoiceOver 还要人工复核，真实 Provider 润色也没有通过本轮网络验收。

完整状态放在 [0.2 验收矩阵](docs/testing/tsb-v0.2-acceptance-matrix.md)。自动化、真机体验和正式发布在这里分开记录，避免把工程进度写成已经上线。

## 本地生成与验证

当前工具链为 macOS 26.5.2 arm64、Xcode 26.6、Swift 6.3.3 和 XcodeGen 2.46.0。完整本地门禁只使用：

```bash
./scripts/verify-tsb.sh
```

该命令会生成被忽略的 Xcode 工程，运行静态与 bootstrap 检查、完整无签名测试，以及无签名 Debug 构建。

## Git 主链

```text
origin/main
  -> codex/<scope> isolated worktree
  -> ./scripts/verify-tsb.sh
  -> Draft PR
  -> independent review + GitHub required check
  -> Ready for review
  -> merge to main
  -> remove merged worktree and branch
```

## 许可证与来源

仓库代码和文档采用 [MIT License](LICENSE)；移植的 OpenDictation 归属说明见 [UPSTREAM.md](apps/macos/TSB/UPSTREAM.md)，外部参考见 [references/README.md](references/README.md)。模型权重和公开语料各自遵循原有许可证，不会因仓库的 MIT 授权而被重新授权。

## 文字为什么分层保存

实时草稿适合让人知道系统听到了什么，本地离线结果负责停止后的定稿。可选的云端润色只处理经过授权的文字候选，返回结果还要经过本地规则检查。

原始转写、本地清理结果、润色候选和整理结果分别保存。TSB 不会为了得到一段更顺的文字，悄悄覆盖最初听到了什么。

## 隐私边界

- 音频、文件路径、API Key 和整份历史记录不会进入云端请求。
- 只有用户明确开启功能后，本次录音的文字候选和相关术语才可以发送。
- 每次录音都可以选择“仅本地”。
- API Key 保存在 macOS Keychain，仓库和日志不保存正文、录音或密钥。
- 云端结果来得再晚，也不能再次修改剪贴板。

## 当前没有做的事

TSB 目前不做语音唤醒、自动粘贴、云端语音识别和模型训练，也不会扫描整台电脑建立知识库。这些能力没有提前搭空架子，后续只有在真实使用需要时才会进入设计。

## 文档入口

- [0.2 第一性原理设计](docs/superpowers/specs/2026-08-20-tsb-v0.2-first-principles-design.md)
- [0.2 转写润色设计](docs/superpowers/specs/2026-08-25-tsb-v0.2-transcript-polish-design.md)
- [0.2 验收矩阵](docs/testing/tsb-v0.2-acceptance-matrix.md)
- [Alpha 2 本地听写设计](docs/specs/tsb-v0.1-alpha2-design.md)
- [架构决策](docs/decisions/)
- [实际执行记录](docs/execution/)
- [外部参考与来源](references/README.md)

## 仓库怎么读

```text
The Second Brain/
├── apps/macos/TSB/       # macOS 产品源码与测试
├── docs/specs/           # 已确认的产品与技术设计
├── docs/plans/           # 准备执行的计划
├── docs/decisions/       # 关键取舍及其后果
├── docs/execution/       # 实际做过的工作和偏差
├── docs/testing/         # 自动化与人工验收边界
├── evidence/             # 可复核的证据索引
└── references/           # 外部项目及原始需求来源
```

设计文档记录当时为什么这样选，执行记录说明后来实际做了什么。两者有冲突时，以带提交和测试证据的执行记录为准。
