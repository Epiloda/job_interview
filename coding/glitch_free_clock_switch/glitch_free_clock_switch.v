// ============================================================================
// 【知识点】
//
// 【1. 无毛刺时钟切换（Glitch-Free Clock Switching）问题背景】
//    - 直接用 MUX 或组合逻辑选择时钟会产生毛刺：时钟边沿交错时会出现尖峰
//    - 示例: clk_out = sel ? clk1 : clk0，若 sel 在 clk0 高电平期间变化，
//      clk_out 可能产生极窄的 glitch 脉冲，导致后级电路误触发
//    - 解决方案: 在切换时钟时，确保旧时钟完全关闭后，新时钟才开启
//
// 【2. 本模块架构（双路径握手式）——有 BUG，详见第 5 条】
//    - clk0 路径: clk0_dff0 → clk0_dff1 → clk0_masked = clk0 & clk0_dff1
//    - clk1 路径: clk1_dff0 → clk1_dff1 → clk1_masked = clk1 & clk1_dff1
//    - clk_out = clk0_masked | clk1_masked，两个路径互斥
//    - 切换时序 (sel=0 → sel=1):
//        Step1: clk1_dff0 在 clk1 下降沿采样 sel & ~clk0_dff1，开始拉高
//        Step2: clk1_dff1 寄存 clk1_dff0，确认 clk1 已接管
//        Step3: clk0_dff0 在 clk0 下降沿检测到 ~clk1_dff1=0，停止拉高
//        Step4: clk0_dff1 寄存 clk0_dff0，确认 clk0 已关闭
//      三重保障: 旧时钟必须经历至少一个完整周期 + 两级 DFF 同步延迟
//
// 【3. 为什么用时钟下降沿触发 always 块？】
//    - 下降沿触发使 clk0 路径和 clk1 路径分别在各自时钟的低电平期间更新
//    - clk0_masked 只在 clk0 低电平时可能变化（clk0=0 时 AND 结果必为 0）
//    - clk1_masked 只在 clk1 低电平时可能变化（clk1=0 时 AND 结果必为 0）
//    - 关键: 旧时钟关闭(clk_masked=0)和新时钟开启(clk_masked=1)都在低电平发生
//      避免在高电平切换导致短脉冲突现
//    - 注意: 本模块的 always @(negedge clk0) 不是跨时钟域同步，而是受控于目标时钟
//
// 【4. 两级 DFF 同步器的作用】
//    - 第一级(dff0): 采样握手信号，消除亚稳态风险
//    - 第二级(dff1): 稳定输出，作为时钟门控的 enable 信号
//    - 只有 dff1=1 时，clk_masked 才可能为 1，保证时钟切换安全
//
// 【5. 现有代码的 BUG — Line 36 自我反馈】
//    - 错误代码: always @(negedge clk1) clk1_dff1 <= clk1_dff1;  // 自反馈
//    - 正确应为: always @(negedge clk1) clk1_dff1 <= clk1_dff0;
//    - 后果: clk1_dff1 永远停在复位值 0，clk1_masked = clk1 & 0 = 0
//      即无论 sel=0/1，clk1 路径永远无法开启，模块只能输出 clk0，无法切换
//    - 同样的架构，clk0 路径（Line 23）是正确的: clk0_dff1 <= clk0_dff0
//    - 教训: 检查每个 DFF 的 D 输入是否是前级输出，而非自身反馈
//
// 【6. clk 作为模块内部时钟的问题】
//    - 本模块用 clk0/clk1 作为 always 块的时钟信号，是"用外部时钟驱动内部逻辑"
//    - 正常 CDC 跨时钟域用两级同步器；这里是"同一信号在不同时钟域间交叉"
//    - sel 变化时，clk1_dff0 在 clk1 下降沿采样，若 sel 变化恰好在 clk1 下降沿附近，
//      可能违反 DFF 的 setup/hold 时间，产生亚稳态
//    - 改进方案: 先将 sel 用两级 DFF 同步到 clk0/clk1 时钟域，再参与握手逻辑
//
// 【7. 复位与初始状态】
//    - 复位时 clk0_dff0=1, clk0_dff1=1 → clk0_masked=1（默认选 clk0）
//              clk1_dff0=0, clk1_dff1=0 → clk1_masked=0（clk1 关闭）
//    - clk0_dff0 硬编码为 1'b1 不依赖 sel，保证了复位后 clk0 默认开启
//    - 实际应用中，复位释放后需要等待时钟切换序列完成才能稳定切换
//
// 【8. 参数化扩展】
//    - 当前 sel 是 1bit，只能在 clk0/clk1 二选一
//    - 多路时钟切换（如 4 选 1）需要使用 one-hot 编码的状态机管理各路优先级
//    - 核心原则不变: 任何时刻最多只有一路时钟被启用
// ============================================================================

module glitch_free_clock_switch (
    input clk0, clk1,
    input rst_n,
    input sel,

    output clk_out
);
    reg clk0_dff0, clk0_dff1;
    reg clk1_dff0, clk1_dff1;

    wire clk0_masked;
    wire clk1_masked;

    // default sel clk0, when clk1_masked completely shutdown, switch to clk0 
    always @(negedge clk0 or negedge rst_n) begin
        if (!rst_n) begin
            clk0_dff0 <= 1'b1;
            clk0_dff1 <= 1'b1;
        end

        else begin
            clk0_dff0 <= (!sel) & (!clk1_dff1);
            clk0_dff1 <= clk0_dff0;
        end
    end

    // when clk0_masked completely shutdown, switch to clk1
    always @(negedge clk1 or negedge rst_n) begin
        if (!rst_n) begin
            clk1_dff0 <= 1'b0;
            clk1_dff1 <= 1'b0;
        end

        else begin
            clk1_dff0 <= sel & (!clk0_dff1);
            clk1_dff1 <= clk1_dff0;  // FIX: 原代码 clk1_dff1 <= clk1_dff1 是 BUG
        end
    end

    assign clk0_masked = clk0 & clk0_dff1;
    assign clk1_masked = clk1 & clk1_dff1;

    assign clk_out = clk0_masked | clk1_masked;
endmodule
