module AXI_MST #(
    parameter C_M_AXI_ADDR_WIDTH = 32,
    parameter C_M_AXI_DATA_WIDTH = 32
)(
    // Global signals
    input  wire                            ACLK,
    input  wire                            ARESETN,
    
    // Write Address Channel
    output wire [C_M_AXI_ADDR_WIDTH-1:0]   M_AXI_AWADDR,
    output wire [2:0]                      M_AXI_AWPROT,
    output wire                            M_AXI_AWVALID,
    input  wire                            M_AXI_AWREADY,
    
    // Write Data Channel
    output wire [C_M_AXI_DATA_WIDTH-1:0]   M_AXI_WDATA,
    output wire [(C_M_AXI_DATA_WIDTH/8)-1:0] M_AXI_WSTRB,
    output wire                            M_AXI_WVALID,
    input  wire                            M_AXI_WREADY,
    
    // Write Response Channel
    input  wire [1:0]                      M_AXI_BRESP,
    input  wire                            M_AXI_BVALID,
    output wire                            M_AXI_BREADY,
    
    // Read Address Channel
    output wire [C_M_AXI_ADDR_WIDTH-1:0]   M_AXI_ARADDR,
    output wire [2:0]                      M_AXI_ARPROT,
    output wire                            M_AXI_ARVALID,
    input  wire                            M_AXI_ARREADY,
    
    // Read Data Channel
    input  wire [C_M_AXI_DATA_WIDTH-1:0]   M_AXI_RDATA,
    input  wire [1:0]                      M_AXI_RRESP,
    input  wire                            M_AXI_RVALID,
    output wire                            M_AXI_RREADY,
    
    // User IP interface signals
    input  wire                            ip_start_transaction,
    input  wire                            ip_transaction_type,    // 0: read, 1: write
    input  wire [C_M_AXI_ADDR_WIDTH-1:0]   ip_address,
    input  wire [C_M_AXI_DATA_WIDTH-1:0]   ip_write_data,
    output wire [C_M_AXI_DATA_WIDTH-1:0]   ip_read_data,
    output wire                            ip_read_data_valid,
    output wire                            ip_transaction_done
);

    // FSM states for both read and write channels
    localparam IDLE = 2'b00;
    localparam ADDR = 2'b01;
    localparam DATA = 2'b10;
    localparam RESP = 2'b11;
    
    // Current state registers
    reg [1:0] write_state;
    reg [1:0] read_state;
    
    // Read data register
    reg [C_M_AXI_DATA_WIDTH-1:0] read_data_reg;
    
    // Control flags
    reg transaction_complete_reg;
    reg read_data_valid_reg;
    
    // Transaction type register
    reg transaction_type_reg;
    
    // AXI signals assignments
    reg [C_M_AXI_ADDR_WIDTH-1:0]   axi_awaddr;
    reg [2:0]                      axi_awprot;
    reg                            axi_awvalid;
    
    reg [C_M_AXI_DATA_WIDTH-1:0]   axi_wdata;
    reg [(C_M_AXI_DATA_WIDTH/8)-1:0] axi_wstrb;
    reg                            axi_wvalid;
    
    reg                            axi_bready;
    
    reg [C_M_AXI_ADDR_WIDTH-1:0]   axi_araddr;
    reg [2:0]                      axi_arprot;
    reg                            axi_arvalid;
    
    reg                            axi_rready;
    
    // Connect internal registers to output ports
    assign M_AXI_AWADDR  = axi_awaddr;
    assign M_AXI_AWPROT  = axi_awprot;
    assign M_AXI_AWVALID = axi_awvalid;
    
    assign M_AXI_WDATA   = axi_wdata;
    assign M_AXI_WSTRB   = axi_wstrb;
    assign M_AXI_WVALID  = axi_wvalid;
    
    assign M_AXI_BREADY  = axi_bready;
    
    assign M_AXI_ARADDR  = axi_araddr;
    assign M_AXI_ARPROT  = axi_arprot;
    assign M_AXI_ARVALID = axi_arvalid;
    
    assign M_AXI_RREADY  = axi_rready;
    
    // Connect to user IP interface
    assign ip_read_data = read_data_reg;
    assign ip_read_data_valid = read_data_valid_reg;
    assign ip_transaction_done = transaction_complete_reg;
    
    // Unified transaction management
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            transaction_complete_reg <= 1'b0;
            transaction_type_reg <= 1'b0;
        end else begin
            transaction_complete_reg <= 1'b0;
            // Start a new transaction
            if (ip_start_transaction) begin
                transaction_complete_reg <= 1'b0;
                transaction_type_reg <= ip_transaction_type;
            end
            
            // Complete a write transaction
            if (write_state == RESP && M_AXI_BVALID && axi_bready) begin
                transaction_complete_reg <= 1'b1;
            end
            
            // Complete a read transaction
            if (read_state == DATA && M_AXI_RVALID && axi_rready) begin
                transaction_complete_reg <= 1'b1;
            end
        end
    end
    
    // Write channel state machine
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            write_state <= IDLE;
            axi_awvalid <= 1'b0;
            axi_wvalid <= 1'b0;
            axi_bready <= 1'b0;
            axi_awaddr <= 0;
        end else begin
            case (write_state)
                IDLE: begin
                    if (ip_start_transaction && ip_transaction_type) begin
                        // Setup for write transaction
                        axi_awaddr <= ip_address;
                        axi_awprot <= 3'b000;   // Unprivileged, secure, data access
                        axi_awvalid <= 1'b1;    // Address is valid
                        
                        // Prepare write data
                        axi_wdata <= ip_write_data;
                        axi_wstrb <= {(C_M_AXI_DATA_WIDTH/8){1'b1}}; // All bytes in the word are valid
                        axi_wvalid <= 1'b1;     // Data is valid
                        
                        write_state <= ADDR;
                    end
                end
                
                ADDR: begin
                    // Wait for both address and data to be accepted
                    if (M_AXI_AWREADY && axi_awvalid) begin
                        axi_awvalid <= 1'b0;  // Address has been accepted
                    end
                    
                    if (M_AXI_WREADY && axi_wvalid) begin
                        axi_wvalid <= 1'b0;   // Data has been accepted
                    end
                    
                    // When both address and data have been accepted, move to response phase
                    if ((!axi_awvalid || M_AXI_AWREADY) && (!axi_wvalid || M_AXI_WREADY)) begin
                        axi_bready <= 1'b1;   // Ready to accept response
                        write_state <= RESP;
                    end else begin
                        write_state <= ADDR;
                    end
                end
                
                RESP: begin
                    if (M_AXI_BVALID && axi_bready) begin
                        axi_bready <= 1'b0;
                        write_state <= IDLE;
                    end
                end
                
                default: write_state <= IDLE;
            endcase
        end
    end
    
    // Read channel state machine
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            read_state <= IDLE;
            axi_arvalid <= 1'b0;
            axi_rready <= 1'b0;
            read_data_valid_reg <= 1'b0;
            read_data_reg <= {C_M_AXI_DATA_WIDTH{1'b0}};
        end else begin
            case (read_state)
                IDLE: begin
                    if (ip_start_transaction && !ip_transaction_type) begin
                        // Setup for read transaction
                        axi_araddr <= ip_address;
                        axi_arprot <= 3'b000;   // Unprivileged, secure, data access
                        axi_arvalid <= 1'b1;    // Address is valid
                        read_state <= ADDR;
                        read_data_valid_reg <= 1'b0;
                    end
                end
                
                ADDR: begin
                    if (M_AXI_ARREADY && axi_arvalid) begin
                        axi_arvalid <= 1'b0;  // Address has been accepted
                        axi_rready <= 1'b1;   // Ready to accept data
                        read_state <= DATA;
                    end
                end
                
                DATA: begin
                    if (M_AXI_RVALID && axi_rready) begin
                        read_data_reg <= M_AXI_RDATA;
                        read_data_valid_reg <= 1'b1;
                        axi_rready <= 1'b0;
                        read_state <= IDLE;
                    end
                end
                
                default: read_state <= IDLE;
            endcase
        end
    end

endmodule