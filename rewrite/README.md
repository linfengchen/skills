# 跨语言重构 Skill 工作区

这个目录包含一个名为 `rewrite` 的 Agent Skill，用于把大型代码库（10W~100W+ 行）从一种语言迁移到另一种语言（Node↔Go / Python↔Rust / Python↔Node 等）。在 **Claude Code** 和 **Cursor** 上可以直接使用，格式相同。

---

## 目录结构

```
code_design/
├── README.md                         ← 本文件
└── skills/
    └── rewrite/
        ├── SKILL.md                  主入口（7 阶段工作流）
        └── references/
            ├── STATE_SCHEMA.md       state.json 断点续传 schema
            ├── TEMPLATES.md          每个阶段的输出模板
            └── LANGUAGE_MAPPING.md   语言对之间的惯用法映射
```

---

## 快速开始

### 1. 让 Agent 能发现这个 skill

Skill 通过 YAML frontmatter 被 Agent 自动发现，需要把它放到 Agent 扫描的目录里。挑一种：

**方式 A — 项目级（推荐，随 repo 共享）**

```bash
mkdir -p .cursor/skills
cp -r skills/rewrite .cursor/skills/

mkdir -p .claude/skills
cp -r skills/rewrite .claude/skills/
```

**方式 B — 用户级（所有项目共用）**

```bash
mkdir -p ~/.cursor/skills
cp -r skills/rewrite ~/.cursor/skills/

mkdir -p ~/.claude/skills
cp -r skills/rewrite ~/.claude/skills/
```

**方式 C — 软链（避免复制，保持单一来源）**

```bash
ln -s "$(pwd)/skills/rewrite" ~/.cursor/skills/rewrite
ln -s "$(pwd)/skills/rewrite" ~/.claude/skills/rewrite
```

> 说明：Cursor 和 Claude Code 都会扫描 `~/.cursor/skills/`、`.cursor/skills/`、`~/.claude/skills/`、`.claude/skills/` 下的 `SKILL.md`。本 skill 使用标准 frontmatter，两个平台都能自动识别。

### 2. 在对话里触发

随便用其中一种说法，Agent 会读取 `SKILL.md` 并自动进入流程：

```
rewrite ./my-node-api go ./my-go-api
```

```
帮我把 ./services/order 从 python 重构到 rust，目标目录 ./services/order-rs
```

```
port this project to go
```

```
重构这个 node 项目到 go
```

### 3. 一次一个阶段，逐步推进

Skill 的核心设计：**每次调用只执行一个阶段，写入 state.json 后停下，等你再次调用**。这样：
- 上下文窗口永远干净
- 任意时刻被打断都能从断点继续
- 你对每一阶段的产物可以审阅、修改、回滚

---

## 7 个阶段概览

| 阶段 | 目标 | 主要产物（都写在 `<target_dir>/.rewrite/` 下） |
|---|---|---|
| **0. Bootstrap** | 识别源语言、创建目录骨架、写初始 state.json | `.rewrite/state.json` |
| **1. 架构抽取** | 把源代码压缩成结构化 markdown（模块/接口/业务规则） | `arch/inventory.md`、`arch/modules/*.md`、`arch/api.md` 等 |
| **2. 测试契约设计** | 在写一行新代码之前定义完整回归面 | `tests/unit_plan.md`、`tests/integration_plan.md` 等 |
| **3. 目标架构设计** ⚠ | 设计新代码的分层/模块映射/技术选型，**暂停等你确认** | `design/architecture.md`、`design/directory_tree.md` 等 |
| **4. 步骤拆分** | 把实现拆成 30–120 行/单元的顺序步骤卡 | `modules/00_index.md`、`modules/NN_<name>.md` |
| **5. 迭代实现** | 一次实现一张步骤卡，强制 YAGNI/KISS/DRY/SRP | 实际目标代码 + 单元测试 |
| **6. 回归清零** | 跑全量测试，按模块分组修 bug，迭代到 0 失败 | `coverage/failures.md`、`coverage/summary.md` |
| **7. 最终文档** | 5 份精简文档（README / 架构 / API / ADR / 迁移 delta） | `docs/*.md` |

阶段 3 会**显式暂停**等你回复 `approved` 才会继续，避免架构错误扩散到实现。

---

## 常用操作

### 查看当前进度

```
rewrite --status
```

输出当前在哪个阶段、已完成哪些模块、下一步是什么。

### 从断点继续

直接再说一次：

```
继续
```

或

```
rewrite
```

Skill 会读 `state.json`，从上次停下的地方继续。

### 重做某个阶段

如果对某阶段产物不满意：

```
rewrite --reset-phase 3
```

会把 phase 3 标为 pending、清空 `design/` 目录、把 `phase` 置回 3。然后重新调用即可。

### state.json 坏了怎么办

```
rewrite --repair
```

会扫描 `.rewrite/` 下已存在的文件反推状态，重建 state.json。

---

## 典型一次完整流程（举例：node → go）

```
你: rewrite ./api go ./api-go

Agent: [Phase 0] 识别到 node 项目，42 个模块，~30W 行。目录骨架已创建。
       下一步: Phase 1 架构抽取。

你: 继续

Agent: [Phase 1] 生成了 42 份模块卡、API 清单、跨切面文档、5 条痛点。
       下一步: Phase 2 测试契约。

你: 继续

Agent: [Phase 2] 单元测试计划 280 条，集成测试 95 条，契约测试 12 条。
       下一步: Phase 3 目标架构，会暂停等你确认。

你: 继续

Agent: [Phase 3] 已写出目标架构（chi + sqlc + slog + viper）、目录树、数据模型。
       ⚠ 请审阅，回复 approved 继续，或指出修改点。

你: approved

Agent: [Phase 3 完成] 目标目录骨架已 scaffold（空文件）。
       下一步: Phase 4 步骤拆分。

你: 继续

Agent: [Phase 4] 拆成 67 个步骤卡，从 domain model 到 main wiring。
       下一步: Phase 5，每次实现一步。

你: 继续

Agent: [Phase 5 - 步骤 0/67] domain_user_model
       写入 internal/domain/user.go (58 行)
       user_test.go 通过 (3/3)
       下一步: 步骤 1 domain_order_model。

你: 继续
...(重复 67 次，每次可以随时停下休息)...

你: 继续

Agent: [Phase 6 - 第 1 轮] 运行全量测试，312/420 通过，108 失败。
       本轮修复 repo 层 5 条失败。下一轮继续。

你: 继续
...(重复到 0 失败)...

Agent: [Phase 7] 5 份文档写完。全部阶段 done。
       目标代码 18432 行，测试 420 条全绿，覆盖率 84%。
```

---

## 设计约束（你之前提出的 7 条需求映射）

1. ✅ **总结原代码架构/接口/业务细节并分门别类存储** → Phase 1 产出 `arch/` 下的分类文件
2. ✅ **基于接口和业务细节设计单元 + 接口测试** → Phase 2 产出 `tests/` 下四份计划
3. ✅ **目标语言架构优先，分层、模块清晰、高内聚低耦合** → Phase 3 + `LANGUAGE_MAPPING.md`，强制用户确认
4. ✅ **StepByStep 细粒度拆分，中断后可原地重启** → Phase 4 步骤卡 + `state.json.current_step`
5. ✅ **YAGNI / DRY / KISS / SRP，函数不过长** → Phase 5 内联 enforce，40 行函数上限、Rule of Three
6. ✅ **测试回归到 bug 清零** → Phase 6 循环，每轮最多 5 条失败或 1 个模块
7. ✅ **最终文档不过多不发散** → Phase 7 固定 5 份，每份 ≤ 500 词硬上限

---

## 故障排查

**Agent 没识别到 skill？**
- 检查 `SKILL.md` 路径（必须在 Agent 扫描的 skills 目录下）
- 检查 frontmatter 完整（`name` + `description`，YAML 语法正确）
- Cursor：在设置里确认 Skills 功能已启用

**Agent 一次跑完多个阶段？**
- 这违反设计意图，请指出"你应该 Phase N 完成后就停下"，Skill 文件里明确要求 one phase per invocation

**`.rewrite/state.json` 和目录结构不一致？**
- 跑 `rewrite --repair`

**实现阶段函数太长 / 出现无用抽象？**
- 在 Phase 5 卡住时提醒 Agent 重新读 SKILL.md 的 Phase 5 实现规则（YAGNI / Rule of Three / 40 行上限）

---

## 下一步

准备就绪后，告诉我具体项目路径和目标语言，我来跑第一次：

```
rewrite <源目录> <目标语言> [目标目录]
```

例如：

```
rewrite /Users/joy/code/my-api go /Users/joy/code/my-api-go
```
