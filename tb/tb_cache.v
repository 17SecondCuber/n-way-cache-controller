`timescale 1ns/1ps

module tb_cache;
    parameter WAYS = 1;
    parameter SETS = 16;
    parameter LINE_WORDS = 4;
    parameter POLICY = 0;
    parameter ADDR_W = 16;
    parameter LATENCY = 3;

    //random test settings
    parameter SEED = 1;
    //random addresses will be below this value, so addresses will be reused and the cache keeps evicting
    parameter RANGE = 2*SETS*WAYS*LINE_WORDS;
    //number of random accesses to perform - enough for each address in RANGE to be used approximately 40 times
    parameter RANDOM_OPS = 40*RANGE;
    //addresses this far apart land in the same set with different tags
    localparam SET_STRIDE = SETS*LINE_WORDS;

    //hot/cold test settings
    localparam CACHE_LINES = SETS*WAYS;
    //hot lines take up 90% of the cache
    localparam HOT_LINES = (CACHE_LINES*9)/10;
    //start above every address the earlier tests used
    localparam HOT_BASE = 4*SETS*WAYS*LINE_WORDS;
    //number of reads in each pass of the hot/cold test
    localparam HOT_OPS = 40*CACHE_LINES;

    localparam OFFSET_W = $clog2(LINE_WORDS);
    localparam LINE_W = LINE_WORDS*32;

    //cpu ports
    reg cpu_req = 0;
    reg cpu_we = 0;
    reg [ADDR_W-1:0] cpu_addr = 0;
    reg [31:0] cpu_wdata = 0;
    wire [31:0] cpu_rdata;
    wire cpu_resp;

    //mem ports
    wire mem_req;
    wire mem_we;
    wire [ADDR_W-OFFSET_W-1:0] mem_addr;
    wire [LINE_W-1:0] mem_wdata;
    wire [LINE_W-1:0] mem_rdata;
    wire mem_resp;

    //statistics
    wire [31:0] hit_count;
    wire [31:0] miss_count;
    wire [31:0] evict_count;

    reg rst = 1;
    //10 ns clock period
    reg clk = 0;
    always #5 clk = ~clk;

    cache #(
        .WAYS(WAYS),
        .SETS(SETS),
        .LINE_WORDS(LINE_WORDS),
        .POLICY(POLICY),
        .ADDR_W(ADDR_W)
    ) dut (
        .clk(clk),
        .rst(rst),
        .cpu_req(cpu_req),
        .cpu_we(cpu_we),
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata),
        .cpu_resp(cpu_resp),
        .mem_req(mem_req),
        .mem_we(mem_we),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata),
        .mem_resp(mem_resp),
        .hit_count(hit_count),
        .miss_count(miss_count),
        .evict_count(evict_count)
    );

    mem_model #(
        .ADDR_W(ADDR_W),
        .LINE_WORDS(LINE_WORDS),
        .LATENCY(LATENCY)
    ) mem (
        .clk(clk),
        .rst(rst),
        .mem_req(mem_req),
        .mem_we(mem_we),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata),
        .mem_resp(mem_resp)
    );

    //reference model to verify the cache's behavior - every word holds its own address
    reg [31:0] ref_mem [0:(1<<ADDR_W)-1];

    integer errors = 0;
    integer accesses = 0;

    //seed must be an integer so it can be overwritten
    integer seed = SEED;

    //cpu read or write, and checks the cache's response against the reference model and updates accesses
    task access(input we, input [ADDR_W-1:0] addr, input [31:0] wdata);
        begin
            @(negedge clk);
            cpu_req = 1;
            cpu_we = we;
            cpu_addr = addr;
            cpu_wdata = wdata;

            //wait until the cache is in RESPOND state
            @(negedge clk);
            while (cpu_resp !== 1) @(negedge clk);

            //when it reaches respond state, either verify the read data or update the reference model for a write
            if (!we) begin
                //read - check the data against the reference model
                if (cpu_rdata !== ref_mem[addr]) begin
                    errors = errors + 1;
                    $display("ERROR: addr=%0d cpu_rdata=%0d ref_mem=%0d",
                                addr, cpu_rdata, ref_mem[addr]);
                end
            end
            else begin
                //write - update the reference model
                ref_mem[addr] = wdata;
            end

            accesses = accesses + 1;
            cpu_req = 0;
        end
    endtask

    integer i;
    //error count before each test, so each test can tell if it added any
    integer errors_before;
    //miss count before a check that needs to know if a read was a hit or a miss
    integer misses_before;
    //which line the replacement policy should evict in the policy test
    integer expected_victim;
    //hit and miss counts when the current test started
    integer test_hits_before;
    integer test_misses_before;
    //hits and misses of the current test only
    integer local_hit_count;
    integer local_miss_count;
    real local_hit_rate;
    //which pass of the hot/cold test is running, and which line it reads
    integer pass;
    integer line;

    //print the hits and misses of the current test only by subtracting the counts from when it started
    task print_local_counts;
        begin
            local_hit_count = hit_count - test_hits_before;
            local_miss_count = miss_count - test_misses_before;
            local_hit_rate = (local_hit_count*100.0)/(local_hit_count + local_miss_count);
            $display("    hits=%0d misses=%0d hit_rate=%0.2f%%", local_hit_count, local_miss_count, local_hit_rate);
        end
    endtask

    initial begin
        //fill ref_mem the same way mem_model fills its memory (every word holds its own address)
        for (i=0; i<(1<<ADDR_W); i=i+1) ref_mem[i] = i;

        //hold reset for two cycles to make sure the cache and memory are reset
        repeat (2) @(negedge clk);
        rst = 0;

        //TESTS START HERE

        //read miss then hit - read one address twice, then check that miss_count and hit_count went up by one each
        errors_before = errors;
        repeat (2) access(0, 0, 0);
        if (miss_count !== 1 || hit_count !== 1) begin
            errors = errors + 1;
            $display("ERROR: miss_count=%0d hit_count=%0d", miss_count, hit_count);
        end
        if (errors == errors_before) $display("PASSED read miss then hit");
        else $display("ERROR: read miss then hit failed");

        //write then read back - write a value, read it, then read a different word in the same line
        //this checks that a cache is writing to the correct word in a line, and that the other words in the line are still correct
        errors_before = errors;
        access(1, 0, 1515);
        access(0, 0, 0);
        access(0, 1, 0);
        if (errors == errors_before) $display("PASSED write then read back");
        else $display("ERROR: write then read back failed");

        //same set conflicts - access more addresses than there are ways, all SET_STRIDE apart, then read them all back
        //this guarantees evictions will happen, and the cache will have to fetch lines from memory successfully
        errors_before = errors;
        for (i=0; i<WAYS+1; i=i+1) begin
            access(1, i*SET_STRIDE, 1000+i);
        end
        //access checks each read against ref_mem
        for (i=0; i<WAYS+1; i=i+1) begin
            access(0, i*SET_STRIDE, 0);
        end
        if (errors == errors_before) $display("PASSED same set conflicts");
        else $display("ERROR: same set conflicts failed");

        //dirty eviction then re-read - write to an address, evict its line, then read it again
        //force a writeback to occur, and make sure that the cache is writing to memory and reading it back correctly
        errors_before = errors;
        access(1, 0, 1234);
        for (i=0; i<WAYS; i=i+1) begin
            access(1, (WAYS+i+1)*SET_STRIDE, 2000+i);
        end
        //access checks that 1234 comes back, and the re-read must be a miss to prove the line was evicted
        misses_before = miss_count;
        access(0, 0, 0);
        if (miss_count !== misses_before + 1) begin
            errors = errors + 1;
            $display("ERROR: address 0 was never evicted");
        end
        if (errors == errors_before) $display("PASSED dirty eviction then re-read");
        else $display("ERROR: dirty eviction then re-read failed");

        //replacement policy - fill an empty set, touch line 1, bring in one more line, then check exactly which line was evicted
        //LRU must evict line 0; tree PLRU with more ways must evict line WAYS/2
        if (WAYS > 1) begin
            errors_before = errors;
            //set 1 is unused so far, so fill it, touch line 1, then add one more line so the policy must pick a victim
            for (i=0; i<WAYS; i=i+1) access(0, LINE_WORDS + i*SET_STRIDE, 0);
            access(0, LINE_WORDS + SET_STRIDE, 0);
            access(0, LINE_WORDS + WAYS*SET_STRIDE, 0);
            expected_victim = (POLICY == 0 || WAYS == 2) ? 0 : WAYS/2;

            //every other line must still hit, then the victim must miss
            misses_before = miss_count;
            for (i=0; i<WAYS; i=i+1) if (i != expected_victim) access(0, LINE_WORDS + i*SET_STRIDE, 0);
            if (miss_count !== misses_before) begin
                errors = errors + 1;
                $display("ERROR: the policy evicted a line other than line %0d", expected_victim);
            end
            access(0, LINE_WORDS + expected_victim*SET_STRIDE, 0);
            if (miss_count !== misses_before + 1) begin
                errors = errors + 1;
                $display("ERROR: line %0d was not evicted", expected_victim);
            end

            if (errors == errors_before) $display("PASSED replacement policy");
            else $display("ERROR: replacement policy failed");
        end

        //random test - run a large amount of random accesses, and check that the cache is reading/writing correctly
        //this will cause evictions to happen at every address, and the cache will have to fetch lines from memory successfully
        errors_before = errors;
        test_hits_before = hit_count;
        test_misses_before = miss_count;
        for (i=0; i<RANDOM_OPS; i=i+1) begin
            access({$random(seed)}%2, {$random(seed)}%RANGE, {$random(seed)});
        end
        if (errors == errors_before) $display("PASSED random test");
        else $display("ERROR: random test failed");
        //the random  and hot/cold test are the only ones with enough accesses for its hit rate to compare LRU and PLRU
        print_local_counts;

        //final read-back - make sure every address the test used holds the right value
        errors_before = errors;
        for (i=0; i<RANGE; i=i+1) begin
            access(0, i, 0);
        end
        if (errors == errors_before) $display("PASSED final read-back");
        else $display("ERROR: final read-back failed");

        //hot/cold - 90% of reads go to a group of hot lines that nearly fills the cache, 10% go to a huge cold region
        //lru/plru should throw out cold lines more often
        //the first pass warms the cache up with the hot lines, and only the second pass is counted
        errors_before = errors;
        for (pass=0; pass<2; pass=pass+1) begin
            if (pass == 1) begin
                test_hits_before = hit_count;
                test_misses_before = miss_count;
            end
            for (i=0; i<HOT_OPS; i=i+1) begin
                if ({$random(seed)}%10 != 0) line = {$random(seed)}%HOT_LINES;
                else line = HOT_LINES + {$random(seed)}%(16*CACHE_LINES);
                access(0, HOT_BASE + line*LINE_WORDS, 0);
            end
        end
        if (errors == errors_before) $display("PASSED hot/cold");
        else $display("ERROR: hot/cold failed");
        print_local_counts;

        //counter check - since every access is a hit or miss, hit_count + miss_count must equal accesses
        if (hit_count + miss_count !== accesses) begin
            errors = errors + 1;
            $display("ERROR: hit_count + miss_count != accesses");
        end
        else $display("PASSED counter check");

        //summary
        $display("WAYS=%0d SETS=%0d POLICY=%0d accesses=%0d hits=%0d misses=%0d evictions=%0d",
                 WAYS, SETS, POLICY, accesses, hit_count, miss_count, evict_count);
        if (errors == 0) $display("OVERALL PASS");
        else $display("FAIL: %0d errors", errors);
        $stop;
    end

endmodule
