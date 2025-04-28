module button_debounce(
    input wire clk,        // System clock
    input wire reset,      // Reset signal
    input wire button_in,  // Raw button input
    output reg button_out  // Debounced button output
);
// Parameters for debounce counter
parameter DEBOUNCE_LIMIT = 50000; // 0.5ms at 100MHz clock
// Debounce counter and state
reg [19:0] counter;
reg button_ff1, button_ff2; // Flip-flops for synchronization
reg button_state;           // Current debounced state
// Double-flop synchronizer for button input
always @(posedge clk) begin
    if (reset) begin
        button_ff1 <= 0;
        button_ff2 <= 0;
    end else begin
        button_ff1 <= button_in;
        button_ff2 <= button_ff1;
    end
end
// Debounce process
always @(posedge clk) begin
    if (reset) begin
        counter <= 0;
        button_state <= 0;
    end else begin
        // If button state changes, start debounce counter
        if (button_ff2 != button_state && counter < DEBOUNCE_LIMIT) begin
            counter <= counter + 1;
        end else if (counter == DEBOUNCE_LIMIT) begin
            // If counter reaches limit, update button state
            button_state <= button_ff2;
            counter <= 0;
        end else begin
            counter <= 0;
        end
    end
end
// Edge detection for button press (rising edge only)
reg button_state_prev;
always @(posedge clk) begin
    if (reset) begin
        button_state_prev <= 0;
        button_out <= 0;
    end else begin
        // Store previous state
        button_state_prev <= button_state;
        
        // Output pulse on rising edge of debounced button
        button_out <= (button_state && !button_state_prev) ? 1'b1 : 1'b0;
    end
end
endmodule