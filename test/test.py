# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: MIT

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
import random
from functools import reduce
import operator

class Memory:
  def __init__(self):
    self.contents = list(random.randbytes(65536))
    self.ptr = 0
  def read(self, addr):
    return self.contents[addr]
  def write(self, addr, value):
    assert value >= 0 and value <= 255
    self.contents[addr] = value
  def append(self, values):
    for i in values:
      self.write(self.ptr, i)
      self.ptr += 1

class BusModel:
  def __init__(self, memory, dut):
    self.memory = memory
    self.dut = dut
  async def handshake_begin(self):
    while (self.dut.uo_out.value & 1) == 0:
      await ClockCycles(self.dut.clk, 1)
  async def handshake_end(self):
    self.dut.ui_in.value = 1
    while (self.dut.uo_out.value & 1) != 0:
      await ClockCycles(self.dut.clk, 1)
    self.dut.ui_in.value = 0
  async def read(self, addr):
    value = self.memory.read(addr)
    await self.handshake_begin()
    assert self.dut.uio_out.value == (addr & 0xff)
    assert self.dut.uio_oe.value == 0xff
    assert (self.dut.uo_out.value & 2) == 0
    await self.handshake_end()
    await self.handshake_begin()
    assert self.dut.uio_out.value == (addr >> 8)
    assert self.dut.uio_oe.value == 0xff
    assert (self.dut.uo_out.value & 2) == 0
    await self.handshake_end()
    await self.handshake_begin()
    assert self.dut.uio_oe.value == 0x00
    self.dut.uio_in.value = value
    await ClockCycles(self.dut.clk, 1)
    await self.handshake_end()
    return value
  async def write(self, addr, value):
    self.memory.write(addr, value)
    await self.handshake_begin()
    assert self.dut.uio_out.value == (addr & 0xff)
    assert self.dut.uio_oe.value == 0xff
    assert (self.dut.uo_out.value & 2) == 2
    await self.handshake_end()
    await self.handshake_begin()
    assert self.dut.uio_out.value == (addr >> 8)
    assert self.dut.uio_oe.value == 0xff
    assert (self.dut.uo_out.value & 2) == 2
    await self.handshake_end()
    await self.handshake_begin()
    assert self.dut.uio_oe.value == 0xff
    assert self.dut.uio_out.value == value
    await self.handshake_end()
  async def halt(self):
    await ClockCycles(self.dut.clk, 20)
    assert (self.dut.uo_out.value & 8) != 0

cpu_opcodes = {}
def instruction(opcode, fields={}, exclude=[]):
  def bytes_with_wildcards(pattern, wildcard):
    assert 0 <= pattern <= 255
    assert 0 <= wildcard <= 255
    n = pattern
    mask = wildcard ^ 0xff
    while n < 0x100:
      yield n
      n = ((n | mask) + 1) & ~mask | pattern
  def extract_wildcard(fields):
    return reduce(operator.or_, [(0xff << b) & ~((-1) << (a+1)) for (a,b) in fields.values()], 0)
  def extract_fields(op, fields):
    return {field: (op & ~((-1) << (a+1))) >> b for (field, (a,b)) in fields.items()}
  def decorator(func):
    wildcard = extract_wildcard(fields)
    for op in bytes_with_wildcards(opcode, wildcard):
      if not (op in exclude):
        field_values = extract_fields(op, fields)
        assert not (op in cpu_opcodes)
        cpu_opcodes[op] = (lambda values: lambda self: func(self, **values))(field_values)
  return decorator

FLAGC = 0x01
FLAGP = 0x04
FLAGH = 0x10
FLAGZ = 0x40
FLAGS = 0x80

def parity(data):
  while data > 1:
    data = data >> 1 ^ (data & 1)
  return data

def addition(a, b, carry):
  assert 0 <= a <= 255
  assert 0 <= b <= 255
  assert carry is True or carry is False
  carry_out = (a + b + int(carry)) > 255
  half_carry_out = ((a & 15) + (b & 15) + int(carry)) > 15
  result = (a + b + int(carry)) & 255
  return (result, carry_out, half_carry_out)

def subtraction(a, b, borrow):
  assert 0 <= a <= 255
  assert 0 <= b <= 255
  assert borrow is True or borrow is False
  carry_out = (a - b - int(borrow)) < 0
  half_carry_out = ((a & 15) - (b & 15) - int(borrow)) < 0
  result = (a - b - int(borrow)) & 255
  return (result, carry_out, half_carry_out)

def alu_op(op, a, b, carry):
  if op == 0:
    return addition(a, b, False)
  elif op == 1:
    return addition(a, b, carry)
  elif op == 2 or op == 7:
    return subtraction(a, b, False)
  elif op == 3:
    return subtraction(a, b, carry)
  elif op == 4:
    return (a & b, False, ((a | b) & 8) != 0)
  elif op == 5:
    return (a ^ b, False, False)
  elif op == 6:
    return (a | b, False, False)

class CPU:
  def __init__(self, bus_model):
    self.rA = 0
    self.rB = 0
    self.rC = 0
    self.rD = 0
    self.rE = 0
    self.rH = 0
    self.rL = 0
    self.rPC = 0
    self.rSP = 0
    self.rPSR = 2
    self.halted = False
    self.bus_model = bus_model
  async def read(self, addr):
    return await self.bus_model.read(addr)
  async def write(self, addr, value):
    await self.bus_model.write(addr, value)
  async def push(self, value):
    self.rSP = (self.rSP - 1) & 0xffff
    await self.bus_model.write(self.rSP, value)
  async def pop(self):
    data = await self.bus_model.read(self.rSP)
    self.rSP = (self.rSP + 1) & 0xffff
    return data
  def getReg(self, r):
    assert r != 6
    return [self.rB,self.rC,self.rD,self.rE,self.rH,self.rL,0,self.rA][r]
  async def getRegM(self, r):
    if r == 6:
      return await self.read(self.rL | self.rH << 8)
    else:
      return self.getReg(r)
  def setReg(self, r, data):
    if r == 0:
      self.rB = data
    elif r == 1:
      self.rC = data
    elif r == 2:
      self.rD = data
    elif r == 3:
      self.rE = data
    elif r == 4:
      self.rH = data
    elif r == 5:
      self.rL = data
    elif r == 7:
      self.rA = data
    else:
      assert False
  async def setRegM(self, r, data):
    if r == 6:
      await self.write(self.rL | self.rH << 8, data)
    else:
      self.setReg(r, data)
  async def fetch(self):
    data = await self.read(self.rPC)
    self.rPC += 1
    return data
  async def fetch16(self):
    lo = await self.fetch()
    hi = await self.fetch()
    return lo | hi << 8
  async def step(self):
    if self.halted:
      return False
    self.curpc = self.rPC
    ir = await self.fetch()
    #print('PC %.4x IR %.2x AF %.2x%.2x BC %.2x%.2x DE %.2x%.2x HL %.2x%.2x SP %.4x' % (self.curpc, ir, self.rA, self.rPSR, self.rB, self.rC, self.rD, self.rE, self.rH, self.rL, self.rSP))
    if not (ir in cpu_opcodes):
      raise Exception("undefined opcode %.2x" % ir)
    await cpu_opcodes[ir](self)
    return True
  def flags(self, data, S=None, Z=None, P=None, C=None, H=None):
    assert 0 <= data <= 255
    data_flags = {
      'Z': data == 0,
      'S': (data & 0x80) != 0,
      'P': parity(data)
    }
    def do_flag(c, v):
      if v == True:
        self.rPSR |= c
      elif v == False:
        self.rPSR &= ~c
      elif v in data_flags:
        do_flag(c, data_flags[v])
      elif v == None:
        pass
      else:
        assert False
    do_flag(FLAGS, S)
    do_flag(FLAGZ, Z)
    do_flag(FLAGP, P)
    do_flag(FLAGC, C)
    do_flag(FLAGH, H)
  @instruction(0x00)
  async def iNOP(self):
    pass
  @instruction(0x76)
  async def iHLT(self):
    await self.bus_model.halt()
    self.halted = True
  @instruction(0x06, {'dst':(5,3)})
  async def iMVI(self, dst):
    data = await self.fetch()
    await self.setRegM(dst, data)
  @instruction(0x40, {'dst':(5,3), 'src':(2,0)}, exclude=[0x76])
  async def iMOV(self, dst, src):
    data = await self.getRegM(src)
    await self.setRegM(dst, data)
  @instruction(0x80, {'op':(5,3), 'src':(2,0)})
  async def iALU(self, op, src):
    data = await self.getRegM(src)
    (result, carry, half_carry) = alu_op(op, self.rA, data, (self.rPSR & FLAGC) != 0)
    if op != 7:
      self.rA = result
    self.flags(result, S='S', Z='Z', P='P', C=carry, H=half_carry)
  @instruction(0xc6, {'op':(5,3)})
  async def iALU_d8(self, op):
    data = await self.fetch()
    (result, carry, half_carry) = alu_op(op, self.rA, data, (self.rPSR & FLAGC) != 0)
    if op != 7:
      self.rA = result
    self.flags(result, S='S', Z='Z', P='P', C=carry, H=half_carry)
  @instruction(0xc3)
  async def iJMP(self):
    pcL = await self.read(self.rPC)
    self.rPC += 1
    pcH = await self.read(self.rPC)
    self.rPC = pcL | pcH << 8
  @instruction(0xc5)
  async def iPUSH_BC(self):
    await self.push(self.rB)
    await self.push(self.rC)
  @instruction(0xd5)
  async def iPUSH_DE(self):
    await self.push(self.rD)
    await self.push(self.rE)
  @instruction(0xe5)
  async def iPUSH_HL(self):
    await self.push(self.rH)
    await self.push(self.rL)
  @instruction(0xf5)
  async def iPUSH_AF(self):
    await self.push(self.rA)
    await self.push(self.rPSR)
  @instruction(0xc1)
  async def iPOP_BC(self):
    self.rC = await self.pop()
    self.rB = await self.pop()
  @instruction(0xd1)
  async def iPOP_DE(self):
    self.rE = await self.pop()
    self.rD = await self.pop()
  @instruction(0xe1)
  async def iPOP_HL(self):
    self.rL = await self.pop()
    self.rH = await self.pop()
  @instruction(0xf1)
  async def iPOP_AF(self):
    self.rPSR = (await self.pop()) & ~0x28 | 2
    self.rA = await self.pop()
  @instruction(0x01)
  async def iLXI_BC(self):
    self.rC = await self.fetch()
    self.rB = await self.fetch()
  @instruction(0x11)
  async def iLXI_DE(self):
    self.rE = await self.fetch()
    self.rD = await self.fetch()
  @instruction(0x21)
  async def iLXI_HL(self):
    self.rL = await self.fetch()
    self.rH = await self.fetch()
  @instruction(0x31)
  async def iLXI_SP(self):
    self.rSP = await self.fetch16()
  @instruction(0x3a)
  async def iLDA(self):
    self.rA = await self.read(await self.fetch16())
  @instruction(0x32)
  async def iLDA(self):
    await self.write(await self.fetch16(), self.rA)
  @instruction(0x2a)
  async def iLHLD(self):
    addr = await self.fetch16()
    self.rL = await self.read(addr)
    self.rH = await self.read(addr + 1)
  @instruction(0x22)
  async def iSTHD(self):
    addr = await self.fetch16()
    await self.write(addr, self.rL)
    await self.write(addr + 1, self.rH)
  @instruction(0x07)
  async def iRLC(self):
    self.flags(0, C=(self.rA & 0x80) != 0)
    self.rA = (self.rA << 1) & 0xff | self.rA >> 7
  @instruction(0x0f)
  async def iRRC(self):
    self.flags(0, C=(self.rA & 1) != 0)
    self.rA = (self.rA >> 1 | self.rA << 7) & 0xff
  @instruction(0x17)
  async def iRAL(self):
    c = self.rPSR & 1
    self.flags(0, C=(self.rA & 0x80) != 0)
    self.rA = (self.rA << 1 | c) & 0xff
  @instruction(0x1f)
  async def iRAR(self):
    c = self.rPSR & 1
    self.flags(0, C=(self.rA & 1) != 0)
    self.rA = (self.rA >> 1 | c << 7) & 0xff
  @instruction(0x27)
  async def iDAA(self):
    half_carry = False
    carry = False
    if (self.rA & 0x0f) > 9 or (self.rPSR & FLAGH) != 0:
      half_carry = (self.rA & 0x0f) > 9
      self.rA = (self.rA + 6) & 0xff
    if (self.rA & 0xf0) > 0x90 or (self.rPSR & FLAGC) != 0:
      carry = (self.rA & 0xf0) > 0x90
      self.rA = (self.rA + 0x60) & 0xff
    self.flags(self.rA, S='S', Z='Z', P='P', C=carry, H=half_carry)
  @instruction(0x2f)
  async def iCMA(self):
    self.rA ^= 0xff
  @instruction(0x37)
  async def iSTC(self):
    self.flags(0, C=True)
  @instruction(0x3f)
  async def iCMC(self):
    self.rPSR ^= FLAGC

class TestCodeGenerator:
  def __init__(self, memory):
    self.memory = memory
  def set_reg(self, r, value):
    assert r >= 0 and r <= 7 and r != 6
    self.memory.append([0x06 | r << 3, value])
  def random_regs(self):
    for i in range(8):
      if i != 6:
        self.set_reg(i, random.randint(0, 255))
  def check_regs(self):
    self.memory.append([0xc5, 0xd5, 0xe5, 0xf5])
  def test_code(self, code, **kwargs):
    self.random_regs()
    self.memory.append(code)
    if 'jump' in kwargs:
        self.memory.ptr = kwargs['jump']
    self.check_regs()


async def timeout(dut):
  await Timer(1000, units='ms')
  assert False and "TIMED OUT"

async def setup_dut(dut):
  clock = Clock(dut.clk, 1, units="us")
  cocotb.start_soon(clock.start())
  cocotb.start_soon(timeout(dut))
  dut.ena.value = 1
  dut.ui_in.value = 0
  dut.uio_in.value = 0
  dut.rst_n.value = 0
  await ClockCycles(dut.clk, 10)
  dut.rst_n.value = 1

def test():
  def test_decorator(test_fn):
    async def coco_test(dut):
      await setup_dut(dut)
      memory = Memory()
      codegen = TestCodeGenerator(memory)
      await test_fn(dut, codegen)
      memory.append([0x76])
      cpu = CPU(BusModel(memory, dut))
      while await cpu.step():
        pass
    coco_test.__name__ = test_fn.__name__
    coco_test.__qualname__ = test_fn.__name__
    return cocotb.test()(coco_test)
  return test_decorator

@test()
async def test_MVI(dut, codegen):
  for r in range(8):
    codegen.test_code([0x06 | r << 3, random.randint(0, 255)])

@test()
async def test_MOV(dut, codegen):
  for r in range(8):
    for s in range(8):
      if r == 6 and s == 6:
        continue
      codegen.test_code([0x40 | r << 3 | s])

@test()
async def test_NOP(dut, codegen):
  codegen.test_code([0])

@test()
async def test_PUSH_POP(dut, codegen):
  codegen.test_code([0xc5, 0xd5, 0xe5, 0xf5, 0xc1, 0xd1, 0xe1, 0xf1])

@test()
async def test_JUMP(dut, codegen):
  codegen.test_code([0xc3, 0xbe, 0xba], jump=0xbabe)

@test()
async def test_LDA(dut, codegen):
  codegen.test_code([0x3a, random.randint(0, 255), random.randint(0, 255)])

@test()
async def test_STA(dut, codegen):
  codegen.test_code([0x32, random.randint(0, 255), random.randint(0, 255)])

@test()
async def test_LHLD(dut, codegen):
  codegen.test_code([0x2a, random.randint(0, 255), random.randint(0, 255)])

@test()
async def test_SHLD(dut, codegen):
  codegen.test_code([0x22, random.randint(0, 255), random.randint(0, 255)])

@test()
async def test_UNARY(dut, codegen):
  for op in range(8):
    for n in range(20):
      codegen.test_code([0x07 | op << 3])

@test()
async def test_ALU(dut, codegen):
  for op in range(8):
    for r in range(8):
      codegen.test_code([0x80 | op << 3 | r])
    for r in range(20):
      codegen.test_code([0x80 | op << 3])

@test()
async def test_ALU_imm(dut, codegen):
  for op in range(8):
    for r in range(20):
      codegen.test_code([0xc6 | op << 3])

@test()
async def test_LXI(dut, codegen):
  for r in range(4):
      codegen.test_code([0x01 | r << 4, random.randint(0, 255), random.randint(0, 255)])