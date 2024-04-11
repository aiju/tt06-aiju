# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: MIT

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer

class Memory:
  def __init__(self):
    self.contents = [6,23,0x3E,42,0x80,2] + [0] * 65536
  def read(self, addr):
    return self.contents[addr]
  def write(self, addr, value):
    self.contents[addr] = value

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
    self.bus_model = bus_model
  async def read(self, addr):
    return await self.bus_model.read(addr)
  async def write(self, addr, value):
    await self.bus_model.write(addr, value)
  def getReg(self, r):
    return [self.rB,self.rC,self.rD,self.rE,self.rH,self.rL,0,self.rA][r]
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
  async def step(self):
    ir = await self.read(self.rPC)
    self.rPC += 1
    if ir == 0:
      self.rA = 0
    elif ir == 1:
      self.rA = (self.rA + 1) & 255
    elif ir == 2:
      await self.write(0xcafe, self.rA)
    elif (ir & 0xc7) == 0x06:
      data = await self.read(self.rPC)
      self.rPC += 1
      self.setReg(ir >> 3 & 7, data)
    elif (ir & 0xc0) == 0x40:
      data = self.getReg(ir & 7)
      self.setReg(ir >> 3 & 7, data)
    elif (ir & 0xc0) == 0x80:
      data = self.getReg(ir & 7)
      self.rA = (self.rA + data) & 255


async def timeout(dut):
  await Timer(1000, units='us')
  assert False and "TIMED OUT"

@cocotb.test()
async def test_project(dut):
  dut._log.info("Start")
  
  # Our example module doesn't use clock and reset, but we show how to use them here anyway.
  clock = Clock(dut.clk, 1, units="us")
  cocotb.start_soon(clock.start())
  cocotb.start_soon(timeout(dut))

  # Reset
  dut._log.info("Reset")
  dut.ena.value = 1
  dut.ui_in.value = 0
  dut.uio_in.value = 0
  dut.rst_n.value = 0
  await ClockCycles(dut.clk, 10)
  dut.rst_n.value = 1

  # Set the input values, wait one clock cycle, and check the output
  dut._log.info("Test")

  cpu = CPU(BusModel(Memory(), dut))
  for i in range(20):
    await cpu.step()

  # assert dut.uo_out.value == 50
