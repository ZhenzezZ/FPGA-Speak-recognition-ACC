`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/03/04 00:45:35
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


module ACC #(
    //Slave Interface Widths
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 32,
    //Master Interface Widths
    parameter C_M_AXI_DATA_WIDTH = 32,
    parameter C_M_AXI_ADDR_WIDTH = 32
)(
    // Global signals
    input  wire                           ACLK,
    input  wire                           ARESETN,
    
    // AXI_SLV interface    
    // AXI Write Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]  S_AXI_AWADDR,     // Write address
    input  wire [2:0]                     S_AXI_AWPROT,     // Write protection type
    input  wire                           S_AXI_AWVALID,    // Write address valid
    output wire                           S_AXI_AWREADY,    // Write address ready
    
    // AXI Write Data Channel
    input  wire [C_S_AXI_DATA_WIDTH-1:0]  S_AXI_WDATA,      // Write data
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,    // Write strobes (byte enables)
    input  wire                           S_AXI_WVALID,     // Write data valid
    output wire                           S_AXI_WREADY,     // Write data ready
    
    // AXI Write Response Channel
    output wire [1:0]                     S_AXI_BRESP,      // Write response
    output wire                           S_AXI_BVALID,     // Write response valid
    input  wire                           S_AXI_BREADY,     // Write response ready
    
    // AXI Read Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]  S_AXI_ARADDR,     // Read address
    input  wire [2:0]                     S_AXI_ARPROT,     // Read protection type
    input  wire                           S_AXI_ARVALID,    // Read address valid
    output wire                           S_AXI_ARREADY,    // Read address ready
    
    // AXI Read Data Channel
    output wire [C_S_AXI_DATA_WIDTH-1:0]  S_AXI_RDATA,      // Read data
    output wire [1:0]                     S_AXI_RRESP,      // Read response
    output wire                           S_AXI_RVALID,     // Read data valid
    input  wire                           S_AXI_RREADY,     // Read data ready
    

    // AXI_MST interface
    // Write Address Channel
    output wire [C_M_AXI_ADDR_WIDTH-1:0]  M_AXI_AWADDR,
    output wire [2:0]                     M_AXI_AWPROT,
    output wire                           M_AXI_AWVALID,
    input  wire                           M_AXI_AWREADY,
    
    // Write Data Channel
    output wire [C_M_AXI_DATA_WIDTH-1:0]  M_AXI_WDATA,
    output wire [(C_M_AXI_DATA_WIDTH/8)-1:0] M_AXI_WSTRB,
    output wire                           M_AXI_WVALID,
    input  wire                           M_AXI_WREADY,
    
    // Write Response Channel
    input  wire [1:0]                     M_AXI_BRESP,
    input  wire                           M_AXI_BVALID,
    output wire                           M_AXI_BREADY,
    
    // Read Address Channel
    output wire [C_M_AXI_ADDR_WIDTH-1:0]  M_AXI_ARADDR,
    output wire [2:0]                     M_AXI_ARPROT,
    output wire                           M_AXI_ARVALID,
    input  wire                           M_AXI_ARREADY,
    
    // Read Data Channel
    input  wire [C_M_AXI_DATA_WIDTH-1:0]  M_AXI_RDATA,
    input  wire [1:0]                     M_AXI_RRESP,
    input  wire                           M_AXI_RVALID,
    output wire                           M_AXI_RREADY
);


    wire rst = !ARESETN;
    //singals from axi slave interface
    wire                            reg_write_enable; // Write enable signal
    wire [C_S_AXI_ADDR_WIDTH-1:0]   reg_write_addr;   // Write address
    wire [C_S_AXI_DATA_WIDTH-1:0]   reg_write_data;   // Write data
    wire [3:0]                      reg_write_strobe; // Write strobes (byte enables)
   
    wire                            reg_read_enable;  // Read enable signal
    wire [C_S_AXI_ADDR_WIDTH-1:0]   reg_read_addr;    // Read address
    wire [C_S_AXI_DATA_WIDTH-1:0]   reg_read_data;     // Read data

    //singals from axi master interface
    reg                            ip_start_transaction;
    wire                            ip_transaction_type;  // 0: read, 1: write
    reg [C_M_AXI_ADDR_WIDTH-1:0]   ip_address;
    reg [C_M_AXI_DATA_WIDTH-1:0]   ip_write_data;
    wire [C_M_AXI_DATA_WIDTH-1:0]   ip_read_data;
    wire                            ip_read_data_valid;
    wire                            ip_transaction_done;

    reg [7:0] w_buffer1 [11:0];
    reg [7:0] a_buffer1 [11:0];
    reg [7:0] w_buffer2 [11:0];
    reg [7:0] a_buffer2 [11:0];
    
    reg [3:0] buffer_counter;
    reg pp_counter;     //0 for buffer1; 0 for buffer2
    
    wire [7:0] a,b;
    wire [255:0] c;
    wire [7:0] in_valid;
    reg [7:0] store;
    
    reg [7:0] out_flag;
    wire [7:0] out_valid;
    reg [7:0] out_resp;

//////////////////////////////////////////////////////////from AXI slave signals
    integer i;
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            for (i = 0; i < 12; i = i + 1) begin
                w_buffer1[i] = 0;  
            end
        end else begin
            if (reg_write_enable) begin
                case(reg_write_addr[5:2])
                    4'b0000: begin 
                            {w_buffer1[3], w_buffer1[2], w_buffer1[1], w_buffer1[0]} <= reg_write_data;
                        end
                    4'b0001: begin
                            {w_buffer1[7], w_buffer1[6], w_buffer1[5], w_buffer1[4]} <= reg_write_data;
                        end
                    4'b0010: begin
                            {w_buffer1[11], w_buffer1[10], w_buffer1[9], w_buffer1[8]} <= reg_write_data;
                        end
                endcase
            end
        end
    end
    
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            for (i = 0; i < 12; i = i + 1) begin
                a_buffer1[i] = 0;  
            end
        end else begin
            if (reg_write_enable) begin
                case(reg_write_addr[5:2])
                    'd3: begin 
                            {a_buffer1[3], a_buffer1[2], a_buffer1[1], a_buffer1[0]} <= reg_write_data;
                        end
                    'd4: begin
                            {a_buffer1[7], a_buffer1[6], a_buffer1[5], a_buffer1[4]} <= reg_write_data;
                        end
                    'd5: begin
                            {a_buffer1[11], a_buffer1[10], a_buffer1[9], a_buffer1[8]} <= reg_write_data;
                        end
                endcase
                
                if (buffer_counter != 0 && !pp_counter) begin
                    a_buffer1[11][0] <= 0;
                end 
            end
        end
    end
    
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            for (i = 0; i < 12; i = i + 1) begin
                w_buffer2[i] = 0;  
            end
        end else begin
            if (reg_write_enable) begin
                case(reg_write_addr[5:2])
                    'd6: begin 
                            {w_buffer2[3], w_buffer2[2], w_buffer2[1], w_buffer2[0]} <= reg_write_data;
                        end
                    'd7: begin
                            {w_buffer2[7], w_buffer2[6], w_buffer2[5], w_buffer2[4]} <= reg_write_data;
                        end
                    'd8: begin
                            {w_buffer2[11], w_buffer2[10], w_buffer2[9], w_buffer2[8]} <= reg_write_data;
                        end
                endcase
            end
        end
    end
    
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            for (i = 0; i < 12; i = i + 1) begin
                a_buffer2[i] = 0;  
            end
        end else begin
            if (reg_write_enable) begin
                case(reg_write_addr[5:2])
                    'd9: begin 
                            {a_buffer2[3], a_buffer2[2], a_buffer2[1], a_buffer2[0]} <= reg_write_data;
                        end
                    'd10: begin
                            {a_buffer2[7], a_buffer2[6], a_buffer2[5], a_buffer2[4]} <= reg_write_data;
                        end
                    'd11: begin
                            {a_buffer2[11], a_buffer2[10], a_buffer2[9], a_buffer2[8]} <= reg_write_data;
                        end
                endcase
                
                if (buffer_counter != 0 && pp_counter) begin
                    a_buffer2[11][0] <= 0;
                end 
            end
        end
    end
    
    always @(posedge ACLK or negedge ARESETN) begin
        if(!ARESETN) begin
            pp_counter <= 'd0;
        end else begin
            if (buffer_counter == 'd9) begin
                pp_counter <= !pp_counter;
            end
        end
    end 
            
            
            
    always @(posedge ACLK or negedge ARESETN) begin
        if(!ARESETN) begin
            buffer_counter <= 'd0;
        end else begin
            case (buffer_counter)
                'd0: if ((a_buffer1[11][0] == 'd1 && !pp_counter) || (a_buffer2[11][0] == 'd1 && pp_counter)) buffer_counter <= 'd1;
                'd1: buffer_counter <= 'd2;
                'd2: buffer_counter <= 'd3;
                'd3: buffer_counter <= 'd4;
                'd4: buffer_counter <= 'd5;
                'd5: buffer_counter <= 'd6;
                'd6: buffer_counter <= 'd7;
                'd7: buffer_counter <= 'd8;
                'd8: buffer_counter <= 'd9;
                'd9: buffer_counter <= 'd0;
                default: buffer_counter <= 'd0;
            endcase
        end
    end
    
    assign a = pp_counter ? a_buffer2[buffer_counter-1] : a_buffer1[buffer_counter-1];
    assign b = pp_counter ? w_buffer2[buffer_counter-1] : w_buffer1[buffer_counter-1];
    assign in_valid = (buffer_counter != 0) ? (pp_counter ? a_buffer2[10] : a_buffer1[10]) : 0;
    
    always @(posedge ACLK or negedge ARESETN) begin
        if(!ARESETN) begin
            store <= 0;
        end else begin
            if (!pp_counter) begin
                case(a_buffer1[10])
                    'b0000_0001: store[0] <= a_buffer1[11][1];
                    'b0000_0010: store[1] <= a_buffer1[11][1];
                    'b0000_0100: store[2] <= a_buffer1[11][1];
                    'b0000_1000: store[3] <= a_buffer1[11][1];
                    'b0001_0000: store[4] <= a_buffer1[11][1];
                    'b0010_0000: store[5] <= a_buffer1[11][1];
                    'b0100_0000: store[6] <= a_buffer1[11][1];
                    'b1000_0000: store[7] <= a_buffer1[11][1];
                endcase
            end else begin
                case(a_buffer2[10])
                    'b0000_0001: store[0] <= a_buffer2[11][1];
                    'b0000_0010: store[1] <= a_buffer2[11][1];
                    'b0000_0100: store[2] <= a_buffer2[11][1];
                    'b0000_1000: store[3] <= a_buffer2[11][1];
                    'b0001_0000: store[4] <= a_buffer2[11][1];
                    'b0010_0000: store[5] <= a_buffer2[11][1];
                    'b0100_0000: store[6] <= a_buffer2[11][1];
                    'b1000_0000: store[7] <= a_buffer2[11][1];
                endcase
            end
        end
    end
                
///////////////////////////////////////////////////////////////// to AXI master signals       
    always @(posedge ACLK or negedge ARESETN) begin
        if(!ARESETN) begin
            ip_address <= 'h87E0_0000;
        end else begin
            if (ip_start_transaction) begin
                ip_address <= ip_address + 4;
            end
        end
    end
    
    always @(posedge ACLK or negedge ARESETN) begin
        if(!ARESETN) begin
            ip_start_transaction <= 0;
        end else begin
            if ((out_flag == 0) && (out_valid != 0)) begin
                ip_start_transaction <= 1;
            end else begin
                ip_start_transaction <= 0;
            end
        end
    end
    
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            out_flag <= 8'b0;
        end else begin
            if (out_flag == 8'b0) begin
                if (out_valid[0]) begin
                    out_flag <= 8'b00000001;
                end else if (out_valid[1]) begin
                    out_flag <= 8'b00000010;
                end else if (out_valid[2]) begin
                    out_flag <= 8'b00000100;
                end else if (out_valid[3]) begin
                    out_flag <= 8'b00001000;
                end else if (out_valid[4]) begin
                    out_flag <= 8'b00010000;
                end else if (out_valid[5]) begin
                    out_flag <= 8'b00100000;
                end else if (out_valid[6]) begin
                    out_flag <= 8'b01000000;
                end else if (out_valid[7]) begin
                    out_flag <= 8'b10000000;
                end else begin
                    out_flag <= 8'b0;
                end
            end else begin
                case (out_flag)
                    8'b00000001: out_flag[0] <= out_valid[0];
                    8'b00000010: out_flag[1] <= out_valid[1];
                    8'b00000100: out_flag[2] <= out_valid[2];
                    8'b00001000: out_flag[3] <= out_valid[3];
                    8'b00010000: out_flag[4] <= out_valid[4];
                    8'b00100000: out_flag[5] <= out_valid[5];
                    8'b01000000: out_flag[6] <= out_valid[6];
                    8'b10000000: out_flag[7] <= out_valid[7];
                    default: out_flag <= 8'b0;
                endcase
            end
        end
    end
    
    assign ip_transaction_type = 1;
    
    always @(*) begin
        // Default assignments
        ip_write_data = 32'b0;  // Ensure ip_write_data is 32 bits wide
        out_resp = 8'b0;
        
        if (out_valid[0]) begin
            ip_write_data = c[31:0];    // Access the first 32 bits of c (c1)
            out_resp[0] = ip_transaction_done;
        end
        else if (out_valid[1]) begin
            ip_write_data = c[63:32];   // Access the next 32 bits of c (c2)
            out_resp[1] = ip_transaction_done;
        end
        else if (out_valid[2]) begin
            ip_write_data = c[95:64];   // Access the next 32 bits of c (c3)
            out_resp[2] = ip_transaction_done;
        end
        else if (out_valid[3]) begin
            ip_write_data = c[127:96];  // Access the next 32 bits of c (c4)
            out_resp[3] = ip_transaction_done;
        end
        else if (out_valid[4]) begin
            ip_write_data = c[159:128]; // Access the next 32 bits of c (c5)
            out_resp[4] = ip_transaction_done;
        end
        else if (out_valid[5]) begin
            ip_write_data = c[191:160]; // Access the next 32 bits of c (c6)
            out_resp[5] = ip_transaction_done;
        end
        else if (out_valid[6]) begin
            ip_write_data = c[223:192]; // Access the next 32 bits of c (c7)
            out_resp[6] = ip_transaction_done;
        end
        else if (out_valid[7]) begin
            ip_write_data = c[255:224]; // Access the next 32 bits of c (c8)
            out_resp[7] = ip_transaction_done;
        end
    end

         
////////////////////////////////////////////////////
    // Instantiate the AXI_MST module
    AXI_MST  #(
        .C_M_AXI_ADDR_WIDTH(32),
        .C_M_AXI_DATA_WIDTH(32)
    ) axi_master_inst (
        // Global signals
        .ACLK(ACLK),
        .ARESETN(ARESETN),
        
        // Write Address Channel
        .M_AXI_AWADDR(M_AXI_AWADDR),
        .M_AXI_AWPROT(M_AXI_AWPROT),
        .M_AXI_AWVALID(M_AXI_AWVALID),
        .M_AXI_AWREADY(M_AXI_AWREADY),
        
        // Write Data Channel
        .M_AXI_WDATA(M_AXI_WDATA),
        .M_AXI_WSTRB(M_AXI_WSTRB),
        .M_AXI_WVALID(M_AXI_WVALID),
        .M_AXI_WREADY(M_AXI_WREADY),
        
        // Write Response Channel
        .M_AXI_BRESP(M_AXI_BRESP),
        .M_AXI_BVALID(M_AXI_BVALID),
        .M_AXI_BREADY(M_AXI_BREADY),
        
        // Read Address Channel
        .M_AXI_ARADDR(M_AXI_ARADDR),
        .M_AXI_ARPROT(M_AXI_ARPROT),
        .M_AXI_ARVALID(M_AXI_ARVALID),
        .M_AXI_ARREADY(M_AXI_ARREADY),
        
        // Read Data Channel
        .M_AXI_RDATA(M_AXI_RDATA),
        .M_AXI_RRESP(M_AXI_RRESP),
        .M_AXI_RVALID(M_AXI_RVALID),
        .M_AXI_RREADY(M_AXI_RREADY),
        
        // User IP interface signals
        .ip_start_transaction(ip_start_transaction),
        .ip_transaction_type(ip_transaction_type),
        .ip_address(ip_address),
        .ip_write_data(ip_write_data),
        .ip_read_data(ip_read_data),
        .ip_read_data_valid(ip_read_data_valid),
        .ip_transaction_done(ip_transaction_done)
    );
    
    
    
    // Instantiate the AXI_SLV module
    AXI_SLV #(
        .C_S_AXI_ADDR_WIDTH(32),  // Set address width to 32 bits
        .C_S_AXI_DATA_WIDTH(32)   // Set data width to 32 bits
    ) axi_slave_inst (
        // Global signals
        .S_AXI_ACLK(ACLK),
        .S_AXI_ARESETN(ARESETN),
        
        // Write Address Channel
        .S_AXI_AWADDR(S_AXI_AWADDR),
        .S_AXI_AWPROT(S_AXI_AWPROT),
        .S_AXI_AWVALID(S_AXI_AWVALID),
        .S_AXI_AWREADY(S_AXI_AWREADY),
        
        // Write Data Channel
        .S_AXI_WDATA(S_AXI_WDATA),
        .S_AXI_WSTRB(S_AXI_WSTRB),
        .S_AXI_WVALID(S_AXI_WVALID),
        .S_AXI_WREADY(S_AXI_WREADY),
        
        // Write Response Channel
        .S_AXI_BRESP(S_AXI_BRESP),
        .S_AXI_BVALID(S_AXI_BVALID),
        .S_AXI_BREADY(S_AXI_BREADY),
        
        // Read Address Channel
        .S_AXI_ARADDR(S_AXI_ARADDR),
        .S_AXI_ARPROT(S_AXI_ARPROT),
        .S_AXI_ARVALID(S_AXI_ARVALID),
        .S_AXI_ARREADY(S_AXI_ARREADY),
        
        // Read Data Channel
        .S_AXI_RDATA(S_AXI_RDATA),
        .S_AXI_RRESP(S_AXI_RRESP),
        .S_AXI_RVALID(S_AXI_RVALID),
        .S_AXI_RREADY(S_AXI_RREADY),
        
        // User IP interface signals
        .reg_write_enable(reg_write_enable),
        .reg_write_addr(reg_write_addr),
        .reg_write_data(reg_write_data),
        .reg_write_strobe(reg_write_strobe),
        
        .reg_read_enable(reg_read_enable),
        .reg_read_addr(reg_read_addr),
        .reg_read_data(reg_read_data)
    );


    PE_ARRAY pe_array_inst (
        .clk(ACLK),
        .rst(rst),
        .A(a),
        .B(b),
        .IN_VALID(in_valid),
        .STORE(store),
        .C(c),
        .OUT_VALID(out_valid),
        .OUT_RESP(out_resp)
    );
endmodule
