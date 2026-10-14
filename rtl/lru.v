module lru
#(
    parameter WAYS = 2,
    parameter SETS = 16
)
(
    input wire clk,
    input wire rst,

    //from the cache when a way just got used
    input wire used,

    //which set and which way was used
    input wire [$clog2(SETS)-1:0] index,
    input wire [$clog2(WAYS)-1:0] way,

    //to the cache - the least recently used way of the set at index
    output reg [$clog2(WAYS)-1:0] victim
);
    localparam WAY_W = $clog2(WAYS);

    //one age per way - 0 is the most recently used, WAYS-1 is the least
    reg [WAY_W-1:0] age [0:SETS-1][0:WAYS-1];

    //find the oldest way
    wire [WAYS-1:0] is_oldest;

    genvar g;
    generate
        for (g=0; g<WAYS; g=g+1) begin : age_cmp
            assign is_oldest[g] = (age[index][g] == WAYS-1);
        end
    endgenerate

    //find the index of the oldest way
    integer w;
    always @(*) begin
        victim = 0;
        for (w=0; w<WAYS; w=w+1) begin
            if (is_oldest[w]) victim = w;
        end
    end

    integer i, j;
    always @(posedge clk) begin
        if (rst) begin
            //start every set with ages 0, 1, 2 ... so they are all different
            for (i=0; i<SETS; i=i+1)
                for (j=0; j<WAYS; j=j+1)
                    age[i][j] <= j;
        end

        else if (used) begin
            for (i=0; i<WAYS; i=i+1) begin
                if(i == way) age[index][i] <= 0;
                else if (age[index][i] < age[index][way]) age[index][i] <= (age[index][i] + 1);
            end
        end
    end

endmodule
