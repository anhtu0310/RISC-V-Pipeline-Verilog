// True dual-port RAM, 32-bit words, synchronous read on both ports.
//   Port A: read-only (instruction fetch), with a read enable that holds the
//           output when low.
//   Port B: read/write with per-byte write strobes (data accesses).
// Written in the style FPGA tools infer as block RAM. INIT_FILE, if given,
// is loaded with $readmemh (one 32-bit word per line).
module dp_ram #(
    parameter integer ADDR_WIDTH = 12,          // words: 2**ADDR_WIDTH
    parameter         INIT_FILE  = ""
) (
    input  wire                  clk,

    input  wire                  a_en,
    input  wire [ADDR_WIDTH-1:0] a_addr,
    output reg  [31:0]           a_rdata,

    input  wire                  b_en,
    input  wire [3:0]            b_wstrb,       // 0000 = read
    input  wire [ADDR_WIDTH-1:0] b_addr,
    input  wire [31:0]           b_wdata,
    output reg  [31:0]           b_rdata
);

    localparam integer DEPTH = 1 << ADDR_WIDTH;

    reg [31:0] mem [0:DEPTH-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'd0;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk) begin
        if (a_en)
            a_rdata <= mem[a_addr];
    end

    always @(posedge clk) begin
        if (b_en) begin
            if (b_wstrb[0]) mem[b_addr][ 7: 0] <= b_wdata[ 7: 0];
            if (b_wstrb[1]) mem[b_addr][15: 8] <= b_wdata[15: 8];
            if (b_wstrb[2]) mem[b_addr][23:16] <= b_wdata[23:16];
            if (b_wstrb[3]) mem[b_addr][31:24] <= b_wdata[31:24];
            b_rdata <= mem[b_addr];
        end
    end

endmodule
