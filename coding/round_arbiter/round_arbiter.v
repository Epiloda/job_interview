module round_arbiter #(
    parameter REQ_WIDTH = 8
)(
    input clk,
    input rst_n,
    input [REQ_WIDTH-1 : 0] req,

    output [REQ_WIDTH-1 : 0] grant
);
    reg [REQ_WIDTH-1 : 0] priority_mask;
    wire [REQ_WIDTH-1 : 0] masked_req;
    wire [REQ_WIDTH-1 : 0] masked_grant;
    wire [REQ_WIDTH-1 : 0] wrapped_grant;

    // wrapper和masked的grant算法和固定优先级的仲裁器一样
    assign wrapped_grant = req & ~(req - 1'b1);
    assign masked_req = req & priority_mask;
    assign masked_grant = masked_req & ~(masked_req - 1'b1);

    assign grant = (!rst_n) ? 'b0 :
                    (|masked_grant) ? masked_grant : wrapped_grant;

    // 根据上一轮grant的结果，mask掉低位的req
    // 比如：响应了req5，则下一轮优先级是：6>7>0>1>2>3>4>5
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            priority_mask <= 'b0;
        end

        else if (|grant) begin
            priority_mask <= ~((grant << 1) - 1'b1);
        end
    end
endmodule
