`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: addroundkey
// What this does:
// - XORs the 128-bit AES state with the 128-bit round key.
// - This is the simplest AES transformation.
//////////////////////////////////////////////////////////////////////////////////

module addroundkey(
    input  wire [127:0] state_in,
    input  wire [127:0] round_key,
    output wire [127:0] state_out
);

assign state_out = state_in ^ round_key;

endmodule
