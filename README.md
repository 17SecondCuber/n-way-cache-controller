# Cache Controller

This is my first Verilog project. It is an N-way set-associative write-back cache. You can pick between true LRU and tree pseudo-LRU for replacement.

Status: still working on it. Right now I only have a small counter test to  make sure ModelSim works. The cache itself is not done yet. This file is what I am planning the interface to look like.

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

## Address layout

A word address gets split into three parts, starting from the top bit:

- Tag: ADDR_W - INDEX_W - OFFSET_W bits, compared with the stored tag to see if it is a hit
- Index: INDEX_W = log2(SETS) bits, picks the set
- Offset: OFFSET_W = log2(LINE_WORDS) bits, picks the word inside the line

With the default values that works out to a 10-bit tag, 4-bit index, and 2-bit offset.
