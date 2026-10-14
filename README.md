# Cache Controller

This is my first Verilog project. It is an N-way set-associative write-back cache. You can pick between true LRU and tree pseudo-LRU for replacement.

Status: still working on it. The cache (rtl/cache.v), both replacement policies (rtl/lru.v and rtl/plru.v), and the memory model (tb/mem_model.v) are written. The testbench (tb/tb_cache.v) is not done yet, so there are no results here yet.

## Parameters

- WAYS (default 1): lines per set, has to be a power of two
- SETS (default 16): number of sets, power of two
- LINE_WORDS (default 4): number of 32-bit words in a line, power of two
- POLICY (default 0): 0 = LRU, 1 = tree PLRU
- ADDR_W (default 16): width of a word address

## Clock and reset

- clk: everything updates on the rising edge
- rst: synchronous and active high, it clears all the valid bits

## How the handshake works

Both sides use the same rule. The one asking raises req and keeps it high (and keeps its other signals the same) until the other side pulses resp high for one clock cycle. Then the requester drops req. Only one request can be going at a time.

## CPU side signals

- cpu_req (input, 1 bit): CPU wants an access, held until cpu_resp
- cpu_we (input, 1 bit): 1 = write, 0 = read
- cpu_addr (input, ADDR_W bits): word address
- cpu_wdata (input, 32 bits): the word to write
- cpu_rdata (output, 32 bits): the word that was read, only valid when cpu_resp is high
- cpu_resp (output, 1 bit): one-cycle pulse when the access is done

## Memory side signals

- mem_req (output, 1 bit): cache wants a transfer, held until mem_resp
- mem_we (output, 1 bit): 1 = write a line back, 0 = fetch a line
- mem_addr (output, ADDR_W - OFFSET_W bits): line address (the word address without the offset bits)
- mem_wdata (output, LINE_WORDS * 32 bits): the whole line to write
- mem_rdata (input, LINE_WORDS * 32 bits): the whole line that was read, only valid when mem_resp is high
- mem_resp (input, 1 bit): one-cycle pulse when the transfer is done

The directions are from the cache's point of view.

## Counter signals

- hit_count (output, 32 bits): number of accesses where the line was already in the cache
- miss_count (output, 32 bits): number of accesses where the line had to be fetched from memory
- evict_count (output, 32 bits): number of misses that replaced a valid line. It counts clean lines and dirty lines, not just the ones that get written back

All three go to zero on reset. Every access counts as either one hit or one miss. 

## Address layout

A word address gets split into three parts, starting from the top bit:

- Tag: ADDR_W - INDEX_W - OFFSET_W bits, compared with the stored tag to see if it is a hit
- Index: INDEX_W = log2(SETS) bits, picks the set
- Offset: OFFSET_W = log2(LINE_WORDS) bits, picks the word inside the line

With the default values that works out to a 10-bit tag, 4-bit index, and 2-bit offset.

A line is stored as one long row of bits. Word 0 is the lowest 32 bits, word 1 is the next 32 bits, and so on.

## State machine

The controller has five states. It sits in IDLE until the CPU raises cpu_req, then goes to LOOKUP. From LOOKUP it goes straight to RESPOND on a hit. On a miss it goes to REFILL, but if the line being replaced is dirty it goes to WRITEBACK first and then to REFILL. After REFILL it goes to RESPOND, and RESPOND always goes back to IDLE.

- IDLE: waits for cpu_req.
- LOOKUP: checks every way of the set for a matching tag. On a miss it also picks which way to replace (an empty way if there is one, otherwise the one the replacement policy picks). Takes one cycle.
- WRITEBACK: sends the old line to memory and waits for mem_resp. Only happens if the line being replaced is valid and dirty. Takes however many cycles memory takes (mem latency).
- REFILL: fetches the line the CPU wants and waits for mem_resp. Then it stores the line and its tag, sets valid, and clears dirty. Takes however many cycles memory takes (mem latency).
- RESPOND: does the actual read or write and pulses cpu_resp. On a write it stores the word and sets dirty. Takes one cycle.

So a hit never talks to memory, a miss with a clean or empty line talks to it once, and a miss with a dirty line talks to it twice.

A write miss does not need anything special. REFILL brings the whole line in first, and then RESPOND writes the one word into it.

## Replacement policies

When a miss happens and every way in the set is full, the cache has to pick a way to throw out. If the set still has an empty way it always uses that one, and only asks the replacement policy when the set is full. POLICY picks which policy gets built. With WAYS = 1 there is nothing to choose, so neither module is built.

Both policies are separate modules with the same ports, so the cache does not know which one it has. The cache tells the policy every time a way is used (once per access, in RESPOND, whether it was a hit or a fresh fill), and the policy always shows which way it would evict from the current set.

True LRU (rtl/lru.v) gives every way in a set an age from 0 to WAYS-1, where 0 is the most recently used. The ages in a set are always all different. When a way is used it becomes 0, and every way that was younger than it gets one older. The victim is the way with age WAYS-1. This takes WAYS * log2(WAYS) bits per set.

Tree pseudo-LRU (rtl/plru.v) puts the ways at the bottom of a binary tree and keeps one bit at each node above them, which works like an arrow pointing left or right. To find the victim it starts at the top and follows the arrows down to a way. When a way is used, every arrow on the path from that way up to the top is set to point away from it. This takes WAYS - 1 bits per set. It does not always pick the oldest way, but it never picks the one that was just used. With 2 ways the two policies behave exactly the same.

The bits each policy needs to store per set for LRU vs PRLU is 2 bits vs 1 bit at 2 ways, 8 vs 3 at 4 ways, and 24 vs 7 at 8 ways. The formula to calculate the bits per set needed for LRU is WAYS*log2(WAYS), and for PRLU is (WAYS-1).
