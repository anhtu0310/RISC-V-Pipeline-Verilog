#ifndef _ID_
#define _ID_
#include <iostream>
#include "OP_code.h"

#define LUI 55
#define AUIPC 23
#define JAL 111
#define JALR 103
#define B_TYPE 99
#define L_TYPE 3
#define S_TYPE 35
#define I_TYPE 19
#define R_TYPE 51

class ID
{
public:
    // uint32_t PC_next, instr_addr, instr;
    //reg_file_input
    bool  reg_wr_en;
    // uint32_t reg_wr_data, reg_wr_addr;
    uint8_t rs1_addr, rs2_addr;
    //Ouputs
    bool reg_wr_en_out, mem_wr_en_out, jump_out, branch_out,
        mem_read_out, ALU_OP1_mux_out, ALU_OP2_mux_out;

    uint8_t ALU_OP_out, reg_data_mux_out, mem_control_out, rs1_addr_out, rs2_addr_out, opcode_out, funct3_out;
    uint32_t PC_next_out, instr_addr_out, rs1_data_out, rs2_data_out, immediate_out, reg_wr_addr_out;

    //internal data_path
    uint32_t immediate, rs1_data, rs2_data;
    bool mem_wr_en, jump, branch, mem_read, ALU_OP1_mux, ALU_OP2_mux;
    uint8_t rd, opcode, funct3, funct7, ALU_OP, reg_data_mux, mem_control;
    uint32_t reg_mem_data[32];

    ID()
    {
        branch = 0;
        mem_read = 0;
        ALU_OP1_mux = 0;
        ALU_OP2_mux = 0;
        ALU_OP = 0;
        reg_data_mux = 0;
        reg_wr_en = 0;
        mem_wr_en = 0;
        mem_control = 0;
        // PC_next  = 0;
        // instr_addr  = 0;
        rs1_addr = 0;
        rs2_addr = 0;
        immediate = 0;
        // reg_wr_addr  = 0;
        rs1_data = 0;
        rs2_data = 0;
        opcode = 0;
        funct3 = 0;
        jump = 0;
        reg_wr_en = 0;
        // reg_wr_data = 0;
        // reg_wr_addr = 0;
        rs1_addr = 0;
        rs2_addr = 0;
        ALU_OP_out = 0;
        branch_out = 0;
        mem_read_out = 0;
        ALU_OP1_mux_out = 0;
        ALU_OP2_mux_out = 0;
        ALU_OP_out = 0;
        reg_data_mux_out = 0;
        reg_wr_en_out = 0;
        mem_wr_en_out = 0;
        mem_control_out = 0;
        PC_next_out = 0;
        instr_addr_out = 0;
        rs1_data_out = 0;
        rs2_data_out = 0;
        immediate_out = 0;
        reg_wr_addr_out = 0;
        rs1_addr_out = 0;
        rs2_addr_out = 0;
        opcode_out = 0;
        funct3_out;
        jump_out = 0;
        reg_wr_en = 0;
        // reg_wr_data = 0;
        // reg_wr_addr = 0;
        rs1_addr = 0;
        rs2_addr = 0;
        // reg_en = 1;
        // reg_clear = 0;
        for (int i = 0; i < 32; i++)
            reg_mem_data[i] = 0;
    }
    void ID_comb(uint32_t instr, uint32_t reg_wr_data, uint32_t reg_wr_addr, bool reg_wr_en_stg5)
    {
        instr_decode(instr);
        controller();
        reg_file_ouput(reg_wr_data, reg_wr_addr, reg_wr_en_stg5); //reg_wr_data,reg_wr_addr,reg_wr_en_stg5);
    }
    void ID_reg(bool reg_en,bool reg_clear,uint32_t PC_next, uint32_t instr_addr)
    {
        if (reg_en)
        {
            // ALU_OP_out = ALU_OP;
            branch_out = branch;
            mem_read_out = mem_read;
            ALU_OP1_mux_out = ALU_OP1_mux;
            ALU_OP2_mux_out = ALU_OP2_mux;
            ALU_OP_out = ALU_OP;
            reg_data_mux_out = reg_data_mux;
            reg_wr_en_out = reg_wr_en;
            mem_wr_en_out = mem_wr_en;
            mem_control_out = mem_control;
            PC_next_out = PC_next;
            instr_addr_out = instr_addr;
            rs1_data_out = rs1_data;
            rs2_data_out = rs2_data;
            immediate_out = immediate;
            reg_wr_addr_out = rd;
            rs1_addr_out = rs1_addr;
            rs2_addr_out = rs2_addr;
            opcode_out = opcode;
            funct3_out = funct3;
            jump_out = jump;
            // reg_wr_en = reg_wr_en_out;
        }
        if (reg_clear)
        {
            ALU_OP_out = 0;
            branch_out = 0;
            mem_read_out = 0;
            ALU_OP1_mux_out = 0;
            ALU_OP2_mux_out = 0;
            ALU_OP_out = 0;
            reg_data_mux_out = 0;
            reg_wr_en_out = 0;
            mem_wr_en_out = 0;
            mem_control_out = 0;
            PC_next_out = 0;
            instr_addr_out = 0;
            rs1_data_out = 0;
            rs2_data_out = 0;
            immediate_out = 0;
            reg_wr_addr_out = 0;
            rs1_addr_out = 0;
            rs2_addr_out = 0;
            opcode_out = 0;
            funct3_out;
            jump_out = 0;
            // reg_wr_en = 0;
            // reg_wr_data = 0;
            // reg_wr_addr = 0;
            // rs1_addr = 0;
            // rs2_addr = 0;
        }
    }

    void reg_file_wr_at_clk(uint32_t reg_wr_data, uint32_t reg_wr_addr, bool reg_wr_en_stg5)
    {
        if (reg_wr_en_stg5)
        {
            reg_mem_data[reg_wr_addr] = reg_wr_data;
            // cout<<hex<<reg_wr_addr<<" "<<reg_mem_data[reg_wr_addr]<<endl;
        }
    }
    // public:
private:
    void instr_decode(uint32_t instr)
    {
        rd = (instr & 0b111110000000) >> 7;
        opcode = instr & 0b1111111;
        funct3 = (instr & 0b111000000000000) >> 12;
        rs1_addr = (instr & 0b11111000000000000000) >> 15;
        rs2_addr = (instr & 0b1111100000000000000000000) >> 20;
        funct7 = (instr & 0b11111110000000000000000000000000) >> 25;

        switch (opcode)
        {
        // case R_TYPE:
        // {
        //     immediate = 0;
        //     break;
        // }
        case JALR:
        case L_TYPE:
        case I_TYPE:
        {
            immediate = instr;
            immediate = int32_t(immediate) >> 20;
            break;
        }
        case LUI:
        case AUIPC:
        {
            immediate = instr & 0xFFFFF000; //0b000000000000;
            break;
        }
        case JAL:
        {
            uint32_t temp1 = (int32_t(instr) >> 11) & 0xFFF00000;
            uint32_t temp2 = (instr & 0x00100000) >> 9;
            uint32_t temp3 = (instr & 0x000FF000);
            uint32_t temp4 = (instr & 0x7FE00000) >> 20;
            immediate = temp1 | temp2 | temp3 | temp4;
            break;
        }
        case B_TYPE:
        {
            uint32_t temp1 = (int32_t(instr) >> 19) & 0xFFFFF000;
            uint32_t temp2 = (instr & 0x00000080) << 4;
            uint32_t temp3 = (instr & 0x7E000000) >> 20;
            uint32_t temp4 = (instr & 0x00000F00) >> 7;
            // cout<<temp1<<"\t"<<temp2<<"\t"<<temp3<<"\t"<<temp4<<endl;

            immediate = temp1 | temp2 | temp3 | temp4;
            break;
        }
        case S_TYPE:
        {
            uint32_t temp1 = (int32_t(instr) >> 20) & 0xFFFFFFE0;
            ;
            uint32_t temp2 = (instr & 0x00000F80) >> 7;
            immediate = temp1 | temp2;
            // cout<<hex <<temp2<<endl;
            break;
        }

        default:
        {
            immediate = 0;
            break;
        }
        }
    }
    void controller()
    {
        jump = 0;
        branch = 0;
        mem_read = 0;
        // PC_mux       = 0;
        ALU_OP1_mux = 0;
        ALU_OP2_mux = 0;
        reg_wr_en = 0;
        mem_wr_en = 0;
        reg_data_mux = 0;
        ALU_OP = 0xFF;
        mem_control = 2;
        switch (opcode)
        {
        case R_TYPE:
        {
            ALU_OP2_mux = 1;
            reg_wr_en = 1;
            reg_data_mux = 1;
            ALU_OP = (funct3 << 1) | (funct7 >> 5);
            break;
        }
        case I_TYPE:
        {
            reg_data_mux = 1;
            reg_wr_en = 1;
            ALU_OP = (funct3 == 5) ? (funct3 << 1) | (funct7 >> 5) : (funct3 << 1);
            break;
        }
        case S_TYPE:
        {
            mem_wr_en = 1;
            reg_data_mux = 1;
            mem_control = funct3;
            ALU_OP = OP_ADD;
            break;
        }
        case L_TYPE:
        {
            mem_control = funct3;
            reg_wr_en = 1;
            ALU_OP = OP_ADD;
            mem_read = 1;
            break;
        }
        case B_TYPE:
        {
            branch = 1;
            ALU_OP1_mux = 1;
            ALU_OP = OP_ADD;
            break;
        }
        case JALR:
        {
            reg_wr_en = 1;
            reg_data_mux = 3;
            ALU_OP = OP_ADD;
            jump = 1;
            break;
        }
        case JAL:
        {
            jump = 1;
            reg_wr_en = 1;
            // PC_mux = 1;
            ALU_OP1_mux = 1;
            reg_data_mux = 3;
            ALU_OP = OP_ADD;
            break;
        }
        case LUI:
        {
            reg_wr_en = 1;
            reg_data_mux = 1;
            ALU_OP = OP_BP;
            break;
        }
        case AUIPC:
        {
            reg_wr_en = 1;
            ALU_OP1_mux = 1;
            reg_data_mux = 1;
            ALU_OP = OP_ADD;
            break;
        }
        default:
            break;
        }
    }
    void reg_file_ouput(uint32_t reg_wr_data, uint32_t reg_wr_addr, bool reg_wr_en)
    {
        // if (reg_wr_en_stg5){
        //     reg_mem_data[reg_wr_addr] = reg_wr_data;
        //     // cout<<hex<<reg_wr_addr<<" "<<reg_mem_data[reg_wr_addr]<<endl;
        // }
        //  rs1_addr ? ((rs1_addr == rd_addr) && wr_en) ? data_in :regfile[rs1_addr] : 32'h0;
        rs1_data = rs1_addr ? ((rs1_addr == reg_wr_addr) && reg_wr_en) ? reg_wr_data : reg_mem_data[rs1_addr] : 0;
        rs2_data = rs2_addr ? ((rs2_addr == reg_wr_addr) && reg_wr_en) ? reg_wr_data : reg_mem_data[rs2_addr] : 0;
    }
};
#endif