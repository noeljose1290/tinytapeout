// ============================================================
//  tt_um_uart_tx — 8N1 UART Transmitter
// ============================================================
//
//  A real, working UART transmitter you can wire directly to a
//  USB-serial adapter and read bytes on any terminal (minicom,
//  PuTTY, screen, etc.).  Format: 8 data bits, no parity, 1 stop bit.
//
//  Default: 115 200 baud at a 10 MHz system clock (TT default).
//  Change CLK_HZ / BAUD_RATE parameters to match your setup.
//
//  Common CLKS_PER_BIT values (= CLK_HZ / BAUD_RATE):
//    9 600 baud  @ 10 MHz  →  1 042
//   57 600 baud  @ 10 MHz  →    174
//  115 200 baud  @ 10 MHz  →     87   ← default
//  115 200 baud  @ 50 MHz  →    434
//
//  Pin map
//  ───────────────────────────────────────────────────
//  ui_in  [7:0]   Byte to transmit (sampled on rising send edge)
//  uio_in [0]     send — rising edge starts one TX frame
//  uio_in [1]     (unused, tie low)
//
//  uo_out [0]     TX  — connect to RXD of your USB-serial dongle
//  uo_out [1]     busy  — high while a frame is in progress
//  uo_out [2]     done  — one-clock pulse when stop bit completes
//  uo_out [7:3]   (always 0)
//
//  uio_out[7:0]   last_byte — last successfully transmitted byte
//  uio_oe         0x00_00_FC  → bits 7:2 output, bits 1:0 input
//  ───────────────────────────────────────────────────
//
//  Typical wiring
//  ───────────────────────────────────────────────────
//    Chip uo_out[0] ──► USB-serial RXD
//    USB-serial GND ──► Chip GND
//    (no connection needed for TX-only; add RX later)
 
`default_nettype none
 
module tt_um_uart_tx #(
    parameter CLK_HZ    = 10_000_000,   // system clock frequency in Hz
    parameter BAUD_RATE = 115_200       // desired baud rate
) (
    input  wire [7:0] ui_in,    // byte to send
    output wire [7:0] uo_out,   // TX, busy, done
    input  wire [7:0] uio_in,   // uio_in[0] = send trigger
    output wire [7:0] uio_out,  // last byte sent
    output wire [7:0] uio_oe,   // direction: bits 7:2 out, 1:0 in
    input  wire       ena,      // clock enable
    input  wire       clk,
    input  wire       rst_n     // active-low reset
);
 
    // ----------------------------------------------------------------
    //  Baud-rate timing
    // ----------------------------------------------------------------
    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD_RATE;
    localparam integer CTR_W        = $clog2(CLKS_PER_BIT + 1);
 
    // ----------------------------------------------------------------
    //  Rising-edge detector on the send pin
    // ----------------------------------------------------------------
    reg send_d0, send_d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) { send_d0, send_d1 } <= 2'b00;
        else        { send_d1, send_d0 } <= { send_d0, uio_in[0] };
    end
    wire send_rise = send_d0 & ~send_d1;   // one-cycle pulse on rising edge
 
    // ----------------------------------------------------------------
    //  State machine
    // ----------------------------------------------------------------
    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;
 
    reg  [1:0]       state;
    reg  [2:0]       bit_idx;               // 0-7: which data bit
    reg  [CTR_W-1:0] clk_cnt;              // baud-period counter
    reg  [7:0]       shift;                // TX shift register
    reg              tx_line;              // the actual serial bit
    reg              busy;
    reg              done;
    reg  [7:0]       last_byte;
 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            bit_idx   <= 3'd0;
            clk_cnt   <= {CTR_W{1'b0}};
            shift     <= 8'hFF;
            tx_line   <= 1'b1;              // UART idle = mark (high)
            busy      <= 1'b0;
            done      <= 1'b0;
            last_byte <= 8'h00;
        end else if (ena) begin
            done <= 1'b0;                   // pulse for exactly one clock
 
            case (state)
 
                // ── Idle: wait for a rising edge on send ────────────
                S_IDLE: begin
                    tx_line <= 1'b1;
                    busy    <= 1'b0;
                    if (send_rise) begin
                        shift   <= ui_in;   // latch the byte
                        clk_cnt <= {CTR_W{1'b0}};
                        busy    <= 1'b1;
                        state   <= S_START;
                    end
                end
 
                // ── Start bit (logic 0 for one baud period) ─────────
                S_START: begin
                    tx_line <= 1'b0;
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= {CTR_W{1'b0}};
                        bit_idx <= 3'd0;
                        state   <= S_DATA;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end
 
                // ── 8 data bits, LSB first ───────────────────────────
                S_DATA: begin
                    tx_line <= shift[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= {CTR_W{1'b0}};
                        if (bit_idx == 3'd7)
                            state <= S_STOP;
                        else
                            bit_idx <= bit_idx + 1'b1;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end
 
                // ── Stop bit (logic 1 for one baud period) ──────────
                S_STOP: begin
                    tx_line <= 1'b1;
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt   <= {CTR_W{1'b0}};
                        last_byte <= shift;
                        done      <= 1'b1;
                        busy      <= 1'b0;
                        state     <= S_IDLE;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end
 
            endcase
        end
    end
 
    // ----------------------------------------------------------------
    //  Output assignments
    // ----------------------------------------------------------------
    assign uo_out  = {5'b00000, done, busy, tx_line};
    assign uio_out = last_byte;             // echo for easy verification
    assign uio_oe  = 8'hFC;                // bits 7:2 → output, 1:0 → input
 
    // silence unused-input lint warnings
    wire _unused_ok = &{uio_in[7:1]};
 
endmodule
