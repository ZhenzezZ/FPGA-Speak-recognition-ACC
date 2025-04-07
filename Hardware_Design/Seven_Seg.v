`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 26.03.2025 20:24:43
// Design Name: 
// Module Name: Seven_Seg
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
module SSD (
    // Global signals for AXI
    input wire S_AXI_ACLK,     // AXI clock
    input wire S_AXI_ARESETN,  // AXI reset
    
    // AXI Slave Interface
    input wire [31:0] S_AXI_AWADDR,
    input wire [2:0] S_AXI_AWPROT,
    input wire S_AXI_AWVALID,
    output wire S_AXI_AWREADY,
    
    input wire [31:0] S_AXI_WDATA,
    input wire [3:0] S_AXI_WSTRB,
    input wire S_AXI_WVALID,
    output wire S_AXI_WREADY,
    
    output wire [1:0] S_AXI_BRESP,
    output wire S_AXI_BVALID,
    input wire S_AXI_BREADY,
    
    input wire [31:0] S_AXI_ARADDR,
    input wire [2:0] S_AXI_ARPROT,
    input wire S_AXI_ARVALID,
    output wire S_AXI_ARREADY,
    
    output wire [31:0] S_AXI_RDATA,
    output wire [1:0] S_AXI_RRESP,
    output wire S_AXI_RVALID,
    input wire S_AXI_RREADY,
    
    // User signals (interfacing AXI with the 7-segment display)
    input wire clk,             //100MHz
    output wire [6:0] SEG,    // 7-segment display segments
    output wire [7:0] AN,     // 7-segment display anodes
    output wire DP            // Decimal point for 7-segment display
);

    // Internal signals for the 7-segment display module
    wire [31:0] reg_read_data;  // Data read from AXI slave for 7-segment display
    wire reg_write_enable;      // Signal indicating that a write has occurred
    wire [31:0] reg_write_addr; // Address for the write operation
    wire [31:0] reg_write_data; // Data being written
    wire [3:0] reg_write_strobe; // Write strobe signals
    
    wire reg_read_enable;       // Signal indicating that a read has occurred
    wire [31:0] reg_read_addr;  // Address for the read operation

    // Instantiate the AXI_SLV module
    AXI_SLV #(
        .C_S_AXI_ADDR_WIDTH(32),
        .C_S_AXI_DATA_WIDTH(32)
    ) axi_slave_inst (
        .S_AXI_ACLK(S_AXI_ACLK),
        .S_AXI_ARESETN(S_AXI_ARESETN),
        
        .S_AXI_AWADDR(S_AXI_AWADDR),
        .S_AXI_AWPROT(S_AXI_AWPROT),
        .S_AXI_AWVALID(S_AXI_AWVALID),
        .S_AXI_AWREADY(S_AXI_AWREADY),
        
        .S_AXI_WDATA(S_AXI_WDATA),
        .S_AXI_WSTRB(S_AXI_WSTRB),
        .S_AXI_WVALID(S_AXI_WVALID),
        .S_AXI_WREADY(S_AXI_WREADY),
        
        .S_AXI_BRESP(S_AXI_BRESP),
        .S_AXI_BVALID(S_AXI_BVALID),
        .S_AXI_BREADY(S_AXI_BREADY),
        
        .S_AXI_ARADDR(S_AXI_ARADDR),
        .S_AXI_ARPROT(S_AXI_ARPROT),
        .S_AXI_ARVALID(S_AXI_ARVALID),
        .S_AXI_ARREADY(S_AXI_ARREADY),
        
        .S_AXI_RDATA(S_AXI_RDATA),
        .S_AXI_RRESP(S_AXI_RRESP),
        .S_AXI_RVALID(S_AXI_RVALID),
        .S_AXI_RREADY(S_AXI_RREADY),
        
        // Connecting the user interface to the AXI slave
        .reg_write_enable(reg_write_enable),
        .reg_write_addr(reg_write_addr),
        .reg_write_data(reg_write_data),
        .reg_write_strobe(reg_write_strobe),
        
        .reg_read_enable(reg_read_enable),
        .reg_read_addr(reg_read_addr),
        .reg_read_data(reg_read_data)
    );

    // Instantiate the seg7decimal module
    seg7decimal seg7_inst (
        .x(reg_write_data),
        .clk(clk),           
        .SEG(SEG),                  // Connect SEG to output 7-segment display segments
        .AN(AN),                    // Connect AN to output 7-segment display anodes
        .DP(DP)                     // Connect DP to output decimal point control
    );


endmodule
