#ifndef _EX_
#define _EX_
#include <iostream>
#include "OP_code.h"
class EX
{
public:
    // bool ALU_OP1_sel, ALU_OP2_sel;
    // uint8_t ALU_OP/;
    bool reg_en, reg_clear;
    uint32_t alu_out, op_1, op_2, br_op_1, br_op_2;

    bool branch_tk, PC_mux_sel, load_hazard;
    //pipline reg
    uint32_t reg_data_mux_out, reg_wr_en_out, mem_wr_en_out, mem_control_out, PC_next_out, ALU_result_out, rs_OP2_out, reg_wr_addr_out;

    //internal
    // uint32_t fwd_mux_1_data, fwd_mux_2_data;
    uint8_t fwd_mux_1, fwd_mux_2;
    void EX_comb(uint8_t ALU_OP, uint8_t BR_OP, uint32_t rs1, uint32_t rs2, uint32_t alu_out_stg5, uint32_t reg_data_in, uint32_t instr_mem_addr, uint32_t immediate, bool alu_mux_op_1, bool alu_mux_op_2, bool branch, bool jump)
    {
        if (!fwd_mux_1)
            br_op_1= rs1;
        else if (fwd_mux_1 == 1)
            br_op_1= alu_out_stg5;
        else
            br_op_1= reg_data_in;

        if (!fwd_mux_2)
            br_op_2= rs2;
        else if (fwd_mux_2 == 1)
            br_op_2= alu_out_stg5;
        else
            br_op_2= reg_data_in;

        if (!alu_mux_op_1)
            op_1 = br_op_1;
        else
            op_1 = instr_mem_addr;

        if (!alu_mux_op_2)
            op_2 = immediate;
        else
            op_2 = br_op_2;

        ALU(ALU_OP);
        branch_comp(BR_OP);
        PC_mux_sel = (branch_tk & branch) | jump;
        if(PC_mux_sel)
            cout<<"jumping  "<<int32_t(BR_OP)<<"\t"<<br_op_1<<"\t"<<br_op_2<<endl;
    }
    void EX_reg(/*bypass signals */ uint32_t reg_data_mux, uint32_t reg_wr_en, uint32_t mem_wr_en, uint32_t mem_control, uint32_t PC_next, uint32_t reg_wr_addr)
    {
        if (reg_en)
        {
            reg_data_mux_out = reg_data_mux;
            reg_wr_en_out = reg_wr_en;
            mem_wr_en_out = mem_wr_en;
            mem_control_out = mem_control;
            PC_next_out = PC_next;
            ALU_result_out = alu_out;
            rs_OP2_out = br_op_2;
            reg_wr_addr_out = reg_wr_addr;
        }
        if (reg_clear)
        {
            reg_data_mux_out = 0;
            reg_wr_en_out = 0;
            mem_wr_en_out = 0;
            mem_control_out = 0;
            PC_next_out = 0;
            ALU_result_out = 0;
            rs_OP2_out = 0;
            reg_wr_addr_out = 0;
        }
    }
    EX()
    {
        reg_en = 1;
        alu_out = 0;
        op_1 = 0;
        op_2 = 0;
        br_op_1 = 0;
        br_op_2 = 0;
        branch_tk = 0;
        PC_mux_sel = 0;
        //pipline reg
        reg_data_mux_out = 0;
        reg_wr_en_out = 0;
        mem_wr_en_out = 0;
        mem_control_out = 0;
        PC_next_out = 0;
        ALU_result_out = 0;
        rs_OP2_out = 0;
        reg_wr_addr_out = 0;
        load_hazard = 0;
        //internal
        // fwd_mux_1_data= 0;
        // fwd_mux_2_data= 0;
    }

    void forwarding_unit(uint32_t rs1_addr, uint32_t rs2_addr, bool reg_wr_en_stg5, bool reg_wr_en_stg4, uint32_t reg_wr_addr_stg4, uint32_t reg_wr_addr_stg5)
    {
        if (reg_wr_en_stg4 && (rs1_addr == reg_wr_addr_stg4))
        {
            cout << "forwarding stage 4 -> RS 1" << endl;
            fwd_mux_1 = 1;
        }
        else if (reg_wr_en_stg5 && (rs1_addr == reg_wr_addr_stg5))
        {
            cout << "forwarding stage 5 -> RS 1" << endl;
            fwd_mux_1 = 2;
        }
        else
            fwd_mux_1 = 0;

        if (reg_wr_en_stg4 && (rs2_addr == reg_wr_addr_stg4))
        {
            cout << "forwarding stage 4 -> RS 2" << endl;
            fwd_mux_2 = 1;
        }
        else if (reg_wr_en_stg5 && (rs2_addr == reg_wr_addr_stg5))
        {
            cout << "forwarding stage 5 -> RS 2" << endl;
            fwd_mux_2 = 2;
        }
        else
            fwd_mux_2 = 0;
    }

    void hazard_unit(uint8_t rs1_addr_stg_2, uint8_t rs2_addr_stg_2, uint8_t reg_wr_addr_stg_3, bool mem_rd)
    {
        load_hazard = mem_rd && ((reg_wr_addr_stg_3 == rs1_addr_stg_2) || (reg_wr_addr_stg_3 == rs2_addr_stg_2));
        if (load_hazard)
            cout << "Stall" << endl;
    }

private:
    void ALU(uint8_t ALU_OP)
    {
        switch (ALU_OP)
        {
        case OP_ADD:
        {
            alu_out = op_1 + op_2;
            break;
        }
        case OP_SUB:
        {
            alu_out = op_1 - op_2;
            break;
        }
        case OP_SLL:
        {
            alu_out = op_1 << (op_2 & 0x0000001F);
            break;
        }
        // case OP_SGT:
        // {
        //     alu_out = (int32_t(op_1) >= int32_t(op_2));
        //     break;
        // }
        case OP_LSR:
        {
            alu_out = op_1 >> (op_2 & 0x0000001F);
            break;
        }
        case OP_ASR:
        {
            alu_out = int32_t(op_1) >> (op_2 & 0x0000001F);
            break;
        }
        case OP_OR:
        {
            alu_out = op_1 | op_2;
            break;
        }
        case OP_AND:
        {
            alu_out = op_1 & op_2;
            break;
        }
        case OP_XOR:
        {
            alu_out = op_1 ^ op_2;
            break;
        }
        case OP_ULT:
        {
            alu_out = (op_1 < op_2);
            break;
        }
        case OP_SLT:
        {
            alu_out = (int32_t(op_1) < int32_t(op_2));
            break;
        }
        case OP_BP:
        {
            cout << "sometihng" << endl;
            alu_out = op_2;
            break;
        }
        default:
        {
            alu_out = 0;
            break;
        }
        }
    }
    void branch_comp(uint8_t BRC_OP)
    {
        branch_tk = 0;
        switch (BRC_OP)
        {
        case OP_EQL:
        {
            branch_tk = (br_op_1 == br_op_2);
            break;
        }
        case OP_NEQ:
        {
            branch_tk = (br_op_1 != br_op_2);
            break;
        }
        case OP_UGT:
        {
            branch_tk = (br_op_1 >= br_op_2);
            break;
        }
        case OP_ULT:
        {
            branch_tk = (br_op_1 < br_op_2);
            break;
        }
        case OP_SGT:
        {
            branch_tk = (int32_t(br_op_1) >= int32_t(br_op_2));
            break;
        }
        case OP_SLT:
        {
            branch_tk = (int32_t(br_op_1) < int32_t(br_op_2));
            break;
        }
        default:
            branch_tk = 0;
            break;
        }
    }
};
#endif