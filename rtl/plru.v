module plru
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

    //to the cache - the way the tree points at in the set at index
    output reg [$clog2(WAYS)-1:0] victim
);
    localparam WAY_W = $clog2(WAYS);

    //one tree of WAYS-1 bits per set
    //the children of node n are 2n+1 (left) and 2n+2 (right)
    //the parent of node n is (n-1)/2
    //the ways are the bottom row, so way w is node (WAYS-1)+w
    //a bit of 0 points left, 1 points right

    //the arrows of all the sets
    reg [WAYS-2:0] data_arrows [0:SETS-1];

    //the arrows of the set at index
    wire [WAYS-2:0] set_arrows = data_arrows[index];

    //find the victim starting at the top
    integer victim_node, victim_lvl;
    always @(*) begin
        victim_node = 0;
        for (victim_lvl=0; victim_lvl<WAY_W; victim_lvl=victim_lvl+1) begin
            if(set_arrows[victim_node]) victim_node = (victim_node*2) + 2;
            else victim_node = (victim_node*2) + 1;
        end
        //turn node number into way number
        victim = victim_node - (WAYS-1);
    end

    integer i, unode, uparent, ulvl;
    always @(posedge clk) begin
        if (rst) begin
            //start every tree with all bits pointing left
            for (i=0; i<SETS; i=i+1)
                data_arrows[i] <= 0;
        end

        //if a way was used, must update one value per row of the tree to point away from the used way
        else if (used) begin
            //start at the used way's node
            unode = (WAYS-1) + way;
            for (ulvl=0; ulvl<WAY_W; ulvl=ulvl+1) begin
                uparent = (unode-1)/2;
                //point the parent's arrow away from unode
                //odd nodes are left children, so point right (1), otherwise point left (0)
                if (unode % 2 == 1) data_arrows[index][uparent] <= 1;
                else data_arrows[index][uparent] <= 0;

                //move up a level
                unode = uparent;
            end
        end
    end

endmodule
