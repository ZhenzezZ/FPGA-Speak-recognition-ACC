`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/02/25 00:11:22
// Design Name: 
// Module Name: ACC
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module PE_ARRAY(
    clk,
    rst,
    A,
    B,
    IN_VALID,
    STORE,
    OUT_RESP,
    C,
    OUT_VALID
    );
    
    input clk;
    input rst;
    input [7:0] A;
    input [7:0] B;
    input [7:0] IN_VALID;
    input [7:0] STORE;
    input [7:0] OUT_RESP;
    output reg [255:0] C;
    output reg [7:0] OUT_VALID;
    
    
    reg [7:0] a1, a2, a3, a4, a5, a6, a7, a8;
    reg [7:0] b1, b2, b3, b4, b5, b6, b7, b8;
    wire [31:0] c1, c2, c3, c4, c5, c6, c7, c8;
    wire out_valid1, out_valid2, out_valid3, out_valid4, out_valid5, out_valid6, out_valid7, out_valid8;
    
    always @(*) begin
        // Default assignments
        a1 = 0;
        b1 = 0;
        a2 = 0;
        b2 = 0;
        a3 = 0;
        b3 = 0;
        a4 = 0;
        b4 = 0;
        a5 = 0;
        b5 = 0;
        a6 = 0;
        b6 = 0;
        a7 = 0;
        b7 = 0;
        a8 = 0;
        b8 = 0;
    
        case (IN_VALID)
            8'b0000_0001: begin
                a1 = A;
                b1 = B;
            end
            8'b0000_0010: begin
                a2 = A;
                b2 = B;
            end
            8'b0000_0100: begin
                a3 = A;
                b3 = B;
            end
            8'b0000_1000: begin
                a4 = A;
                b4 = B;
            end
            8'b0001_0000: begin
                a5 = A;
                b5 = B;
            end
            8'b0010_0000: begin
                a6 = A;
                b6 = B;
            end
            8'b0100_0000: begin
                a7 = A;
                b7 = B;
            end
            8'b1000_0000: begin
                a8 = A;
                b8 = B;
            end
            default: begin
                // Default case (optional)
                a1 = 0;
                b1 = 0;
                a2 = 0;
                b2 = 0;
                a3 = 0;
                b3 = 0;
                a4 = 0;
                b4 = 0;
                a5 = 0;
                b5 = 0;
                a6 = 0;
                b6 = 0;
                a7 = 0;
                b7 = 0;
                a8 = 0;
                b8 = 0;
            end
        endcase
    end
    
    always @(posedge clk) begin
        if (rst) begin
            C <= 256'b0;  // Set C to zero on reset
        end else begin
            C[31:0]    <= out_valid1 ? c1 : C[31:0];      // 32 bits for c1
            C[63:32]   <= out_valid2 ? c2 : C[63:32];     // 32 bits for c2
            C[95:64]   <= out_valid3 ? c3 : C[95:64];     // 32 bits for c3
            C[127:96]  <= out_valid4 ? c4 : C[127:96];    // 32 bits for c4
            C[159:128] <= out_valid5 ? c5 : C[159:128];   // 32 bits for c5
            C[191:160] <= out_valid6 ? c6 : C[191:160];   // 32 bits for c6
            C[223:192] <= out_valid7 ? c7 : C[223:192];   // 32 bits for c7
            C[255:224] <= out_valid8 ? c8 : C[255:224];   // 32 bits for c8
        end
    end
    
    always @(posedge clk) begin
        if (rst) begin
            OUT_VALID <= 8'b0;
        end else begin
            // Bit 0
            if (out_valid1)
                OUT_VALID[0] <= 1;
            else if (OUT_RESP[0])
                OUT_VALID[0] <= 0;
    
            // Bit 1
            if (out_valid2)
                OUT_VALID[1] <= 1;
            else if (OUT_RESP[1])
                OUT_VALID[1] <= 0;
    
            // Bit 2
            if (out_valid3)
                OUT_VALID[2] <= 1;
            else if (OUT_RESP[2])
                OUT_VALID[2] <= 0;
    
            // Bit 3
            if (out_valid4)
                OUT_VALID[3] <= 1;
            else if (OUT_RESP[3])
                OUT_VALID[3] <= 0;
    
            // Bit 4
            if (out_valid5)
                OUT_VALID[4] <= 1;
            else if (OUT_RESP[4])
                OUT_VALID[4] <= 0;
    
            // Bit 5
            if (out_valid6)
                OUT_VALID[5] <= 1;
            else if (OUT_RESP[5])
                OUT_VALID[5] <= 0;
    
            // Bit 6
            if (out_valid7)
                OUT_VALID[6] <= 1;
            else if (OUT_RESP[6])
                OUT_VALID[6] <= 0;
    
            // Bit 7
            if (out_valid8)
                OUT_VALID[7] <= 1;
            else if (OUT_RESP[7])
                OUT_VALID[7] <= 0;
        end
    end

    
    PE pe1 (
    .clk(clk),
    .rst(rst),
    .A(a1),
    .B(b1),
    .in_valid(IN_VALID[0]),
    .store(STORE[0]),
    .C(c1),
    .out_valid(out_valid1)
    );
    
    PE pe2 (
    .clk(clk),
    .rst(rst),
    .A(a2),
    .B(b2),
    .in_valid(IN_VALID[1]),
    .store(STORE[1]),
    .C(c2),
    .out_valid(out_valid2)
    );

    PE pe3 (
    .clk(clk),
    .rst(rst),
    .A(a3),
    .B(b3),
    .in_valid(IN_VALID[2]),
    .store(STORE[2]),
    .C(c3),
    .out_valid(out_valid3)
    );

    PE pe4 (
    .clk(clk),
    .rst(rst),
    .A(a4),
    .B(b4),
    .in_valid(IN_VALID[3]),
    .store(STORE[3]),
    .C(c4),
    .out_valid(out_valid4)
    );

    PE pe5 (
    .clk(clk),
    .rst(rst),
    .A(a5),
    .B(b5),
    .in_valid(IN_VALID[4]),
    .store(STORE[4]),
    .C(c5),
    .out_valid(out_valid5)
    );

    PE pe6 (
    .clk(clk),
    .rst(rst),
    .A(a6),
    .B(b6),
    .in_valid(IN_VALID[5]),
    .store(STORE[5]),
    .C(c6),
    .out_valid(out_valid6)
    );

    PE pe7 (
    .clk(clk),
    .rst(rst),
    .A(a7),
    .B(b7),
    .in_valid(IN_VALID[6]),
    .store(STORE[6]),
    .C(c7),
    .out_valid(out_valid7)
    );

    PE pe8 (
    .clk(clk),
    .rst(rst),
    .A(a8),
    .B(b8),
    .in_valid(IN_VALID[7]),
    .store(STORE[7]),
    .C(c8),
    .out_valid(out_valid8)
    );
    
endmodule
