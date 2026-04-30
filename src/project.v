`default_nettype none

module tt_um_uart_tx #(
    parameter CLK_HZ    = 10_000_000,
    parameter BAUD_RATE = 115_200
) (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // ------------------------------------------------------------
    // Baud rate
    // ------------------------------------------------------------
    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD_RATE;
    localparam integer CTR_W = $clog2(CLKS_PER_BIT + 1);

    // ------------------------------------------------------------
    // Rising edge detect
    // ------------------------------------------------------------
    reg send_d0, send_d1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            {send_d0, send_d1} <= 2'b00;
        else
            {send_d1, send_d0} <= {send_d0, uio_in[0]};
    end

    wire send_rise = send_d0 & ~send_d1;

    // ------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------
    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    reg [1:0] state;
    reg [2:0] bit_idx;
    reg [CTR_W-1:0] clk_cnt;
    reg [7:0] shift;

    reg tx_line;
    reg busy;
    reg done;
    reg [7:0] last_byte;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            bit_idx   <= 3'd0;
            clk_cnt   <= {CTR_W{1'b0}};
            shift     <= 8'hFF;
            tx_line   <= 1'b1;   // idle HIGH
            busy      <= 1'b0;
            done      <= 1'b0;
            last_byte <= 8'h00;
        end else if (ena) begin
            done <= 1'b0;

            case (state)

                S_IDLE: begin
                    tx_line <= 1'b1;
                    busy    <= 1'b0;

                    if (send_rise) begin
                        shift   <= ui_in;
                        clk_cnt <= 0;
                        busy    <= 1'b1;
                        state   <= S_START;
                    end
                end

                S_START: begin
                    tx_line <= 1'b0;

                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        bit_idx <= 0;
                        state   <= S_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_DATA: begin
                    tx_line <= shift[bit_idx];

                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;

                        if (bit_idx == 3'd7)
                            state <= S_STOP;
                        else
                            bit_idx <= bit_idx + 1;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_STOP: begin
                    tx_line <= 1'b1;

                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt   <= 0;
                        last_byte <= shift;
                        done      <= 1'b1;
                        busy      <= 1'b0;
                        state     <= S_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

            endcase
        end
    end

    // ------------------------------------------------------------
    // ✅ GL-SAFE OUTPUT (IMPORTANT FIX)
    // ------------------------------------------------------------
    assign uo_out[0] = rst_n ? tx_line : 1'b1;  // TX idle HIGH
    assign uo_out[1] = rst_n ? busy    : 1'b0;
    assign uo_out[2] = rst_n ? done    : 1'b0;
    assign uo_out[7:3] = 5'b00000;

    assign uio_out = last_byte;
    assign uio_oe  = 8'hFC;

    // Avoid lint warning
    wire _unused_ok = &{uio_in[7:1]};

endmodule
