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

class RandomIOModel:
  def io_in(self, port):
    return random.randint(0, 255)
  def io_out(self, port, data):
    pass

class BusModel:
  def __init__(self, memory, io_model, dut):
    self.memory = memory
    self.io_model = io_model
    self.dut = dut
  async def handshake_begin(self):
    while (self.dut.uo_out.value & 1) == 0:
      await ClockCycles(self.dut.clk, 1)
  async def handshake_end(self):
    self.dut.ui_in.value = self.dut.ui_in.value | 1
    while (self.dut.uo_out.value & 1) != 0:
      await ClockCycles(self.dut.clk, 1)
    self.dut.ui_in.value = self.dut.ui_in.value & ~1
  def read_bus(self):
    assert self.dut.uio_oe.value == 0xff
    return self.dut.uio_out.value
  def write_bus(self, value):
    assert self.dut.uio_oe.value == 0x00
    self.dut.uio_in.value = value
  def clear_bus(self):
    self.dut.uio_in.value = cocotb.binary.BinaryValue('xxxxxxxx')
  def assert_state(self, state, io):
    assert (self.dut.uo_out.value >> 1 & 7) == (state | int(io) << 2)
  async def bus_read(self, addr, value, io):
    await self.handshake_begin()
    self.assert_state(0, io)
    assert self.read_bus() == (addr & 0xff)
    await self.handshake_end()
    await self.handshake_begin()
    self.assert_state(1, io)
    assert self.read_bus() == (addr >> 8)
    await self.handshake_end()
    await self.handshake_begin()
    self.assert_state(2, io)
    self.write_bus(value)
    await ClockCycles(self.dut.clk, 1)
    await self.handshake_end()
    self.clear_bus()
  async def read(self, addr, io=False):
    if io:
      value = self.io_model.io_in(addr)
    else:
      value = self.memory.read(addr)
    await self.bus_read(addr, value, io)
    return value
  async def dummy_read(self, io):
    await self.handshake_begin()
    self.assert_state(0, io)
    await self.handshake_end()
    await self.handshake_begin()
    self.assert_state(1, io)
    await self.handshake_end()
    await self.handshake_begin()
    self.assert_state(2, io)
    await self.handshake_end()
  async def bus_write(self, addr, io):
    await self.handshake_begin()
    self.assert_state(0, io)
    assert self.read_bus() == (addr & 0xff)
    await self.handshake_end()
    await self.handshake_begin()
    self.assert_state(1, io)
    assert self.read_bus() == (addr >> 8)
    await self.handshake_end()
    await self.handshake_begin()
    self.assert_state(3, io)
    value = self.read_bus()
    await self.handshake_end()
    return value
  async def write(self, addr, value, io=False):
    if io:
      self.io_model.io_out(addr, value)
    else:
      self.memory.write(addr, value)
    assert (await self.bus_write(addr, io)) == value
  async def halt(self):
    await ClockCycles(self.dut.clk, 20)
    assert (self.dut.uo_out.value & 0x40) != 0
  async def enter_debug(self):
    self.dut.ui_in.value = self.dut.ui_in.value | 2
    await ClockCycles(self.dut.clk, 1)
    if (self.dut.uo_out.value & 0x40) == 0:
      await self.dummy_read(False)
    await ClockCycles(self.dut.clk, 20)
    assert (self.dut.uo_out.value & 0x20) != 0
    self.dut.ui_in.value = self.dut.ui_in.value & ~2
    await ClockCycles(self.dut.clk, 1)
  async def debug_read(self, addr):
    await self.bus_read(0xcafe, addr, True)
    return await self.bus_write(0xcaff, True)
  async def debug_write(self, addr, value):
    await self.bus_read(0xcafe, 0x80 | addr, True)
    await self.bus_read(0xcaff, value, True)
  async def leave_debug(self):
    await self.bus_read(0xcafe, 0x40, True)
    while (self.dut.uo_out.value & 0x20) != 0:
      await ClockCycles(self.dut.clk, 1)
  async def set_int_req(self):
    await ClockCycles(self.dut.clk, 1)
    self.dut.ui_in.value = self.dut.ui_in.value | 4
    await ClockCycles(self.dut.clk, 1)
  async def int_ack(self):
    await ClockCycles(self.dut.clk, 10)
    assert (self.dut.uo_out.value & 0x80) != 0x00
    self.dut.ui_in.value = self.dut.ui_in.value & ~4
    await ClockCycles(self.dut.clk, 1)

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
  half_carry_out = ((a & 15) - (b & 15) - int(borrow)) >= 0
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
    self.int_enabled = False
  async def read(self, addr, io=False):
    return await self.bus_model.read(addr, io)
  async def write(self, addr, value, io=False):
    await self.bus_model.write(addr, value, io)
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
  async def step_and_interrupt(self, instr):
    assert self.int_enabled
    await self.bus_model.set_int_req()
    await self.step()
    await self.bus_model.int_ack()
    self.int_enabled = False
    self.halted = False
    await self.bus_model.bus_read(self.rPC, instr, False)
    await cpu_opcodes[instr](self)
  def flags(self, data, S=None, Z=None, P=None, C=None, H=None):
    assert 0 <= data <= 255
    data_flags = {
      'Z': data == 0,
      'S': (data & 0x80) != 0,
      'P': not parity(data)
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
  async def iSTA(self):
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
    value = 0
    if (self.rA & 0x0f) > 9 or (self.rPSR & FLAGH) != 0:
      value += 0x06
    if self.rA >= 0x9a or (self.rPSR & FLAGC) != 0:
      value += 0x60
    old_carry = (self.rPSR & FLAGC) != 0
    self.rA, carry, half_carry = addition(self.rA, value, False)
    self.flags(self.rA, S='S', Z='Z', P='P', C=(old_carry or carry), H=half_carry)
  @instruction(0x2f)
  async def iCMA(self):
    self.rA ^= 0xff
  @instruction(0x37)
  async def iSTC(self):
    self.flags(0, C=True)
  @instruction(0x3f)
  async def iCMC(self):
    self.rPSR ^= FLAGC
  @instruction(0xcd)
  async def iCALL(self):
    target = await self.fetch16()
    await self.push(self.rPC >> 8)
    await self.push(self.rPC & 0xff)
    self.rPC = target
  @instruction(0xc9)
  async def iRET(self):
    lo = await self.pop()
    hi = await self.pop()
    self.rPC = lo | hi << 8
  def check_cond(self, cond):
    assert 0 <= cond <= 7
    flag = [FLAGZ, FLAGC, FLAGP, FLAGS][cond>>1]
    return ((self.rPSR & flag) != 0) == ((cond & 1) != 0)
  @instruction(0xc4, {'cond':(5,3)})
  async def iCALLcc(self, cond):
    target = await self.fetch16()
    if self.check_cond(cond):
      await self.push(self.rPC >> 8)
      await self.push(self.rPC & 0xff)
      self.rPC = target
  @instruction(0xc0, {'cond':(5,3)})
  async def iRETcc(self, cond):
    if self.check_cond(cond):
      lo = await self.pop()
      hi = await self.pop()
      self.rPC = lo | hi << 8
  @instruction(0xc2, {'cond':(5,3)})
  async def iJMPcc(self, cond):
    target = await self.fetch16()
    if self.check_cond(cond):
      self.rPC = target
  @instruction(0xc7, {'n':(5,3)})
  async def iRST(self, n):
    await self.push(self.rPC >> 8)
    await self.push(self.rPC & 0xff)
    self.rPC = n * 8
  @instruction(0xe9)
  async def iPCHL(self):
    self.rPC = self.rL | self.rH << 8
  @instruction(0xf9)
  async def iSPHL(self):
    self.rSP = self.rL | self.rH << 8
  @instruction(0x04, {'r':(5,3)})
  async def iINR(self, r):
    data = await self.getRegM(r)
    (data, _, half_carry) = addition(data, 1, False)
    await self.setRegM(r, data)
    self.flags(data, S='S', Z='Z', P='P', H=half_carry)
  @instruction(0x05, {'r':(5,3)})
  async def iDCR(self, r):
    data = await self.getRegM(r)
    (data, _, half_carry) = subtraction(data, 1, False)
    await self.setRegM(r, data)
    self.flags(data, S='S', Z='Z', P='P', H=half_carry)
  @instruction(0x03)
  async def iINX_BC(self):
    self.rC = (self.rC + 1) & 0xff
    if self.rC == 0:
      self.rB = (self.rB + 1) & 0xff
  @instruction(0x13)
  async def iINX_DE(self):
    self.rE = (self.rE + 1) & 0xff
    if self.rE == 0:
      self.rD = (self.rD + 1) & 0xff
  @instruction(0x23)
  async def iINX_HL(self):
    self.rL = (self.rL + 1) & 0xff
    if self.rL == 0:
      self.rH = (self.rH + 1) & 0xff
  @instruction(0x33)
  async def iINX_SP(self):
    self.rSP = (self.rSP + 1) & 0xffff
  @instruction(0x0B)
  async def iDCX_BC(self):
    self.rC = (self.rC - 1) & 0xff
    if self.rC == 0xff:
      self.rB = (self.rB - 1) & 0xff
  @instruction(0x1B)
  async def iDCX_DE(self):
    self.rE = (self.rE - 1) & 0xff
    if self.rE == 0xff:
      self.rD = (self.rD - 1) & 0xff
  @instruction(0x2B)
  async def iDCX_HL(self):
    self.rL = (self.rL - 1) & 0xff
    if self.rL == 0xff:
      self.rH = (self.rH - 1) & 0xff
  @instruction(0x3B)
  async def iDCX_SP(self):
    self.rSP = (self.rSP - 1) & 0xffff
  @instruction(0x09)
  async def iDAD_BC(self):
    (self.rL, carry, _) = addition(self.rL, self.rC, False)
    (self.rH, carry, _) = addition(self.rH, self.rB, carry)
    self.flags(0, C=carry)
  @instruction(0x19)
  async def iDAD_DE(self):
    (self.rL, carry, _) = addition(self.rL, self.rE, False)
    (self.rH, carry, _) = addition(self.rH, self.rD, carry)
    self.flags(0, C=carry)
  @instruction(0x29)
  async def iDAD_HL(self):
    (self.rL, carry, _) = addition(self.rL, self.rL, False)
    (self.rH, carry, _) = addition(self.rH, self.rH, carry)
    self.flags(0, C=carry)
  @instruction(0x39)
  async def iDAD_SP(self):
    (self.rL, carry, _) = addition(self.rL, self.rSP & 0xff, False)
    (self.rH, carry, _) = addition(self.rH, self.rSP >> 8, carry)
    self.flags(0, C=carry)
  @instruction(0x0a)
  async def iLDAX_BC(self):
    self.rA = await self.read(self.rC | self.rB << 8)
  @instruction(0x1a)
  async def iLDAX_DE(self):
    self.rA = await self.read(self.rE | self.rD << 8)
  @instruction(0x02)
  async def iSTAX_BC(self):
    await self.write(self.rC | self.rB << 8, self.rA)
  @instruction(0x12)
  async def iSTAX_DE(self):
    await self.write(self.rE | self.rD << 8, self.rA)
  @instruction(0xEB)
  async def iXCHG(self):
    self.rH, self.rD = self.rD, self.rH
    self.rL, self.rE = self.rE, self.rL
  @instruction(0xE3)
  async def iXTHL(self):
    oldVal = self.rL
    self.rL = await self.read(self.rSP)
    await self.write(self.rSP, oldVal)
    oldVal = self.rH
    self.rH = await self.read(self.rSP + 1)
    await self.write(self.rSP + 1, oldVal)
  @instruction(0xfb)
  async def iEI(self):
    self.int_enabled = True
  @instruction(0xf3)
  async def iDI(self):
    self.int_enabled = False
  @instruction(0xdb)
  async def iIN(self):
    port = await self.fetch()
    self.rA = await self.read(port, True)
  @instruction(0xd3)
  async def iOUT(self):
    port = await self.fetch()
    await self.write(port, self.rA, True)
  async def debug(self):
    await self.bus_model.enter_debug()
    mapping = [
      ('A', 15, self.rA), ('B', 8, self.rB), ('C', 9, self.rC), ('D', 10, self.rD),
      ('E', 11, self.rE), ('H', 12, self.rH), ('L', 13, self.rL), ('PSR', 6, self.rPSR),
      ('PC', (17, 16), self.rPC), ('SP', (5,4), self.rSP)
    ]
    for name, addr, expected in mapping:
      if isinstance(addr, tuple):
        (hi, lo) = addr
        hi_value = await self.bus_model.debug_read(hi)
        lo_value = await self.bus_model.debug_read(lo)
        got = lo_value | hi_value << 8
      else:
        got = await self.bus_model.debug_read(addr)
      if expected != got:
        raise "mismatch for %s, expected 0x%x, got 0x%x" % (name, expected, got)
    await self.bus_model.leave_debug()

class TestCodeGenerator:
  def __init__(self, memory):
    self.memory = memory
  def set_reg(self, r, value):
    assert r >= 0 and r <= 7 and r != 6
    self.memory.append([0x06 | r << 3, value])
  def random_regs(self):
    self.memory.append([0x01, random.randint(0, 255), random.randint(0, 255), 0xc5, 0xf1])
    for i in range(6):
      self.set_reg(i, random.randint(0, 255))
  def check_regs(self):
    self.memory.append([0xc5, 0xd5, 0xe5, 0xf5])
  def test_code(self, code, **kwargs):
    self.random_regs()
    self.memory.append(code)
    if 'jump' in kwargs:
      self.memory.ptr = kwargs['jump']
    if 'after_jump' in kwargs:
      self.memory.append(kwargs['after_jump'])
    self.check_regs()


async def timeout(dut):
  await Timer(10000, units='ms')
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
      cpu = CPU(BusModel(memory, RandomIOModel(), dut))
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
async def test_JMP(dut, codegen):
  codegen.test_code([0xc3, 0xbe, 0xba], jump=0xbabe)

@test()
async def test_CALL(dut, codegen):
  codegen.test_code([0xcd, 0xbe, 0xba], jump=0xbabe, after_jump=[0xc1])

@test()
async def test_CALLcc(dut, codegen):
  for cc in range(8):
    for n in range(4):
      codegen.test_code([0xc4 | cc << 3, 0xbe, 0xba])
  codegen.memory.write(0xbabe, 0xc9)

@test()
async def test_RETcc(dut, codegen):
  loc = 0x1000
  for cc in range(8):
    for n in range(4):
      codegen.test_code([0xcd, loc&0xff, loc>>8])
      codegen.memory.write(loc, 0xc0 | cc << 3)
      codegen.memory.write(loc+1, 0x2f)
      codegen.memory.write(loc+2, 0xc9)
      loc += 23

@test()
async def test_JMPcc(dut, codegen):
  loc = 0x1000
  for cc in range(8):
    for n in range(16):
      codegen.test_code([0xc2 | cc << 3, loc&0xff, loc>>8])
      codegen.memory.write(loc, 0x2f)
      codegen.memory.write(loc+1, 0xc3)
      codegen.memory.write(loc+2, codegen.memory.ptr & 0xff)
      codegen.memory.write(loc+3, codegen.memory.ptr >> 8)
      loc += 23

@test()
async def test_RET(dut, codegen):
  codegen.test_code([0x01, 0xbe, 0xba, 0xc5, 0xc9], jump=0xbabe)

@test()
async def test_CALL_RET(dut, codegen):
  codegen.test_code([0xcd, 0xbe, 0xba])
  codegen.memory.write(0xbabe, 0x2f)
  codegen.memory.write(0xbabe, 0xc9)

@test()
async def test_RST(dut, codegen):
  codegen.memory.append([0x3E, 0xC9, 0x32, 0x00, 0x00, 0xc3, 0x00, 0x10])
  for i in range(1, 8):
    codegen.memory.write(i * 8, 0xc9)
  codegen.memory.ptr = 0x1000
  for n in range(8):
    codegen.test_code([0xc7 | n << 3])

@test()
async def test_PCHL(dut, codegen):
  codegen.test_code([0x21, 0xbe, 0xba, 0xe9], jump=0xbabe)

@test()
async def test_SPHL(dut, codegen):
  codegen.test_code([0xf9])

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
async def test_INR_DCR(dut, codegen):
  for op in range(2):
    for r in range(8):
      codegen.test_code([0x04 | op | r << 3])

@test()
async def test_INX_DCX(dut, codegen):
  for op in range(2):
    for r in range(4):
      codegen.test_code([0x03 | op << 3 | r << 4])
      codegen.test_code([0x0E | r << 4, [0xFF, 0x00][op], 0x03 | op << 3 | r << 4])

@test()
async def test_LDAX_STAX(dut, codegen):
  for op in range(2):
    for r in range(2):
      codegen.test_code([0x02 | op << 3 | r << 4])

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

@test()
async def test_XCHG(dut, codegen):
  codegen.test_code([0xEB])

@test()
async def test_XTHL(dut, codegen):
  codegen.test_code([0xD5, 0xE3])

@test()
async def test_DAD(dut, codegen):
  for r in range(4):
    for n in range(8):
      codegen.test_code([0x09 | r << 4])

@test()
async def test_DAA(dut, codegen):
  for n in range(64):
    codegen.test_code([0x27])

@test()
async def test_IO(dut, codegen):
  codegen.test_code([0xDB, random.randint(0, 255)])
  codegen.test_code([0xD3, random.randint(0, 255)])

@cocotb.test()
async def test_DEBUG(dut):
  await setup_dut(dut)
  memory = Memory()
  codegen = TestCodeGenerator(memory)
  codegen.test_code([0x00])
  memory.append([0x76])
  cpu = CPU(BusModel(memory, RandomIOModel(), dut))
  while await cpu.step():
    pass
  await cpu.debug()

@cocotb.test()
async def test_INT(dut):
  await setup_dut(dut)
  memory = Memory()
  codegen = TestCodeGenerator(memory)
  memory.append([0xc3, 0x00, 0x10])
  memory.ptr = 24
  memory.append([0x2f, 0xfb, 0xc9])
  memory.ptr = 0x1000
  memory.append([0xfb])
  for n in range(64):
    codegen.test_code([0x27])
  memory.append([0x76, 0x76, 0x76, 0x76])
  cpu = CPU(BusModel(memory, RandomIOModel(), dut))
  next_int = random.randint(10,20)
  while True:
    if next_int == 0:
      await cpu.step_and_interrupt(0xdf)
      next_int = random.randint(10,20)
    else:
      next_int -= 1
      if not await cpu.step():
        break

@cocotb.test()
async def test_INT_HALT(dut):
  await setup_dut(dut)
  memory = Memory()
  codegen = TestCodeGenerator(memory)
  memory.append([0xc3, 0x00, 0x10])
  memory.ptr = 24
  memory.append([0x2f, 0xfb, 0xc9])
  memory.ptr = 0x1000
  memory.append([0xfb])
  for i in range(10):
    memory.append([0x76])
  cpu = CPU(BusModel(memory, RandomIOModel(), dut))
  while await cpu.step():
    pass
  await cpu.step_and_interrupt(0xdf)
  for i in range(10):
    await cpu.step()

class MSBasicIOModel:
  def __init__(self):
    self.input_buffer = " 20000\r\rY\r10 INPUT R\r20 PRINT 3.14159 * R * R\r30 END\rRUN\r 4\r"
  def io_in(self, port):
    if port == 0:
      return self.input_buffer == ""
    elif port == 1:
      c = ord(self.input_buffer[0])
      self.input_buffer = self.input_buffer[1:]
      return c
    elif port == 0xff:
      return 0
    else:
      print("read from unknown IO port %.2x" % port)
    return 0
  def io_out(self, port, data):
    if port == 1:
      print(chr(data & 0x7f), end='', flush=True)
    else:
      print("write to unknown IO port %.2x data %.2x" % (port, data))

@cocotb.test(skip=True)
async def test_msbasic(dut):
  await setup_dut(dut)
  memory = Memory()
  with open('4kbas32.bin', 'rb') as file:
    basic = list(file.read())
  for i in range(len(basic)):
    memory.write(i, basic[i])
  cpu = CPU(BusModel(memory, MSBasicIOModel(), dut))
  while cpu.rPC != 0x1f8:
    await cpu.step()

class DummyBusModel:
  def __init__(self, memory, io_model):
    self.memory = memory
    self.io_model = io_model
  async def read(self, addr, io=False):
    if io:
      return self.io_model.io_in(addr)
    else:
      return self.memory.read(addr)
  async def write(self, addr, value, io=False):
    if io:
      return self.io_model.io_out(addr, value)
    else:
      return self.memory.write(addr, value)

class CPMIOModel:
  def io_in(self, port):
    print("read from unknown IO port %.2x" % port)
    return 0
  def io_out(self, port, data):
    if port == 0xcc:
      cmd = self.cpu.rC
      if cmd == 2:
        print(chr(self.cpu.rE), end='', flush=True)
      elif cmd == 9:
        addr = self.cpu.rD << 8 | self.cpu.rE
        while self.cpu.bus_model.memory.read(addr) != ord('$'):
          print(chr(self.cpu.bus_model.memory.read(addr)), end='', flush=True)
          addr += 1
      else:
        print("unknown cp/m call %.2x" % cmd)
    else:
      print("write to unknown IO port %.2x data %.2x" % (port, data))

@cocotb.test(skip=True)
async def test_exerciser(dut):
  await setup_dut(dut)
  memory = Memory()
  with open('8080EX1.COM', 'rb') as file:
    rom = list(file.read())
  for i in range(len(rom)):
    memory.write(0x100 + i, rom[i])
  memory.write(0x120, memory.read(0x120) + 2)
  memory.write(5, 0xd3)
  memory.write(6, 0xcc)
  memory.write(7, 0xc9)
  io_model = CPMIOModel()
  cpu = CPU(DummyBusModel(memory, io_model))
  io_model.cpu = cpu
  cpu.rPC = 0x100
  n = 0
  while cpu.rPC != 0x00:
    await cpu.step()
    n += 1
    if (n % 1000000) == 0:
      print(('%10d' % n) + '\b' * 9, end='', flush=True)