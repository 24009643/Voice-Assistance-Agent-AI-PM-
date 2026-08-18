# The Second Brain

The Second Brain（TSB）是一款本地优先的 macOS 语音听写与灵感捕捉工具。

当前 `0.1` 聚焦一条可靠闭环：快捷键录音、SenseVoiceSmall 本地分段转录、保守清理、原文留存与自动复制。生成式 LLM、语音唤醒、光标直接插入和个人知识库属于后续阶段。

## 当前状态

- 阶段：0.1 工程准备
- 目标设备：M5 Pro、48GB 内存的 MacBook
- 数据边界：音频和听写文本在 0.1 全部留在本地
- 发布边界：当前用于个人验证，不提供签名安装包

## 文档入口

- 设计规格：[docs/specs/tsb-v0.1-design.md](docs/specs/tsb-v0.1-design.md)
- 实施计划：[docs/plans/](docs/plans/)
- 架构决策：[docs/decisions/](docs/decisions/)
- 工程标准：[docs/standards/engineering-standard.md](docs/standards/engineering-standard.md)
- 执行记录：[docs/execution/](docs/execution/)
- 验收证据：[evidence/](evidence/)
- 外部参考：[references/README.md](references/README.md)

## 仓库边界

```text
The Second Brain/
├── apps/macos/TSB/       # 正式 macOS 产品源码
├── docs/specs/           # 已批准的设计事实源
├── docs/plans/           # 尚未执行的实施计划
├── docs/decisions/       # ADR：重要取舍、后果和回退
├── docs/standards/       # 工程、隐私和质量规则
├── docs/execution/       # 实际执行结果和偏差记录
├── evidence/             # 可复核的测试与性能证据索引
├── references/           # 外部项目和原始需求的来源登记
└── artifacts/            # 可再生成的大文件，本地保留且不提交
```

设计说明“为什么和做什么”，计划说明“准备怎样做”，执行记录说明“实际上做了什么”。三者不得互相覆盖。
