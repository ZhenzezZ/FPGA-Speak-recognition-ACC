`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Digilent Inc.
// Engineer: Thomas Kappenman
// 
// Create Date:    03/03/2015 09:08:33 PM 
// Design Name: 
// Module Name:    SEG7decimal 
// Project Name: Nexys4DDR Keyboard Demo
// Target Devices: Nexys4DDR
// Tool Versions: 
// Description: 7 SEGment display driver
// 
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module seg7decimal(

	input [31:0] x,
    input clk,
    output reg [6:0] SEG,
    output reg [7:0] AN,
    output wire DP 
	 );
	 
	 
wire [2:0] s;	 
reg [3:0] digit;
wire [7:0] aen;
reg [19:0] clkdiv;

assign DP = 1;
assign s = clkdiv[19:17];
assign aen = 8'b11111111; // all turned off initially

// quad 4to1 MUX.


always @(posedge clk)// or posedge clr)
	
	case(s)
	0:digit = x[3:0]; // s is 00 -->0 ;  digit gets assigned 4 bit value assigned to x[3:0]
	1:digit = x[7:4]; // s is 01 -->1 ;  digit gets assigned 4 bit value assigned to x[7:4]
	2:digit = x[11:8]; // s is 10 -->2 ;  digit gets assigned 4 bit value assigned to x[11:8
	3:digit = x[15:12]; // s is 11 -->3 ;  digit gets assigned 4 bit value assigned to x[15:12]
	4:digit = x[19:16]; // s is 00 -->0 ;  digit gets assigned 4 bit value assigned to x[3:0]
    5:digit = x[23:20]; // s is 01 -->1 ;  digit gets assigned 4 bit value assigned to x[7:4]
    6:digit = x[27:24]; // s is 10 -->2 ;  digit gets assigned 4 bit value assigned to x[11:8
    7:digit = x[31:28]; // s is 11 -->3 ;  digit gets assigned 4 bit value assigned to x[15:12]

	default:digit = x[3:0];
	
	endcase
	
	//decoder or truth-table for 7SEG display values
	always @(*)

case(digit)


//////////<---MSB-LSB<---
//////////////gfedcba////////////////////////////////////////////           a
0:SEG = 7'b1000000;////0000												   __					
1:SEG = 7'b1111001;////0001												f/	  /b
2:SEG = 7'b0100100;////0010												  g
//                                                                       __	
3:SEG = 7'b0110000;////0011										 	 e /   /c
4:SEG = 7'b0011001;////0100										       __
5:SEG = 7'b0010010;////0101                                            d  
6:SEG = 7'b0000010;////0110
7:SEG = 7'b1111000;////0111
8:SEG = 7'b0000000;////1000
9:SEG = 7'b0010000;////1001
'hA:SEG = 7'b0001000; 
'hB:SEG = 7'b0000011; 
'hC:SEG = 7'b1000110;
'hD:SEG = 7'b0100001;
'hE:SEG = 7'b0000110;
'hF:SEG = 7'b0001110;

default: SEG = 7'b0000000; // U

endcase


always @(*)begin
AN=8'b11111111;
if(aen[s] == 1)
AN[s] = 0;
end


//clkdiv

always @(posedge clk) begin
clkdiv <= clkdiv+1;
end


endmodule
