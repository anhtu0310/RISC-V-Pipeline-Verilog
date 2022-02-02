#ifndef _UTILS_
#define _UTILS_

class utils
{
private:
    ofstream outfile;

   

public:
    utils(string out_file_name)
    {
        outfile.open(out_file_name);
    }
     void gen_reg_file(uint32_t *reg_file)
    {
        // string line_out;

        for (int i = 0; i < 32; i++)
            outfile << hex << setw(8) << setfill('0') << reg_file[i];
        outfile << endl;
    }
};

#endif