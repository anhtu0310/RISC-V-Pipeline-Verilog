#ifndef _OP_CODE_
#define _OP_CODE_

#define OP_ADD 0
#define OP_SUB 1
#define OP_SLL 2
#define OP_SLT 4
#define OP_ULT 6
#define OP_XOR 8
#define OP_LSR 10
#define OP_ASR 11
#define OP_OR  12
#define OP_AND 14
#define OP_BP  7



#define OP_EQL 0
#define OP_NEQ 1
#define OP_UGT 7 //Unsigned Greater Than or Equal
#define OP_SGT 5 //Signed Greater Than or Equal
#define OP_SLT 4
// #define OP_ULT 6

#define MEM_BYTE 0
#define MEM_HALF 1
#define MEM_WORD 2
#define MEM_BYTE_U 4
#define MEM_HALF_U 5
#endif