#ifndef _WB_
#define _WB_

#include "OP_code.h"
class WB
{
public:
    bool reg_en, reg_clear;
    uint32_t mem_data_out;
    uint8_t mem_data[2048]= {0};
    uint8_t reg_data_mux_out, reg_wr_addr_out;
    bool reg_wr_en_out;
    uint32_t PC_next_out, ALU_result_out, mem_data_read_out;

    WB()
    {
        reg_en = 1;
        reg_clear = 0;

        PC_next_out = 0;
        ALU_result_out = 0;
        reg_data_mux_out = 0;
        reg_wr_addr_out = 0;
        reg_wr_en_out = 0;
        mem_data_read_out = 0;
        mem_data_out = 0;
    }
    void WB_reg(uint32_t PC_next, uint32_t ALU_result, uint8_t reg_data_mux, uint8_t reg_wr_addr, bool reg_wr_en)
    {
        if (reg_en)
        {
            PC_next_out = PC_next;
            ALU_result_out = ALU_result;
            reg_data_mux_out = reg_data_mux;
            reg_wr_addr_out = reg_wr_addr;
            reg_wr_en_out = reg_wr_en;
            mem_data_read_out = mem_data_out;
        }
        if (reg_clear)
        {
            PC_next_out = 0;
            ALU_result_out = 0;
            reg_data_mux_out = 0;
            reg_wr_addr_out = 0;
            reg_wr_en_out = 0;
            mem_data_read_out = 0;
        }
    }

// private:
    void data_mem(uint32_t addr, uint32_t data_in, uint8_t mem_control, bool wr_en)
    {
        if (wr_en)
            switch (mem_control)
            {
            case MEM_WORD:
            {
                for (int i = 0; i < 4; i++)
                    mem_data[addr + i] = (data_in >> (i * 8)) & 0x000000FF;
                break;
            }
            case MEM_BYTE:
            {
                mem_data[addr] = data_in;
                break;
            }
            case MEM_HALF:
            {
                mem_data[addr] = data_in & 0x000000FF;
                mem_data[addr + 1] = (data_in & 0x0000FF00) >> 8;
                break;
            }
            default:
                break;
            }

        switch (mem_control)
        {
        case MEM_WORD:
        {
            mem_data_out = 0;
            if(addr <=2047 )
            // cout<<addr<<endl;
            // else
            for (int i = 3; i >= 0; i--)
            {
                mem_data_out = mem_data[addr + i] | mem_data_out;
                mem_data_out = i ? mem_data_out << 8 :mem_data_out;
            }
            break;
        }
        case MEM_BYTE:
        {
            mem_data_out = int8_t(mem_data[addr]);
            break;
        }
        case MEM_BYTE_U:
        {
            mem_data_out = mem_data[addr];
            break;
        }
        case MEM_HALF:
        {
            mem_data_out = (int8_t(mem_data[addr + 1]) << 8);
            mem_data_out = mem_data_out | mem_data[addr];
            break;
        }
        case MEM_HALF_U:
        {
            mem_data_out = (mem_data[addr + 1] << 8);
            mem_data_out = mem_data_out | mem_data[addr];
            break;
        }
        default:
            break;
        }
    }
};
#endif