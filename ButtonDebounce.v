// ButtonDebounce modülü
module ButtonDebounce(
    input wire clk,        // Saat giriþi
    input wire reset,      // Reset giriþi
    input wire button_in,  // Ham buton giriþi
    output reg button_out  // Debounce edilmiþ çýkýþ (basýldýðýnda tek pulse)
);

// Debounce süresi parametresi (saat frekansýnýza göre ayarlayýn)
// 100MHz saat için yaklaþýk 10ms debounce süresi saðlar
parameter DEBOUNCE_LIMIT = 20'h3FFFF;

// Debounce sayacý ve durum
reg [19:0] counter;
reg button_ff1, button_ff2;    // Senkronizasyon için flip-floplar
reg button_state;              // Mevcut debounce edilmiþ durum
reg button_state_prev;         // Önceki durum için register

// Buton giriþi için çift-flop senkronizasyonu
always @(posedge clk) begin
    if (reset) begin
        button_ff1 <= 0;
        button_ff2 <= 0;
    end else begin
        button_ff1 <= button_in;
        button_ff2 <= button_ff1;
    end
end

// Debounce iþlemi
always @(posedge clk) begin
    if (reset) begin
        counter <= 0;
        button_state <= 0;
    end else begin
        // Buton durumu deðiþtiyse, debounce sayacýný baþlat
        if (button_ff2 != button_state && counter < DEBOUNCE_LIMIT) begin
            counter <= counter + 1;
        end else if (counter == DEBOUNCE_LIMIT) begin
            // Sayaç limite ulaþtýysa, buton durumunu güncelle
            button_state <= button_ff2;
            counter <= 0;
        end else begin
            counter <= 0;
        end
    end
end

// Buton basýlmasý için kenar tespiti (sadece yükselen kenar)
always @(posedge clk) begin
    if (reset) begin
        button_state_prev <= 0;
        button_out <= 0;
    end else begin
        // Önceki durumu kaydet
        button_state_prev <= button_state;
        
        // Yükselen kenar tespiti - sadece 0'dan 1'e geçiþte pulse üret
        if (button_state && !button_state_prev) begin
            button_out <= 1;
        end else begin
            button_out <= 0;
        end
    end
end

endmodule
