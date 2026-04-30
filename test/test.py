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
    assert dut.uo_out.value[0] == 1  # TX idle high

    # ---------------------------
    # Send a byte
    # ---------------------------
    dut.ui_in.value = 0xA5

    dut.uio_in.value = 1
    await ClockCycles(dut.clk, 1)
    dut.uio_in.value = 0

    # ---------------------------
    # Check busy
    # ---------------------------
    await ClockCycles(dut.clk, 2)
    assert dut.uo_out.value[1] == 1

    # ---------------------------
    # Wait for done pulse
    # ---------------------------
    done_seen = False

    for _ in range(2000):
        await ClockCycles(dut.clk, 1)
        if dut.uo_out.value[2] == 1:
            done_seen = True
            break

    assert done_seen, "Done signal never asserted"

    dut._log.info("Test complete")
