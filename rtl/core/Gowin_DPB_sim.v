// Behavioral model of Gowin_DPB for simulation
// True Dual Port RAM with separate read/write ports

module Gowin_DPB (
    // Port A
    input         clka,
    input         reseta,
    input         cea,
    input         ocea,
    input         wrea,
    input  [13:0] ada,
    input  [15:0] dina,
    output reg [15:0] douta,
    
    // Port B  
    input         clkb,
    input         resetb,
    input         ceb,
    input         oceb,
    input         wreb,
    input  [13:0] adb,
    input  [15:0] dinb,
    output reg [15:0] doutb,
    
    // Block select (unused in this model)
    input  [2:0]  blksela,
    input  [2:0]  blkselb
);

    // Memory array - 4K x 16-bit
    reg [15:0] mem [0:4095];
    
    // Port A read data register
    reg [15:0] douta_reg;
    
    // Port B read data register  
    reg [15:0] doutb_reg;
    
    // Port A logic
    always @(posedge clka) begin
        if (reseta) begin
            douta_reg <= 16'h0000;
        end else if (cea) begin
            if (wrea) begin
                mem[ada[13:2]] <= dina;
            end
            douta_reg <= mem[ada[13:2]];
        end
    end
    
    // Port A output
    always @(posedge clka) begin
        if (reseta) begin
            douta <= 16'h0000;
        end else if (ocea) begin
            douta <= douta_reg;
        end
    end
    
    // Port B logic
    always @(posedge clkb) begin
        if (resetb) begin
            doutb_reg <= 16'h0000;
        end else if (ceb) begin
            if (wreb) begin
                mem[adb[13:2]] <= dinb;
            end
            doutb_reg <= mem[adb[13:2]];
        end
    end
    
    // Port B output
    always @(posedge clkb) begin
        if (resetb) begin
            doutb <= 16'h0000;
        end else if (oceb) begin
            doutb <= doutb_reg;
        end
    end
    
    // Initialize memory to zero
    integer i;
    initial begin
        for (i = 0; i < 4096; i = i + 1) begin
            mem[i] = 16'h0000;
        end
        douta = 16'h0000;
        doutb = 16'h0000;
        douta_reg = 16'h0000;
        doutb_reg = 16'h0000;
    end

endmodule
