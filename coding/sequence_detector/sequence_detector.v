// ============================================================================
// 【知识点】
//
// 【1. 状态机设计（Moore 型）】
//    - 本模块为 Moore 型状态机：状态数 S=9（IDLE~H），检测序列 1010_1101（8bit）
//    - Moore 型特点: 输出只依赖当前状态(current_state)，不直接依赖输入信号
//    - 输出: match=1 仅在状态机处于 H 状态时成立，与输入序列无关
//    - 状态转移由输入 sequence 决定，每拍输入 1bit，8 拍完成一次检测
//    - 状态转移规律:
//        IDLE --1--> A        A --1--> A（保持在A）  A --0--> B
//        B --1--> C            C --1--> A（部分重叠） C --0--> D
//        D --1--> E            E --1--> F            E --0--> D
//        F --1--> A（部分重叠）F --0--> G
//        G --1--> H            G --0--> IDLE
//        H --1--> A            H --0--> B（部分重叠，下一个序列从 B 开始）
//
// 【2. 状态编码宽度】
//    - current_state/next_state 位宽: $clog2(DATA_WIDTH)+1-1 = $clog2(8) = 3，即 4bit（0~15）
//    - 9 个状态（0~8）需要 4bit，4bit 可表示 0~15，足够容纳
//    - 'b0 赋值给 4bit 寄存器时 Verilog 自动零扩展为 4'b0000，安全
//    - 建议显式写作 {STATE_WIDTH{1'b0}} 或 '0 更规范
//
// 【3. 两段式状态机】
//    - 段1: 时序逻辑 always 块，用 clk 同步更新 current_state <= next_state
//    - 段2: 组合逻辑 always 块，根据 current_state 和输入计算 next_state
//    - 两段式避免组合逻辑环路，是标准写法
//
// 【4. match 输出逻辑】
//    - 当前代码: assign level = (next_state == H)，纯组合逻辑，输出跟随 next_state
//    - 注意: next_state 在当前时钟沿计算，下一拍才更新到 current_state
//    - 若希望 match 只在检测到序列的**那一个时钟周期**成立，应使用:
//        always @(posedge clk) match <= (current_state == H);
//      即基于 current_state 寄存输出，输出会比 next_state 晚一拍
//    - 当前实现 match 在状态 H 期间始终为 1，属于电平输出而非单脉冲
//
// 【5. 部分重叠（Overlapping）检测】
//    - 当前状态机为"部分重叠"模式：检测到 H 后，下一个 0 不是从 IDLE 开始而是从 B 开始
//      意味着检测到 10101101 后，如果下一 bit=0，下一个序列可能从 B 开始（1010_11xx...）
//    - 非重叠模式: H 之后强制回到 IDLE，必须重新开始完整 8bit 序列
//    - 选择哪种模式取决于应用需求，本设计采用部分重叠以提高检测灵敏度
//
// 【6. DATA_WIDTH 参数】
//    - 参数定义为 8，表示待检测序列的总位数
//    - 注意: 当前代码中 DATA_WIDTH 仅用于计算状态寄存器位宽，未参与状态转移逻辑
//    - 若要支持任意长度序列的参数化，应在状态转移逻辑中动态使用 DATA_WIDTH
// ============================================================================

module sequence_detector #(
    parameter DATA_WIDTH = 8
) (
    input clk, rst_n,
    // detect 8'b1010_1101
    input sequence,
    output reg match
);

    localparam  IDLE = 0;
    localparam  A = 1;
    localparam  B = 2;
    localparam  C = 3;
    localparam  D = 4;
    localparam  E = 5;
    localparam  F = 6;
    localparam  G = 7;
    localparam  H = 8;
    

    reg [$clog2(DATA_WIDTH) + 1 - 1 : 0] current_state, next_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            match <= 1'b0;
        end

        else if (current_state == H) begin
            match <= 1'b1;
        end

        else begin
            match <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= 'b0;
        end

        else begin
            current_state <= next_state;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            next_state <= 'b0;
        end

        else begin
        case (current_state)
            IDLE: begin
                if (sequence) next_state <= A;
                else next_state <= IDLE;
            end 

            A: begin
                if (sequence) next_state <= A;
                else next_state <= B;
            end 

            B: begin
                if (sequence) next_state <= C;
                else next_state <= IDLE;
            end 

            C: begin
                if (sequence) next_state <= A;
                else next_state <= D;
            end 

            D: begin
                if (sequence) next_state <= E;
                else next_state <= IDLE;
            end 

            E: begin
                if (sequence) next_state <= F;
                else next_state <= D;
            end 

            F: begin
                if (sequence) next_state <= A;
                else next_state <= G;
            end 

            G: begin
                if (sequence) next_state <= H;
                else next_state <= IDLE;
            end 

            H: begin
                if (sequence) next_state <= A;
                else next_state <= B;
            end 
            
            default: next_state <= IDLE;
        endcase
        end
    end
endmodule
