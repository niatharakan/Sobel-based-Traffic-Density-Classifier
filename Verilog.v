module uart_rx (
    input  wire       clk,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        done
);
    parameter CLKS_PER_BIT = 10416; // 100MHz / 9600 baud

    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0]  state     = IDLE;
    reg [13:0] clk_count = 0;
    reg [2:0]  bit_index = 0;
    reg [7:0]  rx_shift  = 0;
    reg rx_d1 = 1, rx_d2 = 1;

    always @(posedge clk) begin
        rx_d1 <= rx;
        rx_d2 <= rx_d1;
        done  <= 1'b0;

        case (state)
            IDLE: begin
                clk_count <= 0;
                bit_index <= 0;
                if (rx_d2 == 1'b0) state <= START;
            end
            START: begin
                if (clk_count == (CLKS_PER_BIT/2)-1) begin
                    if (rx_d2 == 1'b0) begin
                        clk_count <= 0;
                        state     <= DATA;
                    end else state <= IDLE;
                end else clk_count <= clk_count + 1;
            end
            DATA: begin
                if (clk_count < CLKS_PER_BIT-1)
                    clk_count <= clk_count + 1;
                else begin
                    clk_count           <= 0;
                    rx_shift[bit_index] <= rx_d2;
                    if (bit_index < 7)
                        bit_index <= bit_index + 1;
                    else begin
                        bit_index <= 0;
                        state     <= STOP;
                    end
                end
            end
            STOP: begin
                if (clk_count < CLKS_PER_BIT-1)
                    clk_count <= clk_count + 1;
                else begin
                    done      <= 1'b1;
                    data      <= rx_shift;
                    clk_count <= 0;
                    state     <= IDLE;
                end
            end
            default: state <= IDLE;
        endcase
    end
endmodule


// ============================================================
// Seven segment decoder
// Active LOW segments {DP, G, F, E, D, C, B, A}
// ============================================================
module seg7_decoder (
    input  wire [3:0] digit,
    output reg  [7:0] seg
);
    always @(*) begin
        case (digit)
            4'd0:    seg = 8'b11000000;
            4'd1:    seg = 8'b11111001;
            4'd2:    seg = 8'b10100100;
            4'd3:    seg = 8'b10110000;
            4'd4:    seg = 8'b10011001;
            4'd5:    seg = 8'b10010010;
            4'd6:    seg = 8'b10000010;
            4'd7:    seg = 8'b11111000;
            4'd8:    seg = 8'b10000000;
            4'd9:    seg = 8'b10010000;
            default: seg = 8'b11111111; // blank
        endcase
    end
endmodule


// ============================================================
// Top Module
// ============================================================
// Byte mapping from Python:
// b'0' (48) ? HIGH TRAFFIC   ?  5s red ? led[0]
// b'1' (49) ? MEDIUM TRAFFIC ? 10s red ? led[1]
// b'2' (50) ? LOW TRAFFIC    ? 15s red ? led[2]
// b'3' (51) ? EMERGENCY      ? countdown=0 instantly ? all LEDs ON
// ============================================================
module traffic_uart (
    input  wire       clk,       // 100 MHz - F14
    input  wire       UART_rxd,  // UART RX  - V12
    output reg  [3:0] led,       // 4 LEDs
    output reg  [3:0] D0_AN,     // 7-seg anodes   (active LOW)
    output wire [7:0] D0_SEG     // 7-seg segments (active LOW)
);

    // UART receiver
    wire [7:0] data;
    wire       done;
    uart_rx #(.CLKS_PER_BIT(10416)) receiver (
        .clk(clk), .rx(UART_rxd), .data(data), .done(done)
    );

    //  Startup blink
    reg [26:0] blink_count  = 0;
    reg        startup_done = 0;

    // Timer 
    reg [26:0] sec_counter  = 0;
    reg [4:0]  countdown    = 0;   // 5 bits - holds 0 to 15
    reg        timer_active = 0;

    localparam ONE_SECOND = 27'd99_999_999;

    // Display multiplexing 
    reg [16:0] mux_counter  = 0;
    reg        digit_select = 0;
    reg [3:0]  digit_tens   = 0;
    reg [3:0]  digit_units  = 0;
    reg [3:0]  disp_digit   = 0;

    seg7_decoder dec0 (.digit(disp_digit), .seg(D0_SEG));

    always @(posedge clk) begin

        //  Startup blink - all 4 LEDs on for 1 second 
        if (!startup_done) begin
            led   <= 4'b1111;
            D0_AN <= 4'b0000;   // all segments ON during blink
            if (blink_count == ONE_SECOND) begin
                startup_done <= 1;
                led          <= 4'b0000;
                D0_AN        <= 4'b1111;  // blank after blink
            end else begin
                blink_count <= blink_count + 1;
            end

        end else begin

            // ?? Receive UART byte ??????????????????????????????
            if (done) begin
                case (data)

                    8'd48: begin
                    // b'0' HIGH TRAFFIC - 5s red light
                        led          <= 4'b0001;  // led[0] ON
                        countdown    <= 5'd5;
                        timer_active <= 1;
                        sec_counter  <= 0;
                    end

                    8'd49: begin
                    // b'1' MEDIUM TRAFFIC - 10s red light
                        led          <= 4'b0010;  // led[1] ON
                        countdown    <= 5'd10;
                        timer_active <= 1;
                        sec_counter  <= 0;
                    end

                    8'd50: begin
                    // b'2' LOW TRAFFIC - 15s red light
                        led          <= 4'b0100;  // led[2] ON
                        countdown    <= 5'd15;
                        timer_active <= 1;
                        sec_counter  <= 0;
                    end

                    8'd51: begin
                    // b'3' EMERGENCY - instantly set to 0
                    // Red light OFF immediately
                    // All LEDs ON = green signal for ambulance
                        led          <= 4'b1111;  // all 4 LEDs ON
                        countdown    <= 5'd0;     // instant 0
                        timer_active <= 0;        // stop timer
                        sec_counter  <= 0;
                    end

                    default: begin
                        led          <= 4'b0000;
                        timer_active <= 0;
                        countdown    <= 0;
                    end

                endcase
            end

            // ?? Countdown timer ????????????????????????????????
            if (timer_active) begin
                if (sec_counter == ONE_SECOND) begin
                    sec_counter <= 0;
                    if (countdown > 0) begin
                        countdown <= countdown - 1;
                    end else begin
                        // Countdown reached 0 - turn off LED
                        timer_active <= 0;
                        led          <= 4'b0000;
                    end
                end else begin
                    sec_counter <= sec_counter + 1;
                end
            end

            // ?? BCD split ??????????????????????????????????????
            case (countdown)
                5'd0:  begin digit_tens <= 0; digit_units <= 0;  end
                5'd1:  begin digit_tens <= 0; digit_units <= 1;  end
                5'd2:  begin digit_tens <= 0; digit_units <= 2;  end
                5'd3:  begin digit_tens <= 0; digit_units <= 3;  end
                5'd4:  begin digit_tens <= 0; digit_units <= 4;  end
                5'd5:  begin digit_tens <= 0; digit_units <= 5;  end
                5'd6:  begin digit_tens <= 0; digit_units <= 6;  end
                5'd7:  begin digit_tens <= 0; digit_units <= 7;  end
                5'd8:  begin digit_tens <= 0; digit_units <= 8;  end
                5'd9:  begin digit_tens <= 0; digit_units <= 9;  end
                5'd10: begin digit_tens <= 1; digit_units <= 0;  end
                5'd11: begin digit_tens <= 1; digit_units <= 1;  end
                5'd12: begin digit_tens <= 1; digit_units <= 2;  end
                5'd13: begin digit_tens <= 1; digit_units <= 3;  end
                5'd14: begin digit_tens <= 1; digit_units <= 4;  end
                5'd15: begin digit_tens <= 1; digit_units <= 5;  end
                default: begin digit_tens <= 0; digit_units <= 0; end
            endcase

            // ?? Display multiplexing ???????????????????????????
            if (mux_counter == 17'd66_666) begin
                mux_counter  <= 0;
                digit_select <= ~digit_select;
            end else begin
                mux_counter <= mux_counter + 1;
            end

            // Show digits when timer active OR showing 00
            if (timer_active || countdown == 0) begin
                case (digit_select)
                    1'b0: begin
                        D0_AN      <= 4'b1110;  // rightmost digit
                        disp_digit <= digit_units;
                    end
                    1'b1: begin
                        D0_AN      <= 4'b1101;  // second digit
                        // Hide leading zero for single digit numbers
                        disp_digit <= (digit_tens == 0) ?
                                       4'd15 : digit_tens;
                    end
                endcase
            end else begin
                D0_AN <= 4'b1111;  // blank when inactive
            end

        end
    end
endmodule
