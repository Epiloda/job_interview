// ============================================================================
// 【知识点】
//
// 【1. 参数化设计】
//    - CNT_NUMBER: 计数器上限值（计数值范围 0 ~ CNT_NUMBER-1）
//    - DATA_WIDTH = $clog2(CNT_NUMBER): 计数器的位宽必须能容纳最大的计数值
//    - 例: CNT_NUMBER=8 时，计数范围 0~7，$clog2(8)=3，cnt 为 3bit，足够表示 0~7
//    - 注意: $clog2() 向上取整，当 CNT_NUMBER 不是 2 的幂次时会产生冗余状态
//      例: CNT_NUMBER=10，$clog2(10)=4，cnt 可表示 0~15，但有效状态仅为 0~9
//      超出范围的 10~15 不会被访问到（cnt==9 后下一个为 0），不影响功能但浪费状态
//
// 【2. 复位信号设计】
//    - 异步复位: always @(posedge clk or negedge rst_n)，复位信号不依赖时钟
//    - 低有效复位 (!rst_n): 0=复位有效，1=正常工作，与 ASIC 中常见的低复位一致
//    - 复位时 cnt 清零，与计数器初始状态一致，避免上电后的不定态
//
// 【3. 计数溢出保护】
//    - 计到 CNT_NUMBER-1 后下一个时钟周期清零，重新从 0 开始
//    - 避免了计数器超出预期范围后继续递增的问题
//    - 无专职 overflow 标志位，由 cnt==CNT_NUMBER-1 的比较结果隐式给出
//
// 【4. 位宽扩展问题】
//    - 'b0 是宽度为 1 的字面量，赋值给宽信号时 Verilog 会自动零扩展
//    - 但为明确起见，建议写作 {DATA_WIDTH{1'b0}}，显式填满 DATA_WIDTH 位宽
//    - 本模块 cnt 宽度由参数决定，'b0 可正常工作，但显式写法更规范
//
// 【5. $clog2() 系统函数】
//    - $clog2(N) = ceil(log2(N))，返回能表示 0~N-1 所需的最少比特数
//    - $clog2(8) = 3, $clog2(10) = 4, $clog2(1) = 0
//    - 例: 要计到 15 需要 4bit，$clog2(16)=4；计到 16 需要 5bit，$clog2(17)=5
// ============================================================================

module N_bit_cnt #(
    parameter CNT_NUMBER = 8,
    parameter DATA_WIDTH = $clog2(CNT_NUMBER)
)(
    input clk, rst_n,
    output reg [DATA_WIDTH - 1 : 0] cnt
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 'b0;
        end

        else if (cnt == CNT_NUMBER - 1) begin
            cnt <= 'b0;
        end

        else begin
            cnt <= cnt + 1'b1;
        end
    end
endmodule
