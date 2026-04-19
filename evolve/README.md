# evolve — 棕地代码助手 Skill

在**已有代码库**上做新功能 / 改造 / 修 bug 的端到端 Skill。在 **Claude Code** 和 **Cursor** 上用同一份 SKILL.md，行为完全一致。

**核心特性**：默认授权、自动推进、断点可续。**全程只有一个确认环节**——当 Skill 发现现有代码不合理（挡住实现）时，会列出"重构建议"等你点头/否决/延后；其它所有决策都会直接落盘到设计文件，不满意改文件或 `--reset-phase` 重做。

---

## 目录结构

```
skills/evolve/
├── SKILL.md                       主入口 —— 6 阶段工作流
├── README.md                      ← 本文件（安装 + 使用指引）
└── references/
    ├── STATE_SCHEMA.md            state.json schema、修复协议、确认门语义
    ├── TEMPLATES.md               每个阶段产物的输出模板
    └── QUALITY_GATES.md           evolve 专属的 per-step checklist
                                   （通用准则见 ../PRINCIPLES.md）
```

> 通用软件设计准则（YAGNI/KISS/DRY/SRP/SOLID/分层）抽到 `skills/PRINCIPLES.md`，三个 skill 共享。

---

## 安装

Skill 通过 `SKILL.md` 顶部 YAML frontmatter 被 Agent 自动发现。把 `skills/evolve/` 整个拷到 Agent 扫描的 skills 目录下即可。三选一：

### 方式 A — 用户级（所有项目共享，推荐）

```bash
# Cursor
mkdir -p ~/.cursor/skills
cp -r skills/evolve ~/.cursor/skills/

# Claude Code
mkdir -p ~/.claude/skills
cp -r skills/evolve ~/.claude/skills/
```

如果你想用 PRINCIPLES.md 共享准则，把它一起拷进去（放在 skills 父目录或 evolve 内都行；SKILL.md 里以相对路径 `../PRINCIPLES.md` 引用）：

```bash
cp skills/PRINCIPLES.md ~/.cursor/skills/PRINCIPLES.md
cp skills/PRINCIPLES.md ~/.claude/skills/PRINCIPLES.md
```

### 方式 B — 项目级（只在当前 repo 生效）

在目标项目根目录执行：

```bash
mkdir -p .cursor/skills .claude/skills
cp -r /path/to/skills/evolve .cursor/skills/
cp -r /path/to/skills/evolve .claude/skills/
cp /path/to/skills/PRINCIPLES.md .cursor/skills/
cp /path/to/skills/PRINCIPLES.md .claude/skills/
```

### 方式 C — 软链（保持单一来源，改一处处处生效）

```bash
ln -s "$(pwd)/skills/evolve" ~/.cursor/skills/evolve
ln -s "$(pwd)/skills/evolve" ~/.claude/skills/evolve
ln -s "$(pwd)/skills/PRINCIPLES.md" ~/.cursor/skills/PRINCIPLES.md
ln -s "$(pwd)/skills/PRINCIPLES.md" ~/.claude/skills/PRINCIPLES.md
```

### 验证安装

在任意新对话里说：

```
evolve
```

Agent 应该回答类似 "请提供需求来源 + 项目目录"。如果没识别到：

- 确认 `SKILL.md` 在 `~/.cursor/skills/evolve/` 或 `~/.claude/skills/evolve/` 下
- 检查 frontmatter 完整（`name` + `description`，YAML 合法）
- Cursor：设置里 Skills 功能已开启
- 重启对话窗口

---

## 使用

### 基本调用

```
evolve <需求来源> [项目目录]
```

- **需求来源**：文件路径（`.md/.txt/.pdf`）、URL、或直接对话里贴描述
- **项目目录**：默认当前目录 `.`（Skill 自动从 lockfile 推断语言）

### 例子

**从 PRD 文件起步**：

```
evolve ./prd/mute-user.md ./
```

**直接自然语言描述**：

```
evolve "给订单服务加一个'部分退款'接口，金额校验、幂等、审计日志" ./order-svc
```

**完全自然语言（Agent 自己识别 skill）**：

```
在当前 repo 加一个用户禁言接口，需求文档在 ./prd/mute.md
```

### 6 阶段总览

所有产物都落在 `<项目目录>/.evolve/` 下；生产代码按 repo 自身约定的位置写入。

| 阶段 | 做什么 | 产物位置 | 是否暂停 |
|---|---|---|---|
| 0. Bootstrap | 解析参数、识别语言、建目录、写 state.json | `.evolve/state.json` | 否 |
| 1. 需求 + 顶层设计 + 对外接口（**分门别类**） | 把需求压成结构化文档；做顶层设计；定义对外接口 | `req/`、`design/`、`api/` | 否 |
| 2. 现有架构熟悉 + 测试设计（**单元 + 接口**） | 读懂现有代码层次和约定；写测试计划 | `arch_scan/`、`tests/` | 否 |
| 3. 实现计划 + 重构建议（**唯一确认门**） | 拆步骤；列出现有代码不合理的地方供你决策 | `plan/steps.md`、`plan/refactor_proposals.md` | **是**（如果有重构建议） |
| 4. 迭代实现 | 一次一个步骤，YAGNI/KISS/DRY/SRP + 200 行函数硬上限 | 生产代码 + 单元/接口测试 | 每步停 |
| 5. 回归清零 | 跑全量单元 + 接口测试，按模块修，直到 0 失败 | `coverage/failures.md`、`coverage/summary.md` | 每轮停 |
| 6. 最终文档（**只 1 份**） | 一份 `DESIGN.md`：代码结构 + 使用说明 | `.evolve/DESIGN.md` | 否 |

### 默认行为（重要）

- **0 → 3 自动推进**：一次调用通常会把前 4 个阶段一口气跑完
- **Phase 3 在有重构建议时停下**：等你回 `approve / reject / defer`
- **Phase 4 每个步骤后停下**：防止上下文失控 + 你可以中途审阅
- **Phase 5 每轮后停下**：方便看修复 delta
- **Phase 6 自动完成**
- **任何阶段都不会问"是否继续？"**——只有重构门是例外

---

## 重构确认门怎么用

Phase 3 末尾，如果 Skill 在读现有代码时发现挡住实现的地方，会输出类似：

```
重构建议（共 3 项），等你决策：
  RP-01  Hoist user-lookup helper  (low risk, 1 step)
  RP-02  Split god-function OrderProcess  (medium risk, 2 steps)
  RP-03  Replace global logger  (high risk, 3 steps)

回复格式：
  approve all
  reject all
  approve RP-01 RP-03
  approve RP-01; defer RP-02; reject RP-03
```

你回复后，Skill 把 approved 的项作为新步骤插到 `plan/steps.md` 对应位置（依赖顺序自动处理），把 deferred 的项记在 `DESIGN.md` 末尾的 follow-up TODO 里，rejected 的项原地写 "实现需要绕过它"。

**Phase 4 中途**如果发现新的不合理代码挡住了实现，也会触发同一个门——append 到 `refactor_proposals.md` 暂停等你回复，**不会偷偷重构**。

---

## 常用操作

### 继续执行（断点续传）

```
继续
```

或

```
evolve
```

会自动跳到 `state.json` 里上次停下的 phase / step / round。

### 查看进度

```
evolve --status
```

输出当前 phase、已完成步骤数、下一步、重构决策状态等。

### 一次跑完所有步骤（慎用）

在 Phase 4 时：

```
evolve --run-all-steps
```

连续跑步骤，直到全部完成 / 遇到 blocker / 触发重构门 / 上下文饱和。

### 跳过重构建议（不要任何重构）

```
evolve --skip-refactor
```

Phase 3 不会生成重构提案，全程不暂停。适合"求快、不动现有代码"场景。

### 重做某个阶段

```
evolve --reset-phase 3
```

把 phase 3 标 pending，清掉 `.evolve/plan/`、`.evolve/coverage/`、`.evolve/DESIGN.md`，下次调用会从 phase 3 重新开始。**只清 Skill 自己的产物，不会动你 repo 里原有的代码。**

### 一次只跑一个阶段（关闭自动推进）

一次性禁用：

```
evolve --no-auto
```

永久禁用（写入 state）：

```
evolve --step-only
```

### state 损坏了修复

```
evolve --repair
```

从 `.evolve/` 里已存在文件反推状态，重建 `state.json`。

---

## 典型流程示例

```
你: evolve ./prd/mute-user.md

Agent: [Phase 0] 识别到 go 项目（go.mod），项目目录 ./
       state.json 已创建。自动进入 Phase 1…
       [Phase 1] req/ 6 份、design/ 5 份、api/ 4 份写完。
       记录 2 条 assumptions（PRD 没明确，已默认决策并落盘）。
       自动进入 Phase 2…
       [Phase 2] arch_scan/ 4 份写完（识别到 chi+sqlc+slog+testify 栈）。
       tests/ 3 份写完（unit 24 条、interface 9 条）。
       自动进入 Phase 3…
       [Phase 3] 拆出 11 个步骤。生成 3 条重构建议：
         RP-01  Hoist user-lookup helper  (low, 1 step)
         RP-02  Split god-function OrderProcess  (medium, 2 steps)
         RP-03  Replace global logger  (high, 3 steps)
       已停。回复 approve/reject/defer。

你: approve RP-01; defer RP-02; reject RP-03

Agent: 重构决策已记录。RP-01 插入为 Step 02。
       自动进入 Phase 4 第一步…
       [Phase 4 - 01/12] add migration + repo methods
       写入 migrations/0042_add_muted_until.sql, internal/repo/user.go (修改 +44/-2)
       单元测试 3/3 通过。已停。说"继续"跑下一步。

你: 继续

Agent: [Phase 4 - 02/12] hoist user-lookup helper (RP-01)
       …

（… 12 步完成 …）

Agent: [Phase 4 全部完成] 自动进入 Phase 5 第 1 轮…
       [Phase 5 - 第 1 轮] 全量 185 条，183 通过 / 2 失败。
       本轮修 service/mute 模块的 2 条失败。已停。

你: 继续

Agent: [Phase 5 - 第 2 轮] 全量 185 条全绿。
       coverage 91%。自动进入 Phase 6…
       [Phase 6] 已写 .evolve/DESIGN.md（1240 词）。
       全部完成：新增 6 文件 / 改 4 文件，+820 / -38 行，新增测试 33 条。
```

---

## 你的 8 条需求映射

| 需求 | 对应阶段 / 机制 |
|---|---|
| 1. 理解需求，先做顶层设计 + 对外接口设计，分门别类存储 | Phase 1：`req/`（需求） / `design/`（顶层设计） / `api/`（对外接口）三个分类目录 |
| 2. 在熟悉现有架构上设计单元测试 + 接口测试 | Phase 2：先 `arch_scan/` 吃透现有代码，再写 `tests/unit_plan.md` + `tests/interface_plan.md` |
| 3. 编码时重视架构、分层合理、高内聚低耦合 | Phase 2 `arch_scan/conventions.md` 提取约定；Phase 3 步骤设计严守层次；Phase 4 每步必须匹配现有 conventions（详见 `../PRINCIPLES.md` Tier 2/3） |
| 4. 遇到不合理代码及时重构，**重构前确认** | Phase 3 + Phase 4 中途的"重构建议门"——这是 Skill 唯一会暂停的地方，不批准就不动 |
| 5. YAGNI/DRY/KISS/SRP，函数 ≤ 200 行 | Phase 4 每步 done 前过 `QUALITY_GATES.md` checklist + `../PRINCIPLES.md` Tier 1，函数 200 行硬上限 |
| 6. 测试回归到 bug 清零 | Phase 5 循环，每轮 ≤ 5 失败或 1 模块，0 失败才进 Phase 6 |
| 7. 最终一份设计文档（代码结构 + 使用说明） | Phase 6 只输出 `.evolve/DESIGN.md`，硬规定一份、≤ 1500 词，包含必需章节 |
| 8. 默认授权、不二次确认 | 除"重构建议门"外全程不 prompt；所有决策直接落盘 |

---

## 与 skills/design、skills/rewrite 的区别

| 维度 | design | rewrite | **evolve** |
|---|---|---|---|
| 起点 | 产品需求（无代码） | 已有源码（要移植到新语言） | **已有代码库（要加功能/改造）** |
| 是否需要熟悉现有架构 | 否 | 是（源代码） | **是（仍是同一份代码库）** |
| 重构 | N/A | N/A | **核心：先提案再动** |
| 文档产出 | 5 份 | 类似 | **只 1 份** |
| 函数上限 | 40 行（软） | 40 行（软） | **200 行（硬）** |
| 暂停点 | 无 | Phase 3 等 approve | **重构门 + 每步 + 每轮** |
| 典型调用 | `design <prd>` | `rewrite <repo> <lang>` | **`evolve <change-spec>`** |
| 共享准则 | `../PRINCIPLES.md` | `../PRINCIPLES.md` | `../PRINCIPLES.md` |

---

## 故障排查

**Agent 没识别到 skill？**
- 用 `head -n 15 ~/.cursor/skills/evolve/SKILL.md` 检查 frontmatter
- 重启对话窗口
- 把 SKILL.md 第一段 description 粘给它，说"按这个 skill 跑"

**Agent 在重构以外的地方还在问"是否继续？"**
- 提醒它："SKILL.md 写明默认授权，只有 refactor_proposals 非空时才停"
- 把 SKILL.md "Core Principles" 1 + 2 粘给它

**Agent 偷偷重构了现有代码（没走门）**
- 退回该 step：`evolve --reset-phase 4` 后重新跑（会从 plan 重排）
- 或手动 `git checkout` 那些被改的文件，告诉它"那次改动不算，按重构门流程来"

**做出来的设计不符合预期？**
- 别手改代码（会和 state 不同步）
- `evolve --reset-phase 1` 重写需求/设计后再跑

**步骤拆得太碎 / 太粗？**
- `evolve --reset-phase 3` 重写 `plan/steps.md`，可以直接编辑后再 `evolve --repair` 同步状态

**state.json 丢了？**
- `evolve --repair` 反推重建

**测试一直修不完（同一模块 3 轮还失败）？**
- Skill 会在 `coverage/failures.md` 标记 "structural" 并提议触发重构门——按门流程处理即可

---

## 下一步

```
evolve <你的需求来源> [项目目录]
```

然后等它跑完 Phase 0~3，处理一次重构门，再按 "继续" 推进每个 step / 每轮回归即可。最终在 `<项目目录>/.evolve/DESIGN.md` 收一份代码结构 + 使用说明就完事了。
