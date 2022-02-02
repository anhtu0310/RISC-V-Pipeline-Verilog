module inst_decoder (
  input   wire [31:0]  instr,
  output  wire [4:0]   rs1,
  output  wire [4:0]   rs2,
  output  wire [4:0]   rd,
  output  wire [6:0]   opcode,
  output  wire [2:0]   funct3,
  output  wire [6:0]   funct7,
  // output  reg  [2:0]   instr_type,
  // output  wire         iillegal_instruction,
  output  reg  [31:0]  immediate 
);

  assign rd = instr[11:7];
  assign opcode = instr[6:0];
  assign funct3 = instr[14:12];
  assign funct7 = instr[31:25];
  assign rs1 = instr[19:15];
  assign rs2 = instr[24:20];
  assign rd = instr[11:7];

  always @(instr) begin
    case (opcode)
      7'b011_0011: 
      begin
          immediate = 32'hdeadbeef;
          // instr_type = R_TYPE;
      end 
      
      7'b110_0111,
      7'b000_0011,
      7'b001_0011:
      begin
          immediate = {{20{instr[31]}},instr[31:20]}; 
          // instr_type = I_TYPE;

      end
      7'b011_0111,
      7'b001_0111:
      begin 
        immediate = {instr[31:12],12'h0}; 
        // instr_type = U_TYPE;
      end
      7'b110_1111:
      begin
        immediate = {{11{instr[31]}},instr[31], instr[19:12],instr[20], instr[30:21],1'b0};
        // instr_type = J_TYPE;
      end	
      7'b110_0011:
      begin
            immediate = {{19{instr[31]}},instr[31],instr[7],instr[30:25],instr[11:8],1'b0};
            // instr_type = B_TYPE;
      end	
      7'b010_0011:
      begin 
            immediate = {{20{instr[31]}},instr[31:25],instr[11:7]};
            // instr_type = S_TYPE;

      end
      default:    immediate = 32'hdeadbeef;  //    instr_type = ILLEGAL;
    endcase
  end

endmodule

