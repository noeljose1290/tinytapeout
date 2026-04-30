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
    end else begin
        done <= 1'b0;

        case (state)

            S_IDLE: begin
                tx_line <= 1'b1;
                busy    <= 1'b0;

                if (send_rise && ena) begin   // ✅ FIX HERE
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
