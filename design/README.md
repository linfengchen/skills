# design — 从产品需求到实现的 Skill

把产品需求（PRD / 用户故事 / 自然语言描述）一次性转成带分层架构、完整测试、可运行代码的新项目。在 **Claude Code** 和 **Cursor** 上格式完全一致，可以直接用。

**核心特性**：默认授权、自动推进、断点可续。Agent 不会在中途问"是否继续？"——所有决策直接落盘到设计文件，不满意就改文件或 `--reset-phase` 重做。

---

## 目录结构

```
skills/design/
├── SKILL.md                       主入口 —— 7 阶段工作流
├── README.md                      ← 本文件（安装 + 使用指引）
└── references/
    ├── STATE_SCHEMA.md            state.json schema + 自动推进规则
    ├── TEMPLATES.md               每个阶段的输出模板
    └── LANGUAGE_STACKS.md         目标语言的分层模式、栈推荐、惯用法
```

---

## 安装

Skill 通过 `SKILL.md` 的 YAML frontmatter 被 Agent 自动发现。把 `skills/design/` 整个拷到 Agent 扫描的 skills 目录下即可。任选一种方式：

### 方式 A — 用户级（所有项目共享，推荐）

```bash
# Cursor
mkdir -p ~/.cursor/skills
cp -r skills/design ~/.cursor/skills/

# Claude Code
mkdir -p ~/.claude/skills
cp -r skills/design ~/.claude/skills/
```

### 方式 B — 项目级（只在当前 repo 生效）

在目标项目的根目录执行：

```bash
mkdir -p .cursor/skills .claude/skills
cp -r skills/design .cursor/skills/
cp -r skills/design .claude/skills/
```

### 方式 C — 软链（保持单一来源，改一处处处生效）

```bash
ln -s skills/design ~/.cursor/skills/design
ln -s skills/design ~/.claude/skills/design
```

### 验证安装

在任意新对话里随口说：

```
design
```

Agent 应当识别到 skill 并提示"请提供需求来源 + 目标语言 + 项目目录"。如果没识别到，检查：
- `SKILL.md` 路径是否在 skills 扫描目录下
- frontmatter 是否完整（`name` + `description`，YAML 语法正确）
- Cursor：设置里 Skills 功能是否开启

---

## 使用

### 基本调用格式

```
design <需求来源> <目标语言> [项目目录]
```

- **需求来源**：文件路径（`.md/.txt/.pdf`）、URL、或直接在对话里贴描述
- **目标语言**：`go` / `rust` / `node` / `ts` / `python`
- **项目目录**：输出到哪个目录（不填则默认当前目录下的同名子目录）

### 例子

**从 PRD 文件起步**：

```
design ./prd/task-service.md go ./task-svc
```

**直接用自然语言描述**：

```
design "做一个团队任务管理的 REST API，支持任务 CRUD、指派、到期提醒、按用户列出任务" rust ./tasks-rs
```

**从 URL 拉需求**：

```
design https://wiki.internal/feature-x ts ./feature-x
```

**完全自然语言（Agent 会自动识别）**：

```
我要做一个用户认证服务，用 go 实现，项目目录 ./auth-svc
需求：支持 邮箱+密码 注册/登录、JWT 颁发、密码重置、会话撤销
```

### 7 阶段总览

| 阶段 | 做什么 | 产物位置（都在 `<项目目录>/.design/` 下） |
|---|---|---|
| 0. Bootstrap | 解析参数、读需求、建目录、写 state.json | `.design/state.json` |
| 1. 需求 + 模块 + 外部接口 | 压缩需求为结构化文档；拆模块；定义对外接口 | `req/`、`modules/`、`api/` |
| 2. 测试契约 | 单元 + 接口 + 契约测试计划 | `tests/*.md` |
| 3. 目标语言架构 | 分层、模块映射、DI、错误模型、技术栈、目录树 | `arch/*.md`；目标目录被 scaffold |
| 4. 步骤拆分 | 把实现拆成 30~120 行/个 的有序步骤卡 | `steps/NN_*.md` + `steps/00_index.md` |
| 5. 迭代实现 | 一次一个步骤卡，YAGNI/KISS/DRY/SRP 内联强制 | 目标代码 + 单元测试 |
| 6. 回归清零 | 跑全量测试，按模块分组修 bug，直到 0 失败 | `coverage/failures.md`、`coverage/summary.md` |
| 7. 最终文档 | 5 份精简文档（README / 架构 / API / ADR / 运维） | `docs/*.md` |

### 默认行为（重要）

- **阶段 0 → 4 自动推进**：一次调用可能把前面 5 个阶段跑完（上下文充裕时）
- **阶段 5（实现）每个步骤后停下**：防止长会话失控 + 你可以在每一步之间审阅
- **阶段 6（回归）每一轮后停下**：方便你看修复 delta
- **阶段 7 自动完成**
- **任何阶段都不会问"是否继续？"**——所有决策直接写入对应 `.md` 文件，不满意再改

---

## 常用操作

### 继续执行（断点续传）

```
继续
```

或

```
design
```

Skill 会读 `.design/state.json`，自动跳到上次停下的 phase/step。

### 查看进度

```
design --status
```

输出：当前 phase、已完成模块数、下一步、assumptions 列表等。

### 一次把所有步骤跑完（慎用）

在 Phase 5 时：

```
design --run-all-steps
```

会连续跑步骤直到：（a）全部完成，（b）遇到 blocker，（c）上下文饱和。适合步骤很多、你想喝杯咖啡回来看结果的情况。

### 重做某一阶段

对某阶段产物不满意（例如觉得架构选错了）：

```
design --reset-phase 3
```

把 phase 3 置为 pending，清空 `.design/arch/`，`phase = 3`，重新跑就会用新决策覆盖。

### 一次只跑一个阶段（关闭自动推进）

一次性禁用：

```
design --no-auto
```

永久禁用（把 `auto_advance` 写入 state）：

```
design --step-only
```

### state 坏了修复

```
design --repair
```

从 `.design/` 里已存在的文件反推状态，重建 state.json。

---

## 典型流程（举例：从 PRD 造一个 go 服务）

```
你: design ./prd.md go ./task-svc

Agent: [Phase 0] 识别到 go 目标，项目目录 ./task-svc，读到 PRD (1840 字)。
       state.json 已创建。自动进入 Phase 1…
       [Phase 1] 生成 req/（6 份）、modules/（7 个模块卡 + index）、api/（3 份）。
       记录了 3 条 assumptions（PRD 未明确的细节，已默认决策并落盘）。
       自动进入 Phase 2…
       [Phase 2] 单元测试 142 条、集成测试 38 条、契约测试 5 条计划写完。
       自动进入 Phase 3…
       [Phase 3] 架构决策：chi + sqlc + slog + envconfig。目录树已 scaffold (21 个空文件)。
       自动进入 Phase 4…
       [Phase 4] 拆成 28 个步骤卡，顺序已排好。
       自动进入 Phase 5 第一步…
       [Phase 5 - 00/28] domain_task_model
       写入 internal/domain/task.go (64 行)，task_test.go (3/3 通过)
       已停。说"继续"跑下一步。

你: 继续

Agent: [Phase 5 - 01/28] domain_task_validation ...

（... 循环 28 次 ...）

你: 继续

Agent: [Phase 5 全部完成] 自动进入 Phase 6 第 1 轮…
       [Phase 6 - 第 1 轮] 全量测试 185 条，其中 162 通过，23 失败。
       本轮修 service_task 模块的 5 条失败。已停。

你: 继续
（...直到 0 失败...）

Agent: [Phase 6 完成] 覆盖率 87%。自动进入 Phase 7…
       [Phase 7] 5 份文档写完。
       全部完成：目标代码 2140 行，测试 185 条全绿。
```

---

## 与 skills/rewrite 的区别

| 维度 | rewrite | design |
|---|---|---|
| 起点 | 已有源代码 | 产品需求文档 / 描述 |
| Phase 1 | 从源码抽取架构 | 从需求抽取 + 模块设计 + 外部接口 |
| Phase 3 | **暂停等用户 approve** | **不暂停**，自动推进 |
| 决策不明确时 | 问用户 | 默认决策 + 记录到 `assumptions` |
| 语言参考文件 | `LANGUAGE_MAPPING.md`（源→目标惯用法映射） | `LANGUAGE_STACKS.md`（目标语言栈推荐） |
| 典型规模 | 10W~100W+ 行 | 通常 500~10000 行 |

---

## 你的 8 条需求映射

| 需求 | 对应阶段 / 机制 |
|---|---|
| 1. 理解需求，设计模块和对外接口，分门别类存储 | Phase 1：`req/`、`modules/`、`api/` 三个分类目录 |
| 2. 基于接口设计单元 + 接口测试 | Phase 2：四份 `tests/*_plan.md` |
| 3. 目标语言架构优先，分层合理、高内聚低耦合 | Phase 3 + `LANGUAGE_STACKS.md` |
| 4. 模块 Step by Step、可原地重启 | Phase 4 步骤卡 + state.json `current_step` |
| 5. YAGNI / DRY / KISS / 单一职责，函数不长 | Phase 5 内联强制，40 行函数上限 + Rule of Three |
| 6. 测试回归到 bug 清零 | Phase 6 循环，每轮最多 5 失败或 1 模块 |
| 7. 最终文档精简不发散 | Phase 7 固定 5 份，每份 ≤ 500 词 |
| 8. 默认授权，不二次确认 | Phase 3 不 pause；所有决策直接落盘；assumptions 记录兜底 |

---

## 故障排查

**Agent 没识别到 skill？**
- 确认 SKILL.md 在 `~/.cursor/skills/design/` 或 `~/.claude/skills/design/` 下
- 检查 frontmatter 格式是否正确（用 `head -n 10 SKILL.md` 看）
- 重启对话

**Agent 还是在问"是否继续？"**
- 提醒它："我已经在 skill 里写了默认授权，直接按 SKILL.md 的 auto-advance 规则跑"
- 可以把 SKILL.md 的 "Default authorization" 段落粘给它

**自动推进跳过了我想审查的阶段？**
- 下次用 `design --step-only` 永久切成一阶段一停
- 或者在调用时加 `--no-auto`

**做出来的架构不符合预期？**
- 不要手改代码（会和 state 不同步）。跑 `design --reset-phase 3`，重写架构文档后再跑

**state.json 丢了 / 损坏？**
- `design --repair` 反推重建

---

## 下一步

准备好一份需求（文件、URL、或直接在对话里贴），告诉 Agent：

```
design <需求来源> <目标语言> [项目目录]
```

然后坐等它跑完 Phase 0~4 + Phase 5 第一步，再按 "继续" 推进即可。
