# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: MIT

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer

def memory_read(addr):
  if addr == 7:
    return 2
  return (addr % 7) > 0

def memory_write(addr, data):
  print(hex(addr), hex(data))

async def bus_cycle(dut):
  addr = 0
  while (dut.uo_out.value & 1) == 0:
    await ClockCycles(dut.clk, 1)
  assert dut.uio_oe.value == 255
  is_write = (dut.uo_out.value & 2) != 0
  addr = dut.uio_out.value
  dut.ui_in.value = 1
  while (dut.uo_out.value & 1) != 0:
    await ClockCycles(dut.clk, 1)
  dut.ui_in.value = 0
  while (dut.uo_out.value & 1) == 0:
    await ClockCycles(dut.clk, 1)
  assert dut.uio_oe.value == 255
  addr = addr | dut.uio_out.value << 8
  dut.ui_in.value = 1
  while (dut.uo_out.value & 1) != 0:
    await ClockCycles(dut.clk, 1)
  dut.ui_in.value = 0
  while (dut.uo_out.value & 1) == 0:
    await ClockCycles(dut.clk, 1)
  if is_write:
    memory_write(addr, dut.uio_out.value)
  else:
    dut.uio_in.value = memory_read(addr)
    await ClockCycles(dut.clk, 1)
  dut.ui_in.value = 1
  while (dut.uo_out.value & 1) != 0:
    await ClockCycles(dut.clk, 1)
  dut.ui_in.value = 0

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

  while True:
    await bus_cycle(dut)

  # assert dut.uo_out.value == 50
