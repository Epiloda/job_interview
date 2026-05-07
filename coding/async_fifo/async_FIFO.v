// ============================================================================
// 异步FIFO 知识点总结
// ============================================================================
//
// 【1. 异步FIFO的核心问题】
//    - 读写时钟来自不同的时钟域，频率和相位均无固定关系
//    - 需要在不跨时钟域直接"比较"读写指针的前提下，正确判断FIFO的满/空
//
// 【2. 为什么指针需要扩展1bit？】
//    - FIFO深度 DATA_DEPTH=32，实际地址范围 0~31，需要 5bit (ADDR_WIDTH=$clog2(32)=5)
//    - 指针扩展1bit → POINTER_WIDTH=$clog2(32)+1=6bit
//    - 6bit指针可取 0~63，地址取低5bit(0~31)，最高位用于区分"写指针绕了一圈"
//    - 二进制指针: w_ptr=33(10_0001), r_ptr=1(00_0001)，低5bit相同但高bit不同 → 写比读多走一圈 → FIFO已满
//    - 若只用5bit指针，无法区分"空(都=0)"和"满(写回到0读数一轮=32=0)"，必须扩展1bit
//
// 【3. 为什么跨时钟域要用Gray码？】
//    - 二进制指针跨时钟域时，如果多bit同时翻转(如 0111→1000)，在异步采样时可能采到任意中间值(如 1111)
//    - Gray码每次只翻转1bit，即使采样到了旧值，最多是"滞后一拍"，不会采样到不存在于编码表中的非法值
//    - Gray码是一个双射(一一映射)，所以 Gray(A) == Gray(B) ⟺ A == B，可直接用于相等判断
//
// 【4. 两级同步器(2-FF Synchronizer)】
//    - 异步信号先经过两级目标时钟域的触发器，消除亚稳态
//    - 写指针 Gray 码 → r_clk 打两拍 → w_pointer_d1, w_pointer_d2 (读侧采样到的写指针，已落后2拍)
//    - 读指针 Gray 码 → w_clk 打两拍 → r_pointer_d1, r_pointer_d2 (写侧采样到的读指针，已落后2拍)
//    - 这2拍延迟是异步FIFO"偏保守"的根本原因
//
// 【5. 满/空判断逻辑 (均在Gray码域完成)】
//    
//    (a) Empty 判断: 读时钟域
//        empty = (w_pointer_d2 == r_gray_pointer)
//        含义: 读侧看到的写指针 == 当前的读指针 → 读追上写 → FIFO空
//        CDC延迟方向: w_pointer_d2是落后2拍的旧写指针，实际写指针可能已经又写了数据
//        → 延迟说"不空"而实际已空 → 读侧多读一两个数据 → 过期数据 ← 设计保证读协议不会在空后继续读
//
//    (b) Full 判断: 写时钟域
//        full = (r_pointer_d2[MSB] != w_gray_pointer[MSB]) &
//               (r_pointer_d2[MSB-1] != w_gray_pointer[MSB-1]) &
//               (r_pointer_d2[余下位] == w_gray_pointer[余下位])
//        含义: 高2bit不同，低bit相同 → 写比读多绕一圈 → FIFO满
//        Gray码圈数判断: 当指针循环一圈回到起点，Gray高2bit会翻转
//        CDC延迟方向: r_pointer_d2是落后2拍的旧读指针，实际读指针可能已经又读走数据了
//        → 延迟说"满"而实际已空 → 写侧暂停写，不会溢出 ← 安全的"偏保守"
//    
//    (c) "Conservative Full, Optimistic Empty" 总结:
//        Full  偏保守: 旧读指针还未更新，认为更满 → 更早地说"满" → 不会溢出(安全)
//        Empty 偏乐观: 旧写指针还未更新，认为更空 → 更晚地说"空" → 读侧多读(由上层协议保证不连续读空FIFO)
//
// 【6. 参数说明】
//    - DATA_WIDTH : 每笔数据的位宽
//    - DATA_DEPTH : FIFO存储深度(必须是2的幂次，原因: 需要用$clog2取整+Gray码特性依赖2^n均匀翻转)
//    - ADDR_WIDTH = $clog2(DATA_DEPTH) : 实际SRAM地址线宽
//    - POINTER_WIDTH = $clog2(DATA_DEPTH) + 1 : 扩展1bit的指针位宽，用于区分空/满
//
// 【7. 时序注意事项】
//    - 所有always块中统一使用 <= (非阻塞赋值)，保证仿真和综合行为一致(w_addr在always块外assign为组合)
//    - mem写入用 <= 与时序中对齐，依赖两级同步延迟是异步FIFO设计的固有特性
//    - empty/full 为组合输出，实际应用中可打一拍寄存器去毛刺
// ============================================================================

module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DATA_DEPTH = 32,                                   // FIFO深度，必须是2的幂次
    parameter POINTER_WIDTH = $clog2(DATA_DEPTH) + 1,            // 指针扩展1bit用于区分空/满
    parameter ADDR_WIDTH = $clog2(DATA_DEPTH)                    // 实际SRAM地址线宽
)(
    // ---------- 写时钟域 ----------
    input w_clk,
    input w_rstn,
    input w_en,
    input [DATA_WIDTH - 1 : 0] w_data, 

    // ---------- 读时钟域 ----------
    input r_clk,
    input r_rstn,
    input r_en,
    output reg [DATA_WIDTH - 1 : 0] r_data, 

    // ---------- 标志信号 (组合输出) ----------
    output empty,                                               // FIFO空标志(读时钟域)
    output full                                                 // FIFO满标志(写时钟域)
);

    // =========================================================================
    // 存储阵列: 双端口RAM模型 (异步时钟直接访问)
    // =========================================================================
    reg [DATA_WIDTH - 1 : 0] mem [DATA_DEPTH - 1 : 0];

    // =========================================================================
    // 读写指针 (扩展1bit, 均在各自的时钟域)
    //   w_pointer: 0→63, 低 ADDR_WIDTH bit 是实际写地址
    //   r_pointer: 0→63, 低 ADDR_WIDTH bit 是实际读地址
    //   MSB 用于判断是否"多绕了一圈"
    // =========================================================================
    reg [POINTER_WIDTH - 1 : 0] w_pointer, r_pointer;

    // =========================================================================
    // 地址提取: 取指针低 ADDR_WIDTH bit 作为SRAM地址
    // =========================================================================
    wire [ADDR_WIDTH - 1 : 0] w_addr, r_addr;

    // =========================================================================
    // Gray码指针 (组合逻辑产生, 用于跨时钟域传输)
    //   转换公式: gray = binary ^ (binary >> 1)
    //   特点: 相邻值只有1bit翻转, 适合异步采样
    // =========================================================================
    wire [POINTER_WIDTH - 1 : 0] w_gray_pointer, r_gray_pointer;

    // =========================================================================
    // 两级同步器: 消除亚稳态的核心结构
    //   w_pointer_d1/d2: 写指针Gray → r_clk打两拍 → 读时钟域的写指针快照(落后2拍)
    //   r_pointer_d1/d2: 读指针Gray → w_clk打两拍 → 写时钟域的读指针快照(落后2拍)
    // =========================================================================
    reg [POINTER_WIDTH - 1 : 0] w_pointer_d1, w_pointer_d2;     // 读时钟域
    reg [POINTER_WIDTH - 1 : 0] r_pointer_d1, r_pointer_d2;     // 写时钟域

    // =========================================================================
    // 写逻辑
    // =========================================================================
    assign w_addr = w_pointer[POINTER_WIDTH - 2 : 0];           // 取指针低 ADDR_WIDTH bit 为写地址
    always @(posedge w_clk or negedge w_rstn) begin
        if (w_en & (!full)) begin                               // 仅在非满且写使能有效时写入
            mem[w_addr] <= w_data;                              // (使用非阻塞赋值与时序对齐)
        end
    end

    // =========================================================================
    // 写指针递增
    //   满时不递增 → 避免覆盖未被读走的数据
    // =========================================================================
    always @(posedge w_clk or negedge w_rstn) begin
        if (!w_rstn) begin
            w_pointer <= 'b0;
        end
        else if (w_en & !(full)) begin
            w_pointer <= w_pointer + 1'b1;                      // 非满时写+1
        end
        else begin
            w_pointer <= w_pointer;                             // 满时保持(饱和保护)
        end
    end

    // =========================================================================
    // 读逻辑
    // =========================================================================
    assign r_addr = r_pointer[POINTER_WIDTH - 2 : 0];           // 取指针低 ADDR_WIDTH bit 为读地址
    always @(posedge r_clk or negedge r_rstn ) begin
        if (r_en & !(empty)) begin                              // 仅在非空且读使能有效时读出
            r_data <= mem[r_addr];
        end
    end

    // =========================================================================
    // 读指针递增
    //   空时不递增 → 避免读出无效数据
    // =========================================================================
    always @(posedge r_clk or negedge r_rstn) begin
        if (!r_rstn) begin
            r_pointer <= 'b0;
        end
        else if (r_en & !(empty)) begin
            r_pointer <= r_pointer + 1'b1;                      // 非空时读+1
        end
        else begin
            r_pointer <= r_pointer;                             // 空时保持(饱和保护)
        end
    end

    // =========================================================================
    // 跨时钟域同步: 写指针Gray → 两级同步 → 读时钟域
    //   Step 1: 二进制 → Gray码 (组合逻辑,公式 gray = binary ^ (binary >> 1))
    //   Step 2: Gray码通过两级 D FF 打入读时钟域，消除亚稳态
    //   w_pointer_d2 = 读侧看到的"2拍前的写指针Gray值"
    // =========================================================================
    assign w_gray_pointer = w_pointer ^ (w_pointer >> 1);       // 二进制→Gray转换

    always @(posedge r_clk or negedge r_rstn) begin
        if (!r_rstn) begin
            w_pointer_d1 <= 'b0;
            w_pointer_d2 <= 'b0;
        end
        else begin
            w_pointer_d1 <= w_gray_pointer;                     // 第1拍采样(Gray码每次只变1bit)
            w_pointer_d2 <= w_pointer_d1;                       // 第2拍,消除亚稳态后的稳定值
        end
    end

    // =========================================================================
    // 跨时钟域同步: 读指针Gray → 两级同步 → 写时钟域
    //   r_pointer_d2 = 写侧看到的"2拍前的读指针Gray值"
    // =========================================================================
    assign r_gray_pointer = r_pointer ^ (r_pointer >> 1);       // 二进制→Gray转换

    always @(posedge w_clk or negedge w_rstn) begin
        if (!w_rstn) begin
            r_pointer_d1 <= 'b0;
            r_pointer_d2 <= 'b0;
        end
        else begin
            r_pointer_d1 <= r_gray_pointer;                     // 第1拍采样
            r_pointer_d2 <= r_pointer_d1;                       // 第2拍,稳定值
        end
    end

    // =========================================================================
    // Full 判断 (写时钟域): "偏保守"——更早地说"满",保证不溢出
    //   比较方: r_pointer_d2 (读指针的2-FF同步值) vs w_gray_pointer (当前写指针Gray)
    //   判满条件(Gray码域):
    //     - 高2bit不同: 最高位和次高位均不同 → 写指针绕了一整圈以上
    //     - 低bit相同: 写地址 == 读地址(在一个周期内同一位置)
    //     → 写比读多走整整一圈 → FIFO满
    //   为什么"偏保守"?
    //     r_pointer_d2 是 2+拍 前的旧读指针,实际读可能已读走了数据
    //     → 用旧读数判断,认为FIFO更满 → 更早说"满" → 写停止,不会溢出 ✓
    // =========================================================================
    assign full = (
                    (r_pointer_d2[POINTER_WIDTH - 1] != w_gray_pointer[POINTER_WIDTH - 1]) & // 最高bit不同
                    (r_pointer_d2[POINTER_WIDTH - 2] != w_gray_pointer[POINTER_WIDTH - 2]) & // 次高bit不同
                    (r_pointer_d2[POINTER_WIDTH - 3 : 0] == w_gray_pointer[POINTER_WIDTH - 3 : 0]) // 低bit相同
    );

    // =========================================================================
    // Empty 判断 (读时钟域): "偏乐观"——更晚地说"空"
    //   比较方: w_pointer_d2 (写指针的2-FF同步值) vs r_gray_pointer (当前读指针Gray)
    //   判空条件: 两者Gray码完全相等
    //     Gray码双射: Gray(X) == Gray(Y) ⟺ X == Y
    //     → 读侧看到的写指针 == 当前读指针 → 读追上了写 → FIFO空
    //   为什么"偏乐观"?
    //     w_pointer_d2 是 2+拍 前的旧写指针,实际写可能已经又写了数据
    //     → 用旧写值判断,认为FIFO更空 → 更晚说"空" → 读侧可能多读1~2笔 ← 读协议保证不连续读空FIFO
    // =========================================================================
    assign empty = w_pointer_d2 == r_gray_pointer;

endmodule
