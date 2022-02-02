#include <iostream>
using namespace std;
#include <iomanip>
// #include"OP_code.h"
#include "IF.h"
#include "ID.h"
#include "EX.h"
#include "WB.h"
#include "utils.h"
void print_reg_file(uint32_t *reg_file)
{
    cout << "reg_mem :" << endl;
    for (int i = 0; i < 32; i++)
    {
        cout << setw(8) << reg_file[i] << "\t";
        if (((i + 1) % 6) == 0)
            cout << endl;
    }
    cout << endl;
}

void gen_reg_file(uint32_t *reg_file, char *file_name, int run_cycle)
{
    ofstream outfile;
    outfile.open(file_name);
    // string line_out;

    for (int i = 0; i < 32; i++)
        outfile << hex << setw(8) << setfill('0') << reg_file[i];
    outfile << endl;
}
int main()
{
    IF IF_module("demo");
    ID ID_module;
    EX EX_module;
    WB WB_module;
    utils tools("reg_dbg.mem");
    bool IF_EN = 1, ID_CLR = 0;
    uint32_t reg_wr_data = 0;
    for (int i = 0; i < 80; i++)
    {
        if (!WB_module.reg_data_mux_out)
            reg_wr_data = WB_module.mem_data_read_out;
        else if (WB_module.reg_data_mux_out == 1)
            reg_wr_data = WB_module.ALU_result_out;
        else
            reg_wr_data = WB_module.PC_next_out;

        WB_module.data_mem(EX_module.ALU_result_out, EX_module.rs_OP2_out, EX_module.mem_control_out, EX_module.mem_wr_en_out);
        // ID_module.reg_file_wr_at_clk(reg_wr_data, WB_module.reg_wr_addr_out, WB_module.reg_wr_en_out);

        EX_module.forwarding_unit(ID_module.rs1_addr_out,
                                  ID_module.rs2_addr_out,
                                  WB_module.reg_wr_en_out,
                                  EX_module.reg_wr_en_out,
                                  EX_module.reg_wr_addr_out,
                                  WB_module.reg_wr_addr_out);

        EX_module.EX_comb(ID_module.ALU_OP_out,
                          ID_module.funct3_out,
                          ID_module.rs1_data_out,
                          ID_module.rs2_data_out,
                          EX_module.ALU_result_out,
                          reg_wr_data,
                          ID_module.instr_addr_out,
                          ID_module.immediate_out,
                          ID_module.ALU_OP1_mux_out,
                          ID_module.ALU_OP2_mux_out,
                          ID_module.branch_out,
                          ID_module.jump_out);

        ID_module.ID_comb(IF_module.instr_out, reg_wr_data, WB_module.reg_wr_addr_out, WB_module.reg_wr_en_out);
        EX_module.hazard_unit(ID_module.rs1_addr, ID_module.rs2_addr, ID_module.reg_wr_addr_out, ID_module.mem_read_out);
        IF_EN = EX_module.load_hazard ^ 1;
        ID_CLR = EX_module.load_hazard | EX_module.PC_mux_sel;
        IF_module.IF_comb();

        cout << setfill('0') << setw(2) << i << "\t";
        cout << hex << setfill('0') << setw(8) << IF_module.instr << "\t"; // << IF_module.PC_next_out << "\t";
        cout << setw(2) << IF_EN << "\t";
        cout << EX_module.PC_mux_sel << "\t";
        cout << setw(8) << uint32_t(IF_module.PC) << "\t";
        cout << setw(8) << uint32_t(ID_module.instr_addr_out /*ID_module.ALU_OP_out*/) << "\t";
        cout << setw(8) << uint32_t(EX_module.op_2) << "\t";
        cout << setw(8) << uint32_t(EX_module.alu_out) << "\t";
        cout << endl;
        // print_reg_file(ID_module.reg_mem_data);
        tools.gen_reg_file(ID_module.reg_mem_data);
        //*****Clock trigger simmulate ************
        //**clocked componennts**
        ID_module.reg_file_wr_at_clk(reg_wr_data, WB_module.reg_wr_addr_out, WB_module.reg_wr_en_out);

        WB_module.WB_reg(EX_module.PC_next_out,
                         EX_module.ALU_result_out,
                         EX_module.reg_data_mux_out,
                         EX_module.reg_wr_addr_out,
                         EX_module.reg_wr_en_out);
        EX_module.EX_reg(ID_module.reg_data_mux_out,
                         ID_module.reg_wr_en_out,
                         ID_module.mem_wr_en_out,
                         ID_module.mem_control_out,
                         ID_module.PC_next_out,
                         ID_module.reg_wr_addr_out);
        ID_module.ID_reg(1, ID_CLR, IF_module.PC_next_out, IF_module.instr_addr_out);
        IF_module.IF_reg(IF_EN, EX_module.PC_mux_sel);
        IF_module.PC_counter_reg(EX_module.alu_out, EX_module.PC_mux_sel, IF_EN);
    }
    //************************************
    // for (int i = 0; i < 42; i++)
    // {
    //     IF_module.clk_trig();
    //     ID_module.instr = IF_module.instr_out;
    //     ID_module.PC_next = IF_module.PC_next_out;
    //     ID_module.instr_addr = IF_module.instr_addr_out;
    //     ID_module.ID_comb();
    //     ID_module.clk_trig();
    //     EX_module.EX_comp(ID_module.ALU_OP_out,ID_module.funct3_out,ID_module.rs1_data_out,ID_module.rs2_data_out,0,0,ID_module.instr_addr_out,ID_module.immediate_out,ID_module.ALU_OP1_mux_out,ID_module.ALU_OP2_mux_out,0,0,ID_module.branch_out,ID_module.jump_out);
    //     EX_module.EX_reg(ID_module.reg_data_mux_out,ID_module.reg_wr_en_out,ID_module.mem_wr_en_out,ID_module.mem_control_out,ID_module.PC_next_out,ID_module.reg_wr_addr_out);
    //     EX_module.reg_clear = 0;
    //     cout << hex << setfill('0') << setw(8) << IF_module.instr_out << "\t" << IF_module.PC_next_out <<"\t";
    //     cout << hex << setfill('0') << setw(8) << ID_module.immediate <<"\t";
    //     cout << hex << uint32_t(ID_module.opcode) << "\t";
    //     cout << setw(8) << uint32_t(ID_module.rs2_addr_out) << "\t";
    //     cout << setw(2) << uint32_t(ID_module.ALU_OP2_mux_out) << "\t";
    //     cout << setw(8) << EX_module.fwd_mux_2_data <<"\t";
    //     cout << setw(8) << EX_module.op_2<<"\t";
    //     cout << setw(8) << EX_module.alu_out

    //     <<endl;

    // }

    // uint32_t a = -24;
    // uint32_t b = 4;
    // uint32_t b = int8_t(a) >> 2;
    // cout << (a < b) << endl;
    // cout<<OP_BP<<endl;
    // cout<<hex<<stol("ffffffff",0,16);

    // for(int i = 0; i<32 ; i++)
    //     cout<<i<<"\t"<<ID_module.reg_mem_data[i]<<endl;
}