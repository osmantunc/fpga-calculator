module uart_tx
#(parameter CLKS_PER_BIT = 10416)  // 100 MHz / 9600 = 10416
(
    input wire i_Clock,
    input wire i_Tx_DV,
    input wire [7:0] i_Tx_Byte,
    output reg o_Tx_Active,
    output reg o_Tx_Serial,
    output reg o_Tx_Done
);

    localparam IDLE         = 3'b000;
    localparam TX_START_BIT = 3'b001;
    localparam TX_DATA_BITS = 3'b010;
    localparam TX_STOP_BIT  = 3'b011;
    localparam CLEANUP      = 3'b100;

    reg [2:0] r_SM_Main = IDLE;
    reg [15:0] r_Clock_Count = 0;
    reg [2:0] r_Bit_Index = 0;
    reg [7:0] r_Tx_Data = 0;

    always @(posedge i_Clock) begin
        case (r_SM_Main)
            IDLE: begin
                o_Tx_Done <= 0;
                o_Tx_Serial <= 1'b1;
                r_Clock_Count <= 0;
                r_Bit_Index <= 0;

                if (i_Tx_DV) begin
                    r_Tx_Data <= i_Tx_Byte;
                    o_Tx_Active <= 1'b1;
                    r_SM_Main <= TX_START_BIT;
                end else begin
                    o_Tx_Active <= 1'b0;
                end
            end

            TX_START_BIT: begin
                o_Tx_Serial <= 1'b0;

                if (r_Clock_Count < CLKS_PER_BIT - 1) begin
                    r_Clock_Count <= r_Clock_Count + 1;
                end else begin
                    r_Clock_Count <= 0;
                    r_SM_Main <= TX_DATA_BITS;
                end
            end

            TX_DATA_BITS: begin
                o_Tx_Serial <= r_Tx_Data[r_Bit_Index];

                if (r_Clock_Count < CLKS_PER_BIT - 1) begin
                    r_Clock_Count <= r_Clock_Count + 1;
                end else begin
                    r_Clock_Count <= 0;

                    if (r_Bit_Index < 7) begin
                        r_Bit_Index <= r_Bit_Index + 1;
                    end else begin
                        r_Bit_Index <= 0;
                        r_SM_Main <= TX_STOP_BIT;
                    end
                end
            end

            TX_STOP_BIT: begin
                o_Tx_Serial <= 1'b1;

                if (r_Clock_Count < CLKS_PER_BIT - 1) begin
                    r_Clock_Count <= r_Clock_Count + 1;
                end else begin
                    r_Clock_Count <= 0;
                    r_SM_Main <= CLEANUP;
                    o_Tx_Done <= 1'b1;
                end
            end

            CLEANUP: begin
                o_Tx_Done <= 1'b0;
                r_SM_Main <= IDLE;
                o_Tx_Active <= 1'b0;
            end

            default: r_SM_Main <= IDLE;
        endcase
    end

endmodule