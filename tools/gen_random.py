#!/usr/bin/env python3
"""Generate a random RV32I program for lockstep testing of the pipeline.

The program is emitted directly as a $readmemh image (no toolchain needed).
The testbench runs it on the RTL and on a reference ISA model in parallel and
compares every retired instruction, so the program itself does not need to
know the expected results; it only has to be legal and terminate.

Rules that keep every generated program well-behaved:
  * x31 holds the base of a scratch data area and is never written.
  * Control flow only goes forward (branches, JAL, AUIPC+JALR pairs), so the
    program always reaches the epilogue, which stores 1 to TOHOST.
  * Branch/jump targets are block boundaries, so a jump never lands between
    the AUIPC and JALR of a pair.
  * Source registers are biased towards recently written ones to create
    dense RAW/load-use hazards.
"""
import argparse
import random

TOHOST = 0xF0000000
DATA_BASE = 0x2000      # scratch area inside RAM, above the code
DATA_SIZE = 0x400       # bytes the loads/stores may touch
BASE_REG = 31
MAX_CODE_BYTES = DATA_BASE


# ---------------------------------------------------------------------------
# Encoders
# ---------------------------------------------------------------------------
def _chk(val, bits, signed=True):
    lo, hi = (-(1 << (bits - 1)), (1 << (bits - 1)) - 1) if signed else (0, (1 << bits) - 1)
    assert lo <= val <= hi, (val, bits)
    return val & ((1 << bits) - 1)


def r_type(f7, rs2, rs1, f3, rd, op):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def i_type(imm, rs1, f3, rd, op):
    return (_chk(imm, 12) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def s_type(imm, rs2, rs1, f3, op):
    imm = _chk(imm, 12)
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1f) << 7) | op


def b_type(imm, rs2, rs1, f3):
    imm = _chk(imm, 13)
    assert imm % 2 == 0
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3f) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (f3 << 12) | (((imm >> 1) & 0xf) << 8) | (((imm >> 11) & 1) << 7) | 0x63


def u_type(imm20, rd, op):
    return (_chk(imm20, 20, signed=False) << 12) | (rd << 7) | op


def j_type(imm, rd):
    imm = _chk(imm, 21)
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3ff) << 21) | (((imm >> 11) & 1) << 20) | \
           (((imm >> 12) & 0xff) << 12) | (rd << 7) | 0x6f


OP, OP_IMM, LOAD, STORE, LUI, AUIPC, JAL, JALR, FENCE = 0x33, 0x13, 0x03, 0x23, 0x37, 0x17, 0x6f, 0x67, 0x0f

R_OPS = [  # (funct7, funct3)
    (0x00, 0), (0x20, 0), (0x00, 1), (0x00, 2), (0x00, 3),
    (0x00, 4), (0x00, 5), (0x20, 5), (0x00, 6), (0x00, 7),
]
I_OPS = [0, 2, 3, 4, 6, 7]          # addi slti sltiu xori ori andi
SHIFT_I = [(0x00, 1), (0x00, 5), (0x20, 5)]
LOADS = [(0, 1), (1, 2), (2, 4), (4, 1), (5, 2)]   # (funct3, size)
STORES = [(0, 1), (1, 2), (2, 4)]
BRANCHES = [0, 1, 4, 5, 6, 7]


class Gen:
    def __init__(self, rng):
        self.rng = rng
        self.recent = []

    def rd(self):
        r = self.rng.random()
        if r < 0.05:
            reg = 0                     # writes to x0 must be discarded
        else:
            reg = self.rng.randint(1, 30)
        if reg:
            self.recent = ([reg] + [x for x in self.recent if x != reg])[:4]
        return reg

    def rs(self):
        r = self.rng.random()
        if self.recent and r < 0.6:
            return self.rng.choice(self.recent)
        if r < 0.65:
            return 0
        return self.rng.randint(1, 30)

    def imm12(self):
        return self.rng.choice([0, 1, -1, 2047, -2048, self.rng.randint(-2048, 2047)])

    def mem_off(self, size):
        return self.rng.randrange(0, DATA_SIZE, size)

    # Each block is a list of either ints (encoded words) or callables that
    # take (own_pc, block_addresses) and return the encoded word.
    def block(self, idx, nblocks):
        rng = self.rng
        kind = rng.choices(
            ["alu_r", "alu_i", "shift_i", "lui", "auipc", "load", "store",
             "branch", "jal", "jalr", "fence"],
            weights=[20, 14, 6, 4, 2, 14, 10, 12, 4, 3, 1])[0]
        if kind == "alu_r":
            f7, f3 = rng.choice(R_OPS)
            return [r_type(f7, self.rs(), self.rs(), f3, self.rd(), OP)]
        if kind == "alu_i":
            return [i_type(self.imm12(), self.rs(), rng.choice(I_OPS), self.rd(), OP_IMM)]
        if kind == "shift_i":
            f7, f3 = rng.choice(SHIFT_I)
            return [r_type(f7, rng.randint(0, 31), self.rs(), f3, self.rd(), OP_IMM)]
        if kind == "lui":
            return [u_type(rng.getrandbits(20), self.rd(), LUI)]
        if kind == "auipc":
            return [u_type(rng.getrandbits(20), self.rd(), AUIPC)]
        if kind == "load":
            f3, size = rng.choice(LOADS)
            return [i_type(self.mem_off(size), BASE_REG, f3, self.rd(), LOAD)]
        if kind == "store":
            f3, size = rng.choice(STORES)
            return [s_type(self.mem_off(size), self.rs(), BASE_REG, f3, STORE)]
        if kind == "fence":
            return [i_type(0x0ff, 0, 0, 0, FENCE)]

        # Forward control flow to a later block (or the epilogue).
        target = rng.randint(idx + 1, min(idx + 6, nblocks))
        if kind == "branch":
            f3, a, b = rng.choice(BRANCHES), self.rs(), self.rs()
            return [lambda pc, addr, f3=f3, a=a, b=b, t=target: b_type(addr[t] - pc, b, a, f3)]
        if kind == "jal":
            rd = self.rd()
            return [lambda pc, addr, rd=rd, t=target: j_type(addr[t] - pc, rd)]
        # auipc rX, 0 ; jalr rd, off(rX)   (sometimes with an odd offset to
        # exercise the bit-0 clear)
        base = rng.randint(1, 30)
        rd = self.rd()
        odd = rng.randint(0, 1)
        return [u_type(0, base, AUIPC),
                lambda pc, addr, base=base, rd=rd, t=target, odd=odd:
                    i_type(addr[t] - (pc - 4) + odd, base, 0, rd, JALR)]


def li(rd, value):
    """lui+addi pair loading an arbitrary 32-bit constant."""
    value &= 0xffffffff
    lo = value & 0xfff
    if lo >= 0x800:
        lo -= 0x1000
    hi = ((value - lo) >> 12) & 0xfffff
    return [u_type(hi, rd, LUI), i_type(lo, rd, 0, rd, OP_IMM)]


def generate(seed, count):
    rng = random.Random(seed)
    g = Gen(rng)

    prologue = li(BASE_REG, DATA_BASE)
    for r in range(1, 31):
        prologue += li(r, rng.choice([0, 1, 0xffffffff, 0x80000000, 0x7fffffff, rng.getrandbits(32)]))
    # Seed the scratch area so loads return interesting data.
    for off in range(0, 64, 4):
        prologue.append(s_type(off, rng.randint(1, 30), BASE_REG, 2, STORE))

    blocks = [g.block(i, count) for i in range(count)]
    epilogue = li(1, TOHOST) + li(2, 1) + [s_type(0, 2, 1, 2, STORE), j_type(0, 0)]

    # Lay out block addresses; index `count` is the epilogue.
    addr = []
    pc = 4 * len(prologue)
    for b in blocks:
        addr.append(pc)
        pc += 4 * len(b)
    addr.append(pc)

    words = list(prologue)
    for b, base in zip(blocks, addr):
        for k, w in enumerate(b):
            words.append(w(base + 4 * k, addr) if callable(w) else w)
    words += epilogue
    assert 4 * len(words) <= MAX_CODE_BYTES, "program too large for the code area"
    return words


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--count", type=int, default=600, help="number of random blocks")
    ap.add_argument("-o", "--output", required=True)
    args = ap.parse_args()
    with open(args.output, "w") as f:
        for w in generate(args.seed, args.count):
            f.write("%08x\n" % w)


if __name__ == "__main__":
    main()
