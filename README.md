# Cache Controller

This is my first Verilog project. It is an N-way set-associative write-back cache. You can pick between true LRU and tree pseudo-LRU for replacement.

Status: Done. The cache (rtl/cache.v), both replacement policies (rtl/lru.v and rtl/plru.v), the memory model (tb/mem_model.v) and the testbench (tb/tb_cache.v) are all written, and every config I ran passes. The results are in the Results section at the bottom.

## How to run it

You need ModelSim (I used the Intel FPGA Starter Edition). Run everything from the project folder.

To run the testbench with its default config (1 way, 16 sets, LRU) and open the waveforms:

do run.do

To run a different config, change the parameters in your code, then run the run.do command again, pressing "Reload" when you are prompted.

Each run prints a PASSED or ERROR line for every test, the hit rates for the random and hot/cold tests, and OVERALL PASS at the end if nothing failed.

## Parameters

- WAYS (default 1): lines per set, has to be a power of two
- SETS (default 16): number of sets, power of two
- LINE_WORDS (default 4): number of 32-bit words in a line, power of two
- POLICY (default 0): 0 = LRU, 1 = tree PLRU
- ADDR_W (default 16): width of a word address
- LATENCY (default 3): clock cycles it takes memory to respond

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

LRU (rtl/lru.v) gives every way in a set an age from 0 to WAYS-1, where 0 is the most recently used. The ages in a set are always all different. When a way is used it becomes 0, and every way that was younger than it gets one older. The victim is the way with age WAYS-1. This takes WAYS * log2(WAYS) bits per set.

Tree pseudo-LRU (rtl/plru.v) puts the ways at the bottom of a binary tree and keeps one bit at each node above them, which works like an arrow pointing left or right. To find the victim it starts at the top and follows the arrows down to a way. When a way is used, every arrow on the path from that way up to the top is set to point away from it. This takes WAYS - 1 bits per set. It does not always pick the oldest way, but it never picks the one that was just used. With 2 ways the two policies behave exactly the same.

The bits each policy needs to store per set for LRU vs PLRU is 2 bits vs 1 bit at 2 ways, 8 vs 3 at 4 ways, and 24 vs 7 at 8 ways. The formula to calculate the bits per set needed for LRU is WAYS*log2(WAYS), and for PLRU is (WAYS-1).

## Design simplifications

These are choices I made to keep the project small enough to finish, not things I forgot:

- Word addressing: every address is one 32-bit word, and there are no byte enables, so the CPU can only read or write whole words.
- One request at a time: the CPU holds its request until the cache responds, so the cache never has to juggle more than one access.
- Wide memory port: a whole line moves between the cache and memory in one transfer, so there are no counters for sending a line in pieces.
- Plain register arrays: the tags and data are stored in ordinary Verilog arrays that are read in the same cycle. This is simple to simulate, but a real FPGA design would put the data in block RAM.
- Fixed-latency memory: the memory model always takes LATENCY cycles to respond, instead of acting like real memory with varying delays.

## Testbench

tb/tb_cache.v runs the cache against a simple memory model (tb/mem_model.v) and a reference array in the testbench that holds what every address should contain. Every read is checked against that array. The tests run in this order:

- read miss then hit
- write then read back
- same set conflicts
- dirty eviction then re-read
- replacement policy (only when WAYS is more than 1)
- random test
- final read-back of every address the random test used
- hot/cold test
- counter check (hit_count + miss_count has to equal the number of accesses)

At the end it prints OVERALL PASS or the number of errors.

## Hit and miss rates

I only measure the hit and miss rates in two tests, the random test and the hot/cold test. The other tests are only there to check that the cache is correct, so their rates do not mean anything.

The rate is worked out from the counters: hit rate = hits / (hits + misses), and the miss rate is whatever is left over.

Random test: random reads and writes over an address range that is twice the size of the cache, so lines keep getting evicted and brought back. The addresses are uniformly random, so there is nothing for a replacement policy to take advantage of. I expect about a 50% hit rate for any policy, since the cache can hold about half of the addresses.

Hot/cold test: this one has a pattern a replacement policy can use. 90% of the reads go to a group of "hot" lines, and the other 10% go to a "cold" region that is 16 times bigger than the cache. The hot lines add up to 90% of the cache, so they nearly fill it. The cold reads keep forcing evictions, so a good policy should throw out cold lines and keep the hot ones. The first pass warms up the cache and only the second pass is counted. The best possible hit rate here is about 90%, since the cold reads almost always miss.

With 2 ways, LRU and PLRU should give exactly the same results.

## Results

Every number is a hit rate in percent. PLRU is n/a at 1 way because with only one way there is nothing to choose, so no policy is built. The tables use SEED = 1. I also tried other seeds and they gave approximately the same results, so the numbers do not depend on one lucky seed.

The best possible hot/cold hit rate is about 90%, because 10% of the reads go to the cold region and almost all of those miss. So none of the hot/cold numbers can go above 90%, and the ones here (about 77% to 86%) are the part of that ceiling the cache actually reached.

### 16 sets

```
Ways   Random LRU   Random PLRU   Hot/cold LRU   Hot/cold PLRU
1        49.92%        n/a           86.09%         n/a
2        49.85%       49.85%         82.11%        82.11%
4        50.31%       50.22%         76.80%        76.52%
8        49.44%       49.62%         81.09%        79.00%
```

### 64 sets

```
Ways   Random LRU   Random PLRU   Hot/cold LRU   Hot/cold PLRU
1        50.05%        n/a           79.69%         n/a
2        49.49%       49.49%         80.88%        80.88%
4        49.83%       49.77%         79.25%        78.13%
8        49.99%       50.04%         79.29%        77.68%
```

### LRU minus PLRU

All values are percentage points. Positive means LRU was ahead.

```
Ways   Random 16 sets   Random 64 sets   Hot/cold 16 sets   Hot/cold 64 sets
2          0.00             0.00              0.00               0.00
4         +0.09            +0.06             +0.28              +1.12
8         -0.18            -0.05             +2.09              +1.61
```

What I take from this:

- Random test: LRU and PLRU are the same within about 0.2 points, and the sign flips, so that is just noise. This is what I expected, because random addresses have no pattern to exploit.
- Hot/cold test: LRU is ahead at 4 and 8 ways by 0.3 to 2.1 points. PLRU only approximates LRU, so sometimes it throws out a hot line that LRU would have kept.
- 2 ways: identical, as expected, since a single bit is enough to track which of two ways is older.
- The trade-off: at 8 ways PLRU needs 7 bits per set instead of 24, and it cost about 1.6 to 2.1 points of hit rate on the hot/cold test.

## Future work

- Synthesis: run both policies through Quartus to measure how much logic each one uses and how fast it can be clocked, since this project only compares them in simulation.
- Victim cache: add a small fully associative cache (2 to 4 lines) that catches lines as they are evicted. On a miss the cache would check it first, which should cut down the misses caused by lines fighting over the same set.
