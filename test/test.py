import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    dut._log.info("Test project behavior")
    dut.ui_in.value = 20
    dut.uio_in.value = 30
    await ClockCycles(dut.clk, 1)
    for i in range(32):
        await ClockCycles(dut.clk, 256)
        dut._log.info(f"Cycle {(i+1)*256}: uio_out = {dut.uio_out.value}")
        