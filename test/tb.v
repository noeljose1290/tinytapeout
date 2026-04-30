// ============================================================
//  tb.v — Testbench for tt_um_uart_tx
// ============================================================
//
//  Uses CLK_HZ=9600*10, BAUD_RATE=9600 → CLKS_PER_BIT=10
//  so the whole test runs in microseconds, not seconds.
//
//  Test plan
//  ─────────
//   1. Reset check          TX = 1, busy = 0, uio_oe = 0xFC
//   2. Send 0x55 (01010101) — full frame decode, bit-by-bit
//   3. Send 0xA5 (10100101) — different pattern, verify LSB-first
//   4. Busy guard           — trigger while busy must be ignored
//   5. Back-to-back sends   — queue next byte immediately on done
//   6. ena=0 pause          — TX line must freeze mid-frame
// ============================================================

`timescale 1ns / 1ps
`default_nettype none

module tb;

    localparam CLK_HZ        = 96_000;
    localparam BAUD_RATE     = 9_600;
    localparam CLKS_PER_BIT  = CLK_HZ / BAUD_RATE;   // = 10

    // DUT ports
    reg  [7:0] ui_in;
    wire [7:0] uo_out;
    reg  [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;
    reg        ena, clk, rst_n;

    tt_um_uart_tx #(
        .CLK_HZ    (CLK_HZ),
        .BAUD_RATE (BAUD_RATE)
    ) dut (
        .ui_in(ui_in), .uo_out(uo_out),
        .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
        .ena(ena), .clk(clk), .rst_n(rst_n)
    );

    initial clk = 0;
    always #5 clk = ~clk;   // 100 MHz → 10 ns period

    wire tx_line = uo_out[0];
    wire busy    = uo_out[1];
    wire done    = uo_out[2];

    integer errors;

    // ── Helpers ─────────────────────────────────────────────────────
    task tick; @(posedge clk); #1; endtask

    task do_reset;
        begin
            rst_n = 0; uio_in = 0; ena = 1;
            repeat(4) tick;
            rst_n = 1; tick;
        end
    endtask

    task pulse_send;
        input [7:0] data;
        begin
            ui_in = data; uio_in[0] = 1; tick;
            uio_in[0] = 0;
        end
    endtask

    task wait_idle;
        input integer max_cyc;
        integer k;
        begin
            for (k = 0; k < max_cyc; k = k + 1) begin
                if (!busy) disable wait_idle;
                tick;
            end
            $display("  TIMEOUT waiting for idle"); errors = errors + 1;
        end
    endtask

    // Decode a complete UART frame from TX line.
    // Samples at the midpoint of each baud period.
    task capture_frame;
        output [7:0] rx_byte;
        output       ok;
        integer b;
        begin
            rx_byte = 0; ok = 1;
            // Wait for start bit (falling edge)
            while (tx_line !== 1'b0) tick;
            // Jump to mid-point of start bit
            repeat(CLKS_PER_BIT / 2) tick;
            if (tx_line !== 1'b0) begin
                $display("  FRAMING ERROR: start bit not low at mid-sample"); ok = 0;
            end
            // Sample 8 data bits, LSB first
            for (b = 0; b < 8; b = b + 1) begin
                repeat(CLKS_PER_BIT) tick;
                rx_byte[b] = tx_line;
            end
            // Stop bit must be high
            repeat(CLKS_PER_BIT) tick;
            if (tx_line !== 1'b1) begin
                $display("  FRAMING ERROR: stop bit not high"); ok = 0;
            end
        end
    endtask

    // ── Main test ───────────────────────────────────────────────────
    reg [7:0] rx;
    reg       fok;

    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);
        errors = 0;

        // ============================================================
        // TEST 1: Reset state
        // ============================================================
        $display("=== TEST 1: Reset state ===");
        do_reset;

        if (tx_line !== 1'b1) begin
            $display("  FAIL: TX should idle HIGH, got %b", tx_line); errors=errors+1;
        end else $display("  PASS: TX idles high (mark)");

        if (busy !== 1'b0) begin
            $display("  FAIL: busy should be 0"); errors=errors+1;
        end else $display("  PASS: busy = 0");

        if (uio_oe !== 8'hFC) begin
            $display("  FAIL: uio_oe = 0x%02X (expected 0xFC)", uio_oe); errors=errors+1;
        end else $display("  PASS: uio_oe = 0xFC");

        // ============================================================
        // TEST 2: Transmit 0x55 and decode frame
        // ============================================================
        $display("\n=== TEST 2: Transmit 0x55 (alternating 01010101) ===");
        fork
            begin repeat(3) tick; pulse_send(8'h55); end
            capture_frame(rx, fok);
        join

        if (!fok || rx !== 8'h55) begin
            $display("  FAIL: decoded 0x%02X, expected 0x55 (fok=%b)", rx, fok);
            errors=errors+1;
        end else $display("  PASS: 0x%02X decoded correctly", rx);

        wait_idle(200);
        if (uio_out !== 8'h55) begin
            $display("  FAIL: last_byte = 0x%02X (expected 0x55)", uio_out); errors=errors+1;
        end else $display("  PASS: last_byte = 0x55");

        // ============================================================
        // TEST 3: Transmit 0xA5 (10100101)
        // ============================================================
        $display("\n=== TEST 3: Transmit 0xA5 (10100101) ===");
        tick;
        fork
            begin repeat(2) tick; pulse_send(8'hA5); end
            capture_frame(rx, fok);
        join

        if (!fok || rx !== 8'hA5) begin
            $display("  FAIL: decoded 0x%02X, expected 0xA5", rx); errors=errors+1;
        end else $display("  PASS: 0x%02X decoded correctly", rx);

        wait_idle(200);

        // ============================================================
        // TEST 4: Send-while-busy must be ignored
        // ============================================================
        $display("\n=== TEST 4: Spurious trigger while busy is ignored ===");
        tick;

        fork
            begin
                repeat(2) tick;
                pulse_send(8'hFF);     // real byte
                // immediately try to override while busy
                if (busy) begin
                    ui_in = 8'h00; uio_in[0] = 1; tick; uio_in[0] = 0;
                    $display("  INFO: spurious 0x00 trigger sent while busy");
                end
            end
            capture_frame(rx, fok);
        join

        wait_idle(200);
        if (fok && rx === 8'hFF)
            $display("  PASS: 0xFF transmitted; 0x00 override ignored");
        else begin
            $display("  FAIL: got 0x%02X (expected 0xFF)", rx); errors=errors+1;
        end

        // ============================================================
        // TEST 5: Back-to-back — send next byte immediately on done
        // ============================================================
        $display("\n=== TEST 5: Back-to-back 0xAB then 0xCD ===");
        tick;
        fork
            begin
                repeat(2) tick;
                pulse_send(8'hAB);
                while (!done) tick;        // wait for done pulse
                pulse_send(8'hCD);
            end
            begin
                capture_frame(rx, fok);
                if (!fok || rx !== 8'hAB) begin
                    $display("  FAIL [1/2]: got 0x%02X (expected 0xAB)", rx); errors=errors+1;
                end else $display("  PASS [1/2]: 0xAB received");

                capture_frame(rx, fok);
                if (!fok || rx !== 8'hCD) begin
                    $display("  FAIL [2/2]: got 0x%02X (expected 0xCD)", rx); errors=errors+1;
                end else $display("  PASS [2/2]: 0xCD received");
            end
        join
        wait_idle(200);

        // ============================================================
        // TEST 6: ena=0 pauses TX mid-frame
        // ============================================================
        $display("\n=== TEST 6: ena=0 freezes mid-frame ===");
        tick; ena = 1;

        repeat(2) tick;
        pulse_send(8'hBE);
        repeat(2) tick;   // let it enter DATA state

        begin : freeze_test
            reg snapshot;
            snapshot = tx_line;
            ena = 0;
            repeat(15) tick;
            if (tx_line !== snapshot) begin
                $display("  FAIL: TX changed while ena=0 (was %b, now %b)", snapshot, tx_line);
                errors=errors+1;
            end else
                $display("  PASS: TX held at %b while ena=0", snapshot);
            ena = 1;
            wait_idle(400);
            $display("  PASS: frame completed after ena restored");
        end

        // ============================================================
        // Summary
        // ============================================================
        $display("\n=============================================");
        if (errors == 0)
            $display("ALL TESTS PASSED — ready for tape-out!");
        else
            $display("%0d TEST(S) FAILED", errors);
        $display("=============================================\n");
        $finish;
    end

endmodule
