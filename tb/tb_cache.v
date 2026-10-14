module tb_cache;
    //defined once, here
    parameter WAYS = 1;
    parameter SETS = 16;
    parameter LINE_WORDS = 4;
    parameter POLICY = 0;
    parameter ADDR_W = 16;
    parameter LATENCY = 3;

    cache #(
        .WAYS(WAYS),
        .SETS(SETS),
        .LINE_WORDS(LINE_WORDS),
        .POLICY(POLICY),
        .ADDR_W(ADDR_W)
    ) dut (
        // port connections
    );

    mem_model #(
        .ADDR_W(ADDR_W),
        .LINE_WORDS(LINE_WORDS),
        .LATENCY(LATENCY)
    ) mem (
        // port connections
    );
endmodule
