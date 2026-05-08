# 实习面试手撕代码

本仓库记录实习面试中遇到的手撕代码题目及其实现。

---

## 1. 异步 FIFO

- **文件**：[coding/async_fifo/async_FIFO.v](coding/async_fifo/async_FIFO.v)
- **语言**：Verilog
- **知识点**：
  - 跨时钟域处理（CDC）— Gray 码 + 两级同步器消除亚稳态
  - 指针扩展 1 bit 区分空/满（$N$ 深度用 $N+1$ 位指针）
  - 空满判断策略：保守满（更早说满，保证不溢出）、乐观空（更晚说空）
  - 参数化设计，支持任意深度和数据位宽

---

## 2. 同步 FIFO

- **文件**：[coding/sync_fifo/sync_fifo.v](coding/sync_fifo/sync_fifo.v)
- **语言**：Verilog
- **知识点**：
  - 计数器法判断满/空 — 支持非 2 幂次深度（扩展 1 bit 法仅适用于 2^n）
  - 阻塞赋值 vs 非阻塞赋值 — 时序 always 块必须统一使用 <=
  - 写满/读空保护 — 满时禁止写，空时禁止读
  - mem 复位 off-by-one 错误 — 循环边界需写对

---

## 3. N 位计数器

- **文件**：[coding/N_bit_cnt/N_bit_cnt.v](coding/N_bit_cnt/N_bit_cnt.v)
- **语言**：Verilog
- **知识点**：
  - 参数化设计 — $clog2() 计算计数器的位宽
  - 异步低有效复位 — always @(posedge clk or negedge rst_n)
  - 计数溢出保护 — 计到 CNT_NUMBER-1 后清零
  - 非阻塞赋值 — always 块内统一使用 <=

---

## 4. 序列检测器

- **文件**：[coding/sequence_detector/sequence_detector.v](coding/sequence_detector/sequence_detector.v)
- **语言**：Verilog
- **检测序列**：1010_1101
- **知识点**：
  - Moore 型状态机 — 输出仅依赖当前状态
  - 两段式状态机 — 组合逻辑计算 next_state，时序逻辑更新 current_state
  - 部分重叠（Overlapping）检测 — H 状态后遇到 0 从 B 开始继续检测
  - $clog2() 计算状态编码位宽

---

## 5. 无毛刺时钟切换器

- **文件**：[coding/glitch_free_clock_switch/glitch_free_clock_switch.v](coding/glitch_free_clock_switch/glitch_free_clock_switch.v)
- **语言**：Verilog
- **知识点**：
  - Glitch-Free 原理 — 旧时钟完全关闭后新时钟才开启，避免组合逻辑选通产生的毛刺
  - 双路径握手架构 — clk0/clk1 各走一条路径，互斥输出
  - 下降沿触发起始 — 低电平期间切换，避免高电平切换产生 glitch
  - 两级 DFF 同步器 — dff0 采样 + dff1 稳定输出
  - 典型 BUG：时钟门控信号自反馈导致路径失效
