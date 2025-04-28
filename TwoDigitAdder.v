module TwoDigitAdder(
    input wire clk,
    input wire rst,
    input wire rx,
    input wire [3:0] switches,   // Switch giriþleri eklendi
    // Dört yön butonu için giriþler
    input wire btn_right,   // Sað buton - Ýlk sayýyý arttýrýr
    input wire btn_left,    // Sol buton - Ýlk sayýyý azaltýr
    input wire btn_up,      // Yukarý buton - Ýkinci sayýyý arttýrýr
    input wire btn_down,    // Aþaðý buton - Ýkinci sayýyý azaltýr
    input wire btn_calc,    // U18'deki hesaplama butonu
    output wire tx,
    output reg [3:0] an,
    output reg [6:0] seg,
    output reg [3:0] led
);

localparam CLK_FREQ = 100_000_000;
localparam BAUD_RATE = 9600;
localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

// Buton debounce sinyalleri
wire btn_right_debounced;
wire btn_left_debounced;
wire btn_up_debounced;
wire btn_down_debounced;
wire btn_calc_debounced;


// Buton debouncerlar
ButtonDebounce #(.DEBOUNCE_LIMIT(20'h3FFFF)) debounce_calc (
    .clk(clk),
    .reset(rst),
    .button_in(btn_calc),
    .button_out(btn_calc_debounced)
);

ButtonDebounce #(.DEBOUNCE_LIMIT(20'h3FFFF)) debounce_right (
    .clk(clk),
    .reset(rst),
    .button_in(btn_right),
    .button_out(btn_right_debounced)
);

ButtonDebounce #(.DEBOUNCE_LIMIT(20'h3FFFF)) debounce_left (
    .clk(clk),
    .reset(rst),
    .button_in(btn_left),
    .button_out(btn_left_debounced)
);

ButtonDebounce #(.DEBOUNCE_LIMIT(20'h3FFFF)) debounce_up (
    .clk(clk),
    .reset(rst),
    .button_in(btn_up),
    .button_out(btn_up_debounced)
);

ButtonDebounce #(.DEBOUNCE_LIMIT(20'h3FFFF)) debounce_down (
    .clk(clk),
    .reset(rst),
    .button_in(btn_down),
    .button_out(btn_down_debounced)
);

// UART TX sinyalleri
wire tx_active;
wire tx_done;
reg tx_dv;
reg [7:0] tx_byte;

uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) uart_transmitter (
    .i_Clock(clk),
    .i_Tx_DV(tx_dv),
    .i_Tx_Byte(tx_byte),
    .o_Tx_Active(tx_active),
    .o_Tx_Serial(tx),
    .o_Tx_Done(tx_done)
);

// UART veri gönderimi için FSM
reg [2:0] tx_state;
reg [15:0] result_buffer;
reg display_uart_done;
reg tx_done_previous; // TX_Done sinyalinin önceki deðerini saklamak için

always @(posedge clk) begin
    if (rst) begin
        tx_state <= 0;
        tx_dv <= 0;
        tx_byte <= 0;
        result_buffer <= 0;
        display_uart_done <= 0;
        tx_done_previous <= 0;
    end else begin
        // TX_Done yükselen kenarýný algýla
        if (tx_done && !tx_done_previous) begin
            tx_dv <= 0; // TX tamamlandýðýnda DV'yi sýfýrla
        end
        tx_done_previous <= tx_done;
        
        // Durum kontrolü ve UART iþlemleri
        if (control_state == DISPLAY_RESULT && !display_uart_done) begin
            case (tx_state)
                0: begin
                    result_buffer <= result;
                    tx_byte <= ((result / 1000) % 10) + 8'd48;
                    if (!tx_dv && !tx_done) begin
                        tx_dv <= 1;
                    end
                    if (tx_done && !tx_done_previous) begin
                        tx_state <= 1;
                    end
                end
                1: begin
                    tx_byte <= ((result / 100) % 10) + 8'd48;
                    if (!tx_dv && !tx_done) begin
                        tx_dv <= 1;
                    end
                    if (tx_done && !tx_done_previous) begin
                        tx_state <= 2;
                    end
                end
                2: begin
                    tx_byte <= ((result / 10) % 10) + 8'd48;
                    if (!tx_dv && !tx_done) begin
                        tx_dv <= 1;
                    end
                    if (tx_done && !tx_done_previous) begin
                        tx_state <= 3;
                    end
                end
                3: begin
                    tx_byte <= (result % 10) + 8'd48;
                    if (!tx_dv && !tx_done) begin
                        tx_dv <= 1;
                    end
                    if (tx_done && !tx_done_previous) begin
                        tx_state <= 4;
                    end
                end
                4: begin
                    tx_byte <= 8'd10; // Yeni satýr karakteri
                    if (!tx_dv && !tx_done) begin
                        tx_dv <= 1;
                    end
                    if (tx_done && !tx_done_previous) begin
                        tx_state <= 5;
                        display_uart_done <= 1; // Ýþlem tamamlandý, bir daha göndermemesi için
                    end
                end
                5: begin
                    tx_dv <= 0;
                    // Bu durumda kalýr ve daha fazla iþlem yapmaz
                end
            endcase
        end else if (control_state != DISPLAY_RESULT) begin
            // DISPLAY_RESULT durumunda deðilse, UART FSM'i sýfýrla
            tx_dv <= 0;
            tx_state <= 0;
        end
    end
end

// UART RX alýcý FSM
localparam IDLE = 2'd0,
           START_BIT = 2'd1,
           DATA_BITS = 2'd2,
           STOP_BIT = 2'd3;

reg [1:0] uart_state;
reg rx_data_valid;
reg [7:0] rx_byte;
reg [$clog2(CLKS_PER_BIT)-1:0] clk_count;
reg [2:0] bit_index;

always @(posedge clk) begin
    if (rst) begin
        uart_state <= IDLE;
        rx_data_valid <= 0;
        rx_byte <= 0;
        clk_count <= 0;
        bit_index <= 0;
    end else begin
        rx_data_valid <= 0;
        case (uart_state)
            IDLE: begin
                clk_count <= 0;
                bit_index <= 0;
                if (rx == 1'b0)
                    uart_state <= START_BIT;
            end
            START_BIT: begin
                if (clk_count == (CLKS_PER_BIT/2)) begin
                    if (rx == 1'b0) begin
                        clk_count <= 0;
                        uart_state <= DATA_BITS;
                    end else
                        uart_state <= IDLE;
                end else
                    clk_count <= clk_count + 1;
            end
            DATA_BITS: begin
                if (clk_count == (CLKS_PER_BIT-1)) begin
                    clk_count <= 0;
                    rx_byte[bit_index] <= rx;
                    if (bit_index == 7) begin
                        bit_index <= 0;
                        uart_state <= STOP_BIT;
                    end else
                        bit_index <= bit_index + 1;
                end else
                    clk_count <= clk_count + 1;
            end
            STOP_BIT: begin
                if (clk_count == (CLKS_PER_BIT-1)) begin
                    clk_count <= 0;
                    rx_data_valid <= 1;
                    uart_state <= IDLE;
                end else
                    clk_count <= clk_count + 1;
            end
        endcase
    end
end

// Ana kontrol FSM
localparam WAIT_NUM1 = 4'd0,
           STORE_NUM1 = 4'd1,
           WAIT_NUM2 = 4'd2,
           STORE_NUM2 = 4'd3,
           WAIT_COMMAND = 4'd4,
           ADDITION = 4'd5,
           SUBTRACTION = 4'd6,
           MULTIPLICATION = 4'd7,
           DIVISION = 4'd8,
           DISPLAY_RESULT = 4'd9,
           WAIT_RESTART = 4'd10,
           SENDING_RESULT = 4'd11; // Yeni durum: Sonucun gönderilmesi için

reg [3:0] control_state;
reg [7:0] num1, num2;
reg [15:0] result;
reg result_negative;
reg division_by_zero;

reg [1:0] operation_type;
localparam OP_ADD = 2'd0,
           OP_SUB = 2'd1,
           OP_MUL = 2'd2,
           OP_DIV = 2'd3;

reg [16:0] refresh_counter;
reg [1:0] display_selector;
reg [3:0] current_digit;
reg dp;

localparam SHOW_NUM1 = 2'd0,
           SHOW_NUM2 = 2'd1,
           SHOW_RESULT = 2'd2,
           SHOW_BOTH = 2'd3;

reg [1:0] display_mode;

initial begin
    uart_state = IDLE;
    rx_data_valid = 0;
    rx_byte = 0;
    clk_count = 0;
    bit_index = 0;
    control_state = WAIT_NUM1;
    num1 = 0; num2 = 0;
    result = 0;
    result_negative = 0;
    division_by_zero = 0;
    operation_type = OP_ADD;
    refresh_counter = 0;
    display_selector = 0;
    current_digit = 0;
    dp = 1;
    display_mode = SHOW_BOTH; // Baþlangýçta her iki sayýyý da göster
    an = 4'b1111;
    seg = 7'b1111111;
    led = 4'b0000;
end

always @(posedge clk) begin
    if (rst) begin
        control_state <= WAIT_NUM1;
        num1 <= 0; num2 <= 0; result <= 0;
        result_negative <= 0; division_by_zero <= 0;
        operation_type <= OP_ADD;
        display_mode <= SHOW_BOTH; // Resetlendiðinde her iki sayýyý da göster
        display_uart_done <= 0;
        led <= 4'b0000;
    end else begin
        // Sayýlar için buton kontrolleri
        // Ýlk sayý için sað ve sol butonlar
        if (btn_right_debounced && num1 < 99) begin
            num1 <= num1 + 1; // Sað buton: Ýlk sayýyý artýr
        end
        if (btn_left_debounced && num1 > 0) begin
            num1 <= num1 - 1; // Sol buton: Ýlk sayýyý azalt
        end
        
        // Ýkinci sayý için yukarý ve aþaðý butonlar
        if (btn_up_debounced && num2 < 99) begin
            num2 <= num2 + 1; // Yukarý buton: Ýkinci sayýyý artýr
        end
        if (btn_down_debounced && num2 > 0) begin
            num2 <= num2 - 1; // Aþaðý buton: Ýkinci sayýyý azalt
        end
        
                if (btn_calc_debounced) begin
            case (switches)
                4'b0001: begin  // SW0 aktif - Toplama
                    operation_type <= OP_ADD;
                    led <= 4'b0001;
                    control_state <= ADDITION;
                end
                4'b0010: begin  // SW1 aktif - Çýkarma
                    operation_type <= OP_SUB;
                    led <= 4'b0010;
                    control_state <= SUBTRACTION;
                end
                4'b0100: begin  // SW2 aktif - Çarpma
                    operation_type <= OP_MUL;
                    led <= 4'b0100;
                    control_state <= MULTIPLICATION;
                end
                4'b1000: begin  // SW3 aktif - Bölme
                    operation_type <= OP_DIV;
                    led <= 4'b1000;
                    control_state <= DIVISION;
                end
                default: begin  // Varsayýlan - Toplama
                    operation_type <= OP_ADD;
                    led <= 4'b0001;
                    control_state <= ADDITION;
                end
            endcase
        end
        
        // UART RX ile de iþlemler yapýlabilir
        if (rx_data_valid) begin
            case (control_state)
                WAIT_NUM1: begin
                    if (rx_byte >= 8'd48 && rx_byte <= 8'd57) begin
                        num1 <= rx_byte - 8'd48;
                        control_state <= STORE_NUM1;
                    end
                end
                STORE_NUM1: begin
                    if (rx_byte >= 8'd48 && rx_byte <= 8'd57) begin
                        num1 <= (num1 * 10) + (rx_byte - 8'd48);
                        control_state <= WAIT_NUM2;
                    end
                end
                WAIT_NUM2: begin
                    if (rx_byte >= 8'd48 && rx_byte <= 8'd57) begin
                        num2 <= rx_byte - 8'd48;
                        control_state <= STORE_NUM2;
                    end
                end
                STORE_NUM2: begin
                    if (rx_byte >= 8'd48 && rx_byte <= 8'd57) begin
                        num2 <= (num2 * 10) + (rx_byte - 8'd48);
                        control_state <= WAIT_COMMAND;
                    end
                end
                WAIT_COMMAND: begin
                
                    // Switch kontrolleri
                    if (switches[0]) begin          // SW0 aktif - Toplama
                        operation_type <= OP_ADD;
                        led <= 4'b0001;
                        control_state <= ADDITION;
                    end
                    else if (switches[1]) begin     // SW1 aktif - Çýkarma
                        operation_type <= OP_SUB;
                        led <= 4'b0010;
                        control_state <= SUBTRACTION;
                    end
                    else if (switches[2]) begin     // SW2 aktif - Çarpma
                        operation_type <= OP_MUL;
                        led <= 4'b0100;
                        control_state <= MULTIPLICATION;
                    end
                    else if (switches[3]) begin     // SW3 aktif - Bölme
                        operation_type <= OP_DIV;
                        led <= 4'b1000;
                        control_state <= DIVISION;
                    end
                    if (rx_byte == 8'd43) begin  // "+" karakteri
                        operation_type <= OP_ADD;
                        control_state <= ADDITION;
                    end else if (rx_byte == 8'd45) begin  // "-" karakteri
                        operation_type <= OP_SUB;
                        control_state <= SUBTRACTION;
                    end else if (rx_byte == 8'd42) begin  // "*" karakteri
                        operation_type <= OP_MUL;
                        control_state <= MULTIPLICATION;
                    end else if (rx_byte == 8'd47) begin  // "/" karakteri
                        operation_type <= OP_DIV;
                        control_state <= DIVISION;
                    end
                    
                end
                DISPLAY_RESULT: begin
                    if (rx_byte == 8'd114 || rx_byte == 8'd82) begin  // "r" veya "R" karakteri
                        // R tuþuna basýldýðýnda yeni bir iþlem baþlýyor
                        control_state <= WAIT_NUM1;
                        display_uart_done <= 0;
                        num1 <= 0; num2 <= 0;
                    end
                    else if (rx_byte == 8'd110 || rx_byte == 8'd78) begin  // "n" veya "N" karakteri
                        control_state <= WAIT_RESTART;
                        display_uart_done <= 0;
                    end
                end
                WAIT_RESTART: begin
                    if (rx_byte >= 8'd48 && rx_byte <= 8'd57) begin
                        num1 <= rx_byte - 8'd48;
                        num2 <= 0;
                        result <= 0;
                        result_negative <= 0;
                        division_by_zero <= 0;
                        led <= 4'b0000;
                        control_state <= STORE_NUM1;
                    end
                end
            endcase
        end
        
        // Ýþlemleri gerçekleþtir (switch'ler ile kontrol edilecek kýsým için hazýrlýk)
        case (control_state)
            ADDITION: begin
                result <= num1 + num2;
                result_negative <= 0;
                division_by_zero <= 0;
                display_uart_done <= 0;
                control_state <= DISPLAY_RESULT;
            end
            SUBTRACTION: begin
                if (num1 >= num2) begin
                    result <= num1 - num2;
                    result_negative <= 0;
                end else begin
                    result <= num2 - num1;
                    result_negative <= 1;
                end
                division_by_zero <= 0;
                display_uart_done <= 0;
                control_state <= DISPLAY_RESULT;
            end
            MULTIPLICATION: begin
                result <= num1 * num2;
                result_negative <= 0;
                division_by_zero <= 0;
                display_uart_done <= 0;
                control_state <= DISPLAY_RESULT;
            end
            DIVISION: begin
                if (num2 == 0) begin
                    result <= 0;
                    division_by_zero <= 1;
                end else begin
                    result <= num1 / num2;
                    division_by_zero <= 0;
                end
                result_negative <= 0;
                display_uart_done <= 0;
                control_state <= DISPLAY_RESULT;
            end
            DISPLAY_RESULT: begin
                display_mode <= SHOW_RESULT;
                case (operation_type)
                    OP_ADD: led <= 4'b0001;
                    OP_SUB: led <= 4'b0010;
                    OP_MUL: led <= 4'b0100;
                    OP_DIV: led <= 4'b1000;
                    default: led <= 4'b0000;
                endcase
            end
        endcase
    end
end

// Seven Segment gösterici iþlemi
always @(posedge clk) begin
    if (rst) begin
        refresh_counter <= 0;
        display_selector <= 0;
        an <= 4'b1111;  // Tüm digitler kapalý
        seg <= 7'b1111111; // Tüm segmentler kapalý
        dp <= 1; // Decimal point kapalý
    end else begin
        // Yenileme sayacýný artýr
        if (refresh_counter == 17'd100000) begin
            refresh_counter <= 0;
            
            // Display seçiciyi döndür
            if (display_selector == 2'd3) begin
                display_selector <= 0;
            end else begin
                display_selector <= display_selector + 1;
            end
        end else begin
            refresh_counter <= refresh_counter + 1;
        end
        
        // Decimal point varsayýlan olarak kapalý
        dp <= 1;
        
        // Görüntülenecek deðere göre aktif digit belirleme
        case (display_mode)
            SHOW_NUM1: begin
                case (display_selector)
                    2'd2: begin 
                        an <= 4'b1011; 
                        current_digit <= num1 % 10;        // Birler
                    end
                    2'd3: begin 
                        an <= 4'b0111; 
                        current_digit <= (num1 / 10) % 10; // Onlar
                    end
                    default: begin 
                        an <= 4'b1111; 
                        current_digit <= 0;                // Diðer dijitler kapalý
                    end
                endcase
            end
            
            SHOW_NUM2: begin
                case (display_selector)
                    2'd2: begin 
                        an <= 4'b1011; 
                        current_digit <= num2 % 10;        // Birler
                    end
                    2'd3: begin 
                        an <= 4'b0111; 
                        current_digit <= (num2 / 10) % 10; // Onlar
                    end
                    default: begin 
                        an <= 4'b1111; 
                        current_digit <= 0;                // Diðer dijitler kapalý
                    end
                endcase
            end
            
            SHOW_BOTH: begin
                case (display_selector)
                    2'd0: begin 
                        an <= 4'b1110; 
                        current_digit <= num2 % 10;        // Num2 Birler
                    end
                    2'd1: begin 
                        an <= 4'b1101; 
                        current_digit <= (num2 / 10) % 10; // Num2 Onlar
                    end
                    2'd2: begin 
                        an <= 4'b1011; 
                        current_digit <= num1 % 10;        // Num1 Birler
                    end
                    2'd3: begin 
                        an <= 4'b0111; 
                        current_digit <= (num1 / 10) % 10; // Num1 Onlar
                    end
                endcase
            end
            
            SHOW_RESULT: begin
                // Sýfýra bölme hatasý gösterimi
                if (division_by_zero) begin
                    case (display_selector)
                        2'd0: begin  // En saðdaki basamak - "r"
                            an <= 4'b1110; 
                            current_digit <= 11;  // "r" harfi için 11 kullanýyoruz
                        end
                        2'd1: begin  // "o"
                            an <= 4'b1101; 
                            current_digit <= 12;  // "o" harfi için 12 kullanýyoruz
                        end
                        2'd2: begin  // "r"
                            an <= 4'b1011; 
                            current_digit <= 11;  // "r" harfi için 11 kullanýyoruz
                        end
                        2'd3: begin  // "E"
                            an <= 4'b0111;
                            current_digit <= 14;  // "E" harfi için 14 kullanýyoruz
                        end
                    endcase
                end
                // Çarpma iþlemi sonuçlarý için özel görüntüleme
                else if (operation_type == OP_MUL) begin
                    case (display_selector)
                        2'd0: begin  // En saðdaki basamak - Birler
                            an <= 4'b1110; 
                            current_digit <= result % 10;
                        end
                        2'd1: begin  // Onlar
                            an <= 4'b1101; 
                            current_digit <= (result / 10) % 10;
                        end
                        2'd2: begin  // Yüzler
                            an <= 4'b1011; 
                            current_digit <= (result / 100) % 10;
                        end
                        2'd3: begin  // Binler (En soldaki basamak)
                            an <= 4'b0111;
                                current_digit <= (result / 1000) % 10;
                        end
                    endcase
                end
                // Bölme iþlemi sonuçlarý için görüntüleme
                else if (operation_type == OP_DIV) begin
                    case (display_selector)
                        2'd0: begin  // En saðdaki basamak - Birler
                            an <= 4'b1110; 
                            current_digit <= result % 10;
                        end
                        2'd1: begin  // Onlar
                            an <= 4'b1101; 
                            current_digit <= (result / 10) % 10;
                           
                        end
                        2'd2: begin  // Yüzler
                            an <= 4'b1011;
                            current_digit <= (result / 100) % 10;
                            
                        end
                        2'd3: begin  // En soldaki basamak
                            an <= 4'b0111;
                            current_digit <= (result / 1000) % 10;
                        end
                    endcase
                end
                // Toplama ve çýkarma iþlemi sonuçlarý için normal görüntüleme
                else begin
                    case (display_selector)
                        2'd0: begin 
                            an <= 4'b1110; 
                            current_digit <= result % 10;         // Birler
                        end
                        2'd1: begin 
                            an <= 4'b1101; 
                            current_digit <= (result / 10) % 10;  // Onlar
                        end
                        2'd2: begin 
                            an <= 4'b1011; 
                            current_digit <= (result / 100) % 10; // Yüzler
                        end
                        2'd3: begin
                            an <= 4'b0111;
                            // Eðer sonuç negatifse, en sol basamakta eksi iþareti göster
                            if (result_negative) begin
                                current_digit <= 10;  // Eksi iþareti için özel durum
                                dp <= 0;              // Decimal point ile eksi iþareti göstereceðiz
                            end else begin
                                // 100'den küçükse dijiti kapat
                                    an <= 4'b0111;
                                    current_digit <= (result / 100) % 10;
                            end
                        end
                    endcase
                end
            end
            
            default: begin
                an <= 4'b1111;
                current_digit <= 0;
            end
        endcase
        
        // Seven segment çýkýþýný güncelle
        case (current_digit)
            4'd0: seg <= 7'b1000000;  // 0: Tüm segmentler açýk (0 aktif)
            4'd1: seg <= 7'b1111001;  // 1
            4'd2: seg <= 7'b0100100;  // 2
            4'd3: seg <= 7'b0110000;  // 3
            4'd4: seg <= 7'b0011001;  // 4
            4'd5: seg <= 7'b0010010;  // 5
            4'd6: seg <= 7'b0000010;  // 6
            4'd7: seg <= 7'b1111000;  // 7
            4'd8: seg <= 7'b0000000;  // 8
            4'd9: seg <= 7'b0010000;  // 9
            4'd10: seg <= 7'b0111111; // Eksi iþareti (orta segment) - görüntüleme için kullanýlacak
            4'd11: seg <= 7'b0101111; // "r" harfi
            4'd12: seg <= 7'b0100011; // "o" harfi
            4'd13: seg <= 7'b1000111; // "L" harfi
            4'd14: seg <= 7'b0000110; // "E" harfi
            default: seg <= 7'b1111111; // Hiçbir segment açýk deðil
        endcase
        
        // Eksi iþareti için decimal point'i kullan
        if (dp == 0) begin
            seg[7] <= 0;  // Decimal point aktif (eksi iþareti için)
        end
    end
end

endmodule