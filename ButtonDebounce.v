// ButtonDebounce mod�l�
module ButtonDebounce(
    input wire clk,        // Saat giri�i
    input wire reset,      // Reset giri�i
    input wire button_in,  // Ham buton giri�i
    output reg button_out  // Debounce edilmi� ��k�� (bas�ld���nda tek pulse)
);

// Debounce s�resi parametresi (saat frekans�n�za g�re ayarlay�n)
// 100MHz saat i�in yakla��k 10ms debounce s�resi sa�lar
parameter DEBOUNCE_LIMIT = 20'h3FFFF;

// Debounce sayac� ve durum
reg [19:0] counter;
reg button_ff1, button_ff2;    // Senkronizasyon i�in flip-floplar
reg button_state;              // Mevcut debounce edilmi� durum
reg button_state_prev;         // �nceki durum i�in register

// Buton giri�i i�in �ift-flop senkronizasyonu
always @(posedge clk) begin
    if (reset) begin
        button_ff1 <= 0;
        button_ff2 <= 0;
    end else begin
        button_ff1 <= button_in;
        button_ff2 <= button_ff1;
    end
end

// Debounce i�lemi
always @(posedge clk) begin
    if (reset) begin
        counter <= 0;
        button_state <= 0;
    end else begin
        // Buton durumu de�i�tiyse, debounce sayac�n� ba�lat
        if (button_ff2 != button_state && counter < DEBOUNCE_LIMIT) begin
            counter <= counter + 1;
        end else if (counter == DEBOUNCE_LIMIT) begin
            // Saya� limite ula�t�ysa, buton durumunu g�ncelle
            button_state <= button_ff2;
            counter <= 0;
        end else begin
            counter <= 0;
        end
    end
end

// Buton bas�lmas� i�in kenar tespiti (sadece y�kselen kenar)
always @(posedge clk) begin
    if (reset) begin
        button_state_prev <= 0;
        button_out <= 0;
    end else begin
        // �nceki durumu kaydet
        button_state_prev <= button_state;
        
        // Y�kselen kenar tespiti - sadece 0'dan 1'e ge�i�te pulse �ret
        if (button_state && !button_state_prev) begin
            button_out <= 1;
        end else begin
            button_out <= 0;
        end
    end
end

endmodule
