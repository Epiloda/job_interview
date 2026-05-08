// ============================================================================
// 同步FIFO 知识点总结
// ============================================================================
//
// 【1. 同步FIFO的核心特点】
//    - 读写共用同一时钟 clk，不存在跨时钟域问题，设计比异步FIFO简单
//    - 读写指针可以直接在同一时钟域内比较，无需 Gray 码或两级同步器
//    - 适用场景：单时钟域内的数据缓冲、速率匹配、握手解耦
//
// 【2. 为什么指针需要扩展1bit？】
//    - FIFO深度 DATA_DEPTH=128，地址范围 0~127，需要 7bit ($clog2(128)=7)
//    - 指针扩展1bit → ADDR_WIDTH=$clog2(128)+1=8bit
//    - 如果只用 7bit，"空"和"满"都是 wr_addr == rd_addr，无法区分
//    - 扩展1bit后: 最高位(MSB)记录指针"绕圈次数的奇偶"
//      * 同圈(MSB相同) 且低位相同  → wr == rd → FIFO 空
//      * 异圈(MSB不同) 且低位相同  → 写比读多走一整圈 → FIFO 满
//
// 【3. 满/空判断逻辑】
//    - empty = (wr_addr == rd_addr)
//      整个指针(含MSB)相等，说明写追不上读或初始状态，FIFO 空
//    - full  = (wr_addr[MSB] != rd_addr[MSB])
//           && (wr_addr[低位] == rd_addr[低位])
//      MSB不同说明写指针多绕一圈，低位又追上读指针 → FIFO 满
//
// 【4. 地址回绕逻辑（当 DATA_DEPTH 不是2的幂次时尤其重要）】
//    - 若 DATA_DEPTH 是2的幂次(如128)，地址低位自然溢出回零，无需显式回绕
//    - 若 DATA_DEPTH 不是2的幂次(如100)，地址低位不能自然溢出，必须显式检测
//      条件: addr[低位] == DATA_DEPTH - 1 → MSB取反，低位清零
//    - 本模块用显式回绕，兼容任意 DATA_DEPTH（包括非2幂次）
//
// 【5. 常见Bug总结】
//    (a) 读数据时地址下标用了 DATA_WIDTH 而非 ADDR_WIDTH → 下标远超地址范围，读到错误地址
//    (b) 地址回绕条件比较完整指针而非低位 → 第二圈 MSB=1 时条件永远不满足，地址越界
//    (c) wr_addr 递增未检查 full → FIFO 满时指针仍递增，与写数据逻辑不一致
//    (d) 时序 always 块中混用阻塞赋值 = → 综合与仿真行为可能不一致，应统一用 <=
//
// ============================================================================

module sync_fifo #(
    // 如果DATA_DEPTH不是2的幂次？
    parameter DATA_DEPTH = 128,
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = $clog2(DATA_DEPTH) + 1
) (
    input clk, rst_n,

    input wr_en,
    input [DATA_WIDTH - 1 : 0] data,
    input rd_en,

    output full, empty,
    output reg [DATA_WIDTH - 1 : 0] out_data
);
    
    reg [DATA_WIDTH - 1 : 0] mem [DATA_DEPTH - 1 : 0];
    reg [ADDR_WIDTH - 1 : 0] wr_addr, rd_addr;

    // write
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < DATA_DEPTH; i = i + 1) begin
                mem[i] <= 'b0;
            end
        end

        else if (wr_en & (!full)) begin
            mem[wr_addr[ADDR_WIDTH - 2 : 0]] <= data;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_addr <= 'b0;
        end

        else if (wr_en & (!full)) begin
            if (wr_addr[ADDR_WIDTH - 2 : 0] == DATA_DEPTH - 1'b1) begin
                wr_addr[ADDR_WIDTH - 1] <= ~wr_addr[ADDR_WIDTH - 1];
                wr_addr[ADDR_WIDTH - 2 : 0] <= 'b0;
            end

            else begin
                wr_addr <= wr_addr + 1'b1;
            end
        end

        else begin
            wr_addr <= wr_addr;
        end
    end

    // read
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_data <= 'b0;
        end

        else if (rd_en & !(empty)) begin
            out_data <= mem[rd_addr[ADDR_WIDTH - 2 : 0]];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_addr <= 'b0;
        end

        else if (rd_en & (!empty)) begin
            if (rd_addr[ADDR_WIDTH - 2 : 0] == DATA_DEPTH - 1'b1) begin
                rd_addr[ADDR_WIDTH - 1] <= ~rd_addr[ADDR_WIDTH - 1];
                rd_addr[ADDR_WIDTH - 2 : 0] <= 'b0;
            end

            else begin
                rd_addr <= rd_addr + 1'b1;
            end
        end

        else begin
            rd_addr <= rd_addr;
        end
    end

    assign full = (wr_addr[ADDR_WIDTH - 1] != rd_addr[ADDR_WIDTH - 1]) 
               && (wr_addr[ADDR_WIDTH - 2 : 0] == rd_addr[ADDR_WIDTH - 2 : 0]);
    assign empty = wr_addr == rd_addr;
endmodule
