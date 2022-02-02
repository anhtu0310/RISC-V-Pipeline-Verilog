#ifndef _IF_
#define _IF_

#include <fstream>
#include <string>
#include <iostream>

class IF
{
public:
    //inputs
    // uint32_t PC_in;
    // bool PC_mux_sel;
    // bool PC_en;
    // bool reg_en, reg_clear;
    //outputs
    uint32_t PC_next_out, instr_addr_out, instr_out;
    uint32_t instr;

    uint32_t PC_next, PC;
    void IF_comb(/*uint32_t PC_in, bool PC_mux_sel, bool PC_en*/)
    {
        // PC_counter(PC_in, PC_mux_sel, PC_en);
        PC_counter_comb();
        instr_mem_unit();
        // IF_reg();
    }
    void IF_reg(bool reg_en, bool reg_clear)
    {
        if (reg_en)
        {
            PC_next_out = PC_next;
            instr_addr_out = PC;
            instr_out = instr;
        }
        if (reg_clear)
        {
            PC_next_out = 0;
            instr_addr_out = 0;
            instr_out = 0;
        }
    }
    IF(string program)
    {
        ifstream inProgram;
        inProgram.open(program);
        string line;
        uint32_t hex_val;
        int i = 0;
        while (getline(inProgram, line))
        {
            hex_val = stol(line, 0, 16);
            // cout<<hex<<hex_val<<endl;
            instr_mem[i] = hex_val;
            i++;
        }

        // PC_in = 0;
        // PC_mux_sel = 0;
        // PC_en = 1;
        // reg_en = 1;
        // reg_clear = 0;
        //outputs
        PC_next_out = 0;
        instr_addr_out = 0;
        instr_out = 0;
        PC_next = 0;
        PC = 0;
        instr = 0;
    }
    void PC_counter_reg(uint32_t PC_in, bool PC_mux_sel, bool PC_en)
    {
        if (PC_en)
        {
            if (PC_mux_sel)
                PC = PC_in;
            else
                PC = PC_next;
        }
    }

private:
    uint32_t instr_mem[50];
    void PC_counter_comb()
    {
        PC_next = PC + 4;
    }
    void instr_mem_unit()
    {
        instr = instr_mem[PC / 4];
    }
};

#endif