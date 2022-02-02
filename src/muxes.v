
module MUX_2_1 (
    input  wire [31:0] I1,
    input  wire [31:0] I2,
    input  wire        S,
    output wire [31:0] out
);

assign out = (S == 1'b0) ? I1 : I2;
endmodule

module MUX_3_1 (
    input  wire [31:0] I1,
    input  wire [31:0] I2,
    input  wire [31:0] I3,
    input  wire [1:0]  S,
    output wire [31:0] out
);

assign out = (S == 2'b00) ? I1 :
             (S == 2'b01) ? I2 : I3;
endmodule