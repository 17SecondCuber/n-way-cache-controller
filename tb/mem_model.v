module mem_model #(
    parameter ADDR_W     = 16,
    parameter LINE_WORDS = 4,
    parameter LATENCY    = 3,
    parameter OFFSET_W   = $clog2(LINE_WORDS),
    parameter LINEA_W    = ADDR_W - OFFSET_W 
) 
(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     mem_req,
    input  wire                     mem_we,
    input  wire [LINEA_W-1:0]       mem_addr,
    input  wire [LINE_WORDS*32-1:0] mem_wdata,
    output reg  [LINE_WORDS*32-1:0] mem_rdata,
    output reg                      mem_resp
);
    //make the memory - number of bits per line by number of lines
    reg [LINE_WORDS*32-1:0] mem [0:(1<<LINEA_W)-1];

    //counts cycles since request started
    reg [7:0] count_cycles;

    //make every memory slot hold its own address as a placeholder
    integer i, j;
    initial begin
        for (i=0; i<(1<<LINEA_W); i=i+1)
            for (j=0; j<LINE_WORDS; j=j+1)
                mem[i][j*32 +: 32] = i*LINE_WORDS+j; //4 words in 1 line, so start from j*32
    end


    always @(posedge clk) begin
        mem_resp <= 0; //make sure the mem_resp is only a 1 cycle pulse

        if (rst == 1) count_cycles <= 0;

        else begin
            if (mem_req == 1 && mem_resp == 0) begin //check if memory access is being requested
                if (count_cycles == LATENCY - 1) begin //check if latency has been reached
                    if (mem_we == 1) mem[mem_addr] <= mem_wdata; 
                    else mem_rdata <= mem[mem_addr]; 
                    mem_resp <= 1; //set the mem_resp when action is complete
                    count_cycles <= 0;
                end
                else count_cycles <= count_cycles + 1;
            end
        end
    end
endmodule
