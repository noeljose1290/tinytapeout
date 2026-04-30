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
    # Wait for GL signals to settle
    # ---------------------------
    await ClockCycles(dut.clk, 20)

    # ---------------------------
    # Test UART idle
    # ---------------------------
    tx = dut.uo_out.value[0]

    assert tx.is_resolvable, "TX is still X after reset"
    assert int(tx) == 1, "TX should be idle high"

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
    await ClockCycles(dut.clk, 5)

    busy = dut.uo_out.value[1]
    assert busy.is_resolvable, "Busy is X"
    assert int(busy) == 1, "Busy should be high during TX"

    # ---------------------------
    # Wait for done pulse
    # ---------------------------
    done_seen = False

    for _ in range(3000):   # extra margin for GL delays
        await ClockCycles(dut.clk, 1)
        done = dut.uo_out.value[2]

        if done.is_resolvable and int(done) == 1:
            done_seen = True
            break

    assert done_seen, "Done signal never asserted"

    dut._log.info("Test complete")
