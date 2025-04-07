module AXI_SLV #(
    parameter C_S_AXI_ADDR_WIDTH = 32,  // Width of the address bus
    parameter C_S_AXI_DATA_WIDTH = 32  // Width of the data bus
)(
    // Global signals
    input  wire                            S_AXI_ACLK,
    input  wire                            S_AXI_ARESETN,
    
    // Write Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]   S_AXI_AWADDR,
    input  wire [2:0]                      S_AXI_AWPROT,
    input  wire                            S_AXI_AWVALID,
    output wire                            S_AXI_AWREADY,
    
    // Write Data Channel
    input  wire [C_S_AXI_DATA_WIDTH-1:0]   S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  wire                            S_AXI_WVALID,
    output wire                            S_AXI_WREADY,
    
    // Write Response Channel
    output wire [1:0]                      S_AXI_BRESP,
    output wire                            S_AXI_BVALID,
    input  wire                            S_AXI_BREADY,
    
    // Read Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]   S_AXI_ARADDR,
    input  wire [2:0]                      S_AXI_ARPROT,
    input  wire                            S_AXI_ARVALID,
    output wire                            S_AXI_ARREADY,
    
    // Read Data Channel
    output wire [C_S_AXI_DATA_WIDTH-1:0]   S_AXI_RDATA,
    output wire [1:0]                      S_AXI_RRESP,
    output wire                            S_AXI_RVALID,
    input  wire                            S_AXI_RREADY,
    
    // User IP interface signals - to connect to your logic
    output wire                           reg_write_enable,
    output wire [C_S_AXI_ADDR_WIDTH-1:0]  reg_write_addr,
    output wire [C_S_AXI_DATA_WIDTH-1:0]  reg_write_data,
    output wire [(C_S_AXI_DATA_WIDTH/8)-1:0] reg_write_strobe,
    
    output wire                           reg_read_enable,
    output wire [C_S_AXI_ADDR_WIDTH-1:0]  reg_read_addr,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]  reg_read_data
);

    // Registers for handshaking signals
    reg axi_awready;
    reg axi_wready;
    reg axi_bvalid;
    reg axi_arready;
    reg axi_rvalid;
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;
    reg [1:0] axi_bresp;
    reg [1:0] axi_rresp;
    
    // Register to store write address and read address
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
    
    // Local registers for control signals
    reg reg_write_enable_i;
    reg [C_S_AXI_ADDR_WIDTH-1:0] reg_write_addr_i;
    reg [C_S_AXI_DATA_WIDTH-1:0] reg_write_data_i;
    reg [(C_S_AXI_DATA_WIDTH/8)-1:0] reg_write_strobe_i;
    
    reg reg_read_enable_i;
    reg [C_S_AXI_ADDR_WIDTH-1:0] reg_read_addr_i;
        
    // Assign outputs
    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY = axi_wready;
    assign S_AXI_BRESP = axi_bresp;
    assign S_AXI_BVALID = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA = axi_rdata;
    assign S_AXI_RRESP = axi_rresp;
    assign S_AXI_RVALID = axi_rvalid;
    
    // Assign user interface signals
    assign reg_write_enable = reg_write_enable_i;
    assign reg_write_addr = reg_write_addr_i;
    assign reg_write_data = reg_write_data_i;
    assign reg_write_strobe = reg_write_strobe_i;
    
    assign reg_read_enable = reg_read_enable_i;
    assign reg_read_addr = reg_read_addr_i;
    
    //----------------------------------------------
    // Write address channel handshake
    //----------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_awready <= 1'b0;
            axi_awaddr <= 0;
        end else begin
            if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID) begin
                // Address latching - only accepts address when both
                // address and data are valid
                axi_awready <= 1'b1;
                axi_awaddr <= S_AXI_AWADDR;
            end else begin
                axi_awready <= 1'b0;
            end
        end
    end
    
    //----------------------------------------------
    // Write data channel handshake
    //----------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_wready <= 1'b0;
            reg_write_enable_i <= 1'b0;
            reg_write_data_i <= 0;
            reg_write_addr_i <= 0;
            reg_write_strobe_i <= 0;
        end else begin
            if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID) begin
                // Indicates that the slave has accepted the valid write data
                axi_wready <= 1'b1;
                
                // Pass the write signals to the user logic
                reg_write_enable_i <= 1'b1;
                reg_write_data_i <= S_AXI_WDATA;
                reg_write_strobe_i <= S_AXI_WSTRB;
                
                // Address decoding for accessing the correct register
                reg_write_addr_i <= S_AXI_AWADDR;
            end else begin
                axi_wready <= 1'b0;
                reg_write_enable_i <= 1'b0;
            end
        end
    end
    
    //----------------------------------------------
    // Write response channel
    //----------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_bvalid <= 1'b0;
            axi_bresp <= 2'b0;
        end else begin
            if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID) begin
                // Indicates a valid write response is available
                axi_bvalid <= 1'b1;
                axi_bresp <= 2'b00; // 'OKAY' response
            end else begin
                if (S_AXI_BREADY && axi_bvalid) begin
                    // Check if bready is asserted while bvalid is high
                    axi_bvalid <= 1'b0;
                end
            end
        end
    end
    
    //----------------------------------------------
    // Read address channel handshake
    //----------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_arready <= 1'b0;
            axi_araddr <= 32'b0;
            reg_read_enable_i <= 1'b0;
            reg_read_addr_i <= 0;
        end else begin
            if (~axi_arready && S_AXI_ARVALID) begin
                // Indicates that the address is valid
                axi_arready <= 1'b1;
                // Read address latching
                axi_araddr <= S_AXI_ARADDR;
                
                // Enable read operation
                reg_read_enable_i <= 1'b1;
                
                // Address decoding for accessing the correct register
                reg_read_addr_i <= S_AXI_ARADDR;
            end else begin
                axi_arready <= 1'b0;
                reg_read_enable_i <= 1'b0;
            end
        end
    end
    
    //----------------------------------------------
    // Read data channel handshake
    //----------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_rvalid <= 1'b0;
            axi_rresp <= 2'b0;
            axi_rdata <= 32'b0;
        end else begin
            if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
                // Valid read data is available
                axi_rvalid <= 1'b1;
                axi_rresp <= 2'b00; // 'OKAY' response
                // Get data from user logic
                axi_rdata <= reg_read_data;
            end else if (axi_rvalid && S_AXI_RREADY) begin
                // Read data is accepted by the master
                axi_rvalid <= 1'b0;
            end
        end
    end

endmodule