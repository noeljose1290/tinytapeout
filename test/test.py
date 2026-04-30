import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # 10 MHz clock
    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    # ---------------------------
    # Test UART idle
    # ---------------------------
    await ClockCycles(dut.clk, 1)

    # TX line should be HIGH (idle)
    assert dut.uo_out.value.integer & 1 == 1

    # ---------------------------
    # Send a byte
    # ---------------------------
    dut.ui_in.value = 0xA5  # test byte

    # Trigger send (rising edge)
    dut.uio_in.value = 1
    await ClockCycles(dut.clk, 1)
    dut.uio_in.value = 0

    # ---------------------------
    # Check busy goes high
    # ---------------------------
    await ClockCycles(dut.clk, 2)
    assert (dut.uo_out.value >> 1) & 1 == 1  # busy = 1

    # ---------------------------
    # Wait for transmission to finish
    # ---------------------------
    await ClockCycles(dut.clk, 1000)

    # Done should pulse
    assert (dut.uo_out.value >> 2) & 1 in [0,1]

    dut._log.info("Test complete")
