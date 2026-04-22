`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: aes128_core_ce
// What this does:
// - AES-128 iterative encryption core with clock-enable style progress control
// - `start` loads a new block when idle
// - `ce` advances round state; when `ce` is low, state holds
//
// Notes:
// - Initial AddRoundKey uses the input key directly (rk0 = key)
// - Round keys are generated incrementally per round (on-the-fly key schedule)
//////////////////////////////////////////////////////////////////////////////////

module aes128_core_ce(
    input  wire         clk,
    input  wire         rst,
    input  wire         start,
    input  wire         ce,
    input  wire [127:0] plaintext,
    input  wire [127:0] key,
    output reg  [127:0] ciphertext,
    output reg          done,
    output reg          busy
);

function [31:0] rcon_word;
    input [3:0] round_idx;
    begin
        case (round_idx)
            4'd1:  rcon_word = 32'h01000000;
            4'd2:  rcon_word = 32'h02000000;
            4'd3:  rcon_word = 32'h04000000;
            4'd4:  rcon_word = 32'h08000000;
            4'd5:  rcon_word = 32'h10000000;
            4'd6:  rcon_word = 32'h20000000;
            4'd7:  rcon_word = 32'h40000000;
            4'd8:  rcon_word = 32'h80000000;
            4'd9:  rcon_word = 32'h1b000000;
            4'd10: rcon_word = 32'h36000000;
            default: rcon_word = 32'h00000000;
        endcase
    end
endfunction

reg [127:0] round_key_reg;
reg [127:0] state_reg;
reg [3:0]   round_ctr;

wire [31:0] rk_w0 = round_key_reg[127:96];
wire [31:0] rk_w1 = round_key_reg[95:64];
wire [31:0] rk_w2 = round_key_reg[63:32];
wire [31:0] rk_w3 = round_key_reg[31:0];

wire [31:0] rk_rotword = {rk_w3[23:0], rk_w3[31:24]};
wire [31:0] rk_subword;

subword u_key_subword (
    .word_in(rk_rotword),
    .word_out(rk_subword)
);

wire [31:0] rk_next_w0 = rk_w0 ^ rk_subword ^ rcon_word(round_ctr);
wire [31:0] rk_next_w1 = rk_w1 ^ rk_next_w0;
wire [31:0] rk_next_w2 = rk_w2 ^ rk_next_w1;
wire [31:0] rk_next_w3 = rk_w3 ^ rk_next_w2;

wire [127:0] next_round_key = {rk_next_w0, rk_next_w1, rk_next_w2, rk_next_w3};

// Simple operand isolation to reduce unnecessary switching while idle
wire normal_round_active = busy && (round_ctr >= 4'd1) && (round_ctr <= 4'd9);
wire final_round_active  = busy && (round_ctr == 4'd10);

wire [127:0] normal_state_in = normal_round_active ? state_reg : 128'h0;
wire [127:0] normal_key_in   = normal_round_active ? next_round_key : 128'h0;
wire [127:0] final_state_in  = final_round_active ? state_reg : 128'h0;
wire [127:0] final_key_in    = final_round_active ? next_round_key : 128'h0;

wire [127:0] normal_round_out;
wire [127:0] final_round_out;

aes_round u_aes_round (
    .state_in(normal_state_in),
    .round_key(normal_key_in),
    .state_out(normal_round_out)
);

aes_final_round u_aes_final_round (
    .state_in(final_state_in),
    .round_key(final_key_in),
    .state_out(final_round_out)
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        round_key_reg <= 128'h0;
        state_reg   <= 128'h0;
        ciphertext  <= 128'h0;
        round_ctr   <= 4'd0;
        done        <= 1'b0;
        busy        <= 1'b0;
    end
    else begin
        // done is a pulse
        done <= 1'b0;

        // Accept a new block only when idle
        if (start && !busy) begin
            round_key_reg <= key;
            // Initial AddRoundKey with round key 0 (the original key)
            state_reg <= plaintext ^ key;
            round_ctr <= 4'd1;
            busy      <= 1'b1;
        end
        // Advance rounds only on enable ticks
        else if (busy && ce) begin
            if ((round_ctr >= 4'd1) && (round_ctr <= 4'd9)) begin
                state_reg <= normal_round_out;
                round_key_reg <= next_round_key;
                round_ctr <= round_ctr + 4'd1;
            end else if (round_ctr == 4'd10) begin
                ciphertext <= final_round_out;
                round_key_reg <= next_round_key;
                busy       <= 1'b0;
                done       <= 1'b1;
                round_ctr  <= 4'd0;
            end
        end
    end
end

endmodule
