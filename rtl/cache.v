module cache
#(
    parameter WAYS = 1,
    parameter SETS = 16,
    parameter LINE_WORDS = 4,
    parameter POLICY = 0,
    parameter ADDR_W = 16
)
(
    input wire clk,
    input wire rst,

    //cpu inputs and outputs
    input wire cpu_req,
    input wire cpu_we,
    input wire [ADDR_W-1:0] cpu_addr,
    input wire [31:0] cpu_wdata,
    output wire [31:0] cpu_rdata,
    output wire cpu_resp,

    //memory inputs and outputs
    output wire mem_req,
    output wire mem_we,
    output wire [ADDR_W-$clog2(LINE_WORDS)-1:0] mem_addr,
    output wire [LINE_WORDS*32-1:0] mem_wdata,
    input wire [LINE_WORDS*32-1:0] mem_rdata,
    input wire mem_resp,

    //statistics on efficiency
    output reg [31:0] hit_count,
    output reg [31:0] miss_count,
    output reg [31:0] evict_count
);
    //derived widths
    localparam OFFSET_W = $clog2(LINE_WORDS);
    localparam INDEX_W = $clog2(SETS);
    localparam TAG_W = ADDR_W - INDEX_W - OFFSET_W;
    localparam LINE_W = LINE_WORDS*32;
    //a way number needs at least 1 bit, even when there is only one way
    localparam WAY_W = (WAYS > 1) ? $clog2(WAYS) : 1;

    //fsm states
    localparam IDLE = 3'd0;
    localparam LOOKUP = 3'd1;
    localparam WRITEBACK = 3'd2;
    localparam REFILL = 3'd3;
    localparam RESPOND = 3'd4;

    reg [2:0] state;

    //storage - one entry per line, addressed as [set][way]
    reg valid [0:SETS-1][0:WAYS-1];
    reg dirty [0:SETS-1][0:WAYS-1];
    reg [TAG_W-1:0] tags [0:SETS-1][0:WAYS-1];
    reg [LINE_W-1:0] data [0:SETS-1][0:WAYS-1];

    //split the cpu address into tag, index, offset
    wire [TAG_W-1:0] addr_tag = cpu_addr[ADDR_W-1 -: TAG_W];
    wire [OFFSET_W-1:0] addr_offset = cpu_addr[OFFSET_W-1:0];
    wire [INDEX_W-1:0] addr_index = cpu_addr[OFFSET_W +: INDEX_W];

    //check every way of the selected set at once - one bit per way
    wire [WAYS-1:0] way_hit;
    wire [WAYS-1:0] way_invalid;

    genvar g;
    generate
        for (g=0; g<WAYS; g=g+1) begin : way_cmp
            //hit if way g is valid and its tag equals addr_tag
            assign way_hit[g] = valid[addr_index][g] && (tags[addr_index][g] == addr_tag);

            //invalid if way g is empty
            assign way_invalid[g] = !valid[addr_index][g];
        end
    endgenerate

    //see if there is at least one hit/invalid
    wire has_hit = |way_hit;
    wire has_invalid = |way_invalid;

    //holds the number of the way that is hit/invalid
    reg [WAY_W-1:0] hit_way;
    reg [WAY_W-1:0] invalid_way;

    //turn the way_hit/way_invalid bit vectors into a way number
    integer w;
    always @(*) begin
        hit_way = 0;
        invalid_way = 0;
        for (w=0; w<WAYS; w=w+1) begin
            if (way_hit[w]) hit_way = w;
            if (way_invalid[w]) invalid_way = w;
        end
    end

    //the way this access uses
    reg [WAY_W-1:0] way_sel;

    //the victim determined by the lru/plru
    wire [WAY_W-1:0] policy_victim;

    //bit to tell lru/plru that a way was used so it updates values
    wire way_was_used = (state == RESPOND);

    generate
        //only one victim possible if ways = 1
        if (WAYS == 1) begin : no_policy
            assign policy_victim = 0;
        end
        //use lru or plru depending on policy bit
        else if (POLICY == 0) begin : use_lru
            lru #(.WAYS(WAYS), .SETS(SETS)) policy (
                .clk(clk),
                .rst(rst),
                .used(way_was_used),
                .index(addr_index),
                .way(way_sel),
                .victim(policy_victim)
            );
        end
        else begin : use_plru
            plru #(.WAYS(WAYS), .SETS(SETS)) policy (
                .clk(clk),
                .rst(rst),
                .used(way_was_used),
                .index(addr_index),
                .way(way_sel),
                .victim(policy_victim)
            );
        end
    endgenerate

    //on a miss, fill an empty way if there is one, otherwise use the lru/plru
    wire [WAY_W-1:0] victim_way = has_invalid ? invalid_way : policy_victim;

    assign cpu_resp = (state == RESPOND);

    //the data we are reading is from the cache picked by the set, way, then word respectively
    assign cpu_rdata = data[addr_index][way_sel][addr_offset*32 +: 32];

    //the data we are writing is the entire line picked by the set and way
    assign mem_wdata = data[addr_index][way_sel];

    //mem_req is high whenever we are reading or writing to mem (WRITEBACK or REFILL)
    assign mem_req = (state == WRITEBACK) || (state == REFILL);

    //mem_we is high whenever we are writing to mem
    assign mem_we = (state == WRITEBACK);

    //if it is a writeback, then use the tag bits already there, otherwise, use the tag bits from cpu since it is a refill
    assign mem_addr = (state == WRITEBACK) ? {tags[addr_index][way_sel], addr_index} : {addr_tag, addr_index};

    integer i, j;
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            way_sel <= 0;
            hit_count <= 0;
            miss_count <= 0;
            evict_count <= 0;
            for (i=0; i<SETS; i=i+1)
                for (j=0; j<WAYS; j=j+1)
                    valid[i][j] <= 0;
        end

        else begin
            case (state)

                IDLE: begin
                    //go to LOOKUP when cpu_req is high
                    if (cpu_req) state <= LOOKUP;
                end

                LOOKUP: begin

                    //on a hit, way_sel selects hit_way
                    if (has_hit) begin
                        way_sel <= hit_way;
                        state <= RESPOND;
                        hit_count <= hit_count + 1;
                    end

                    //else, way_sel gets victim_way
                    else begin
                        way_sel <= victim_way;
                        miss_count <= miss_count + 1;

                        //increment evict if the line being replaced is valid
                        if (valid[addr_index][victim_way]) evict_count <= evict_count + 1;

                        //writeback if valid and dirty, otherwise refill
                        if (valid[addr_index][victim_way] && dirty[addr_index][victim_way]) state <= WRITEBACK;
                        else state <= REFILL;

                    end
                end

                WRITEBACK: begin
                    //mem has latency, so go to refill only when mem_resp is set
                    if (mem_resp) state <= REFILL;
                end

                REFILL: begin
                    //mem has latency, so update cache and state only when mem_resp is set
                    if (mem_resp) begin
                        tags[addr_index][way_sel] <= addr_tag;
                        data[addr_index][way_sel] <= mem_rdata;
                        valid[addr_index][way_sel] <= 1;
                        dirty[addr_index][way_sel] <= 0;
                        state <= RESPOND;
                    end

                end

                RESPOND: begin
                    //if write, store data and set dirty bit
                    if (cpu_we) begin
                        data[addr_index][way_sel][32*addr_offset +: 32] <= cpu_wdata;
                        dirty[addr_index][way_sel] <= 1;
                    end
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
