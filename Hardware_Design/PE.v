
module PE(
    clk,
    rst,
    A,
    B,
    in_valid,
    store,
    C,
    out_valid
    );
    
    input wire clk;
    input wire rst;
    
    input wire [7:0] A;
    input wire [7:0] B;
    input wire in_valid;
    input wire store;
    
    output wire [31:0] C;
    output wire out_valid;
    
    wire in_valid_negedge;
    reg in_valid_reg;
    reg [2:0] counter;
    reg [3:0] counter2;
    
    wire [7:0] mult_a, mult_b;
    reg mult_en;
    wire [15:0] mult_out;
    
    wire [31:0] add_a, add_b;
    wire add_en;
    wire [31:0] add_out;
    reg [31:0] add_buff;

    
    mult_gen_0 mult(
    .CLK(clk),
    .A(mult_a),
    .B(mult_b),
    .CE(mult_en),
    .SCLR(rst),
    .P(mult_out)
  );
    
    c_addsub_0 adder (
    .A(add_a),
    .B(add_b),
    .CLK(clk),
    .SCLR(rst),
    .S(add_out)
  );
  
    always@(posedge clk) begin
        if(rst) begin
            in_valid_reg <= 0;
        end else begin
            in_valid_reg <= in_valid;
        end
    end
    
    assign in_valid_negedge = in_valid ? 0 : in_valid_reg;
    
    always@(posedge clk) begin
        if(rst) begin
            counter2 <= 0;
        end else begin
            if (counter == 'd7)
                counter2 <= 0;
            case(counter2)
                4'd0: if (in_valid) counter2 <= 4'd1;
                4'd1: if (in_valid) counter2 <= 4'd2;
                4'd2: if (in_valid) counter2 <= 4'd3;
                4'd3: if (in_valid) counter2 <= 4'd4;
                4'd4: if (in_valid) counter2 <= 4'd5;
                4'd5: if (in_valid) counter2 <= 4'd6;
                4'd6: if (in_valid) counter2 <= 4'd7;
                4'd7: if (in_valid) counter2 <= 4'd8;
                4'd8: if (in_valid) counter2 <= 4'd9;
                4'd9: if (in_valid) counter2 <= 4'd10;
                4'd10: if (in_valid) counter2 <= 4'd11;
                default: counter2 <= 3'd0;
            endcase
        end
    end
    
    always@(posedge clk) begin
        if(rst) begin
            counter <= 0;
        end else begin
            case(counter)
                3'd0: if (in_valid_negedge) counter <= 3'd1;
                3'd1: counter <= 3'd2;
                3'd2: counter <= 3'd3;
                3'd3: counter <= 3'd4;
                3'd4: counter <= 3'd5;
                3'd5: counter <= 3'd6;
                3'd6: counter <= 3'd7;
                3'd7: counter <= 3'd0;
                default: counter <= 3'd0;
            endcase
        end
    end

    always@(negedge clk) begin
        if(rst) begin
            mult_en <= 0;
        end else begin
            if(in_valid) begin
                mult_en <= 1;
            end
            if(counter == 3'd2) begin
                mult_en <= 0;
            end
        end
    end     
    
    assign mult_a = in_valid ? A : 16'b0;
    assign mult_b = in_valid ? B : 16'b0;
    
    
    assign add_b = (counter == 'd7 | counter2 < 'd3) ? 0 : add_out;
    assign add_a = ((counter == 3'd4) || (counter2 == 'd2)) ? add_buff : {{16{mult_out[15]}}, mult_out};
    
    always@(posedge clk) begin
        if(rst) begin
            add_buff <= 32'b0;
        end else begin
            if(counter == 3'd3 | counter == 'd6) begin
                add_buff <= add_out;
            end
            if(counter =='d7 && store == 0) begin
                add_buff <= 0;
            end
        end
    end
    
    assign C = add_out;
    assign out_valid = (counter == 3'd6 && !store) ? 1 : 0;

    
    
    
    
endmodule
