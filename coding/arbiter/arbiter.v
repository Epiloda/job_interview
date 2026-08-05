module arbiter #(
    parameter REQ_WIDTH = 8
)(
    input [REQ_WIDTH-1 : 0] req,

    output [REQ_WIDTH-1 : 0] grant
);

    assign grant = req & ~(req - 1'b1);

endmodule
