`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: aes_top_parallel
// What this does:
// - N-lane duplicated AES-128 architecture for architecture-driven voltage scaling
// - Input broadcast to all lanes
// - Per-lane CE schedule (effective lane update rate = f_sample / N)
// - Completion capture and ordered output through a MUX-style collect path
//
// Interface style:
// - `start` + (plaintext, key) submits one block when `ready` is high
// - `done` pulses when one ciphertext result is emitted
//////////////////////////////////////////////////////////////////////////////////

module aes_top_parallel #(
    parameter integer N         = 2,
    parameter integer ROB_DEPTH = 16,
    parameter integer SEQ_W     = 16
)(
    input  wire         clk,
    input  wire         rst,
    input  wire         start,
    input  wire [127:0] plaintext,
    input  wire [127:0] key,
    output reg  [127:0] ciphertext,
    output reg          done,
    output wire         busy,
    output wire         ready
);

function integer clog2;
    input integer value;
    integer v;
    begin
        v = value - 1;
        clog2 = 0;
        while (v > 0) begin
            v = v >> 1;
            clog2 = clog2 + 1;
        end
    end
endfunction

localparam integer PHASE_W = (N <= 2) ? 1 : clog2(N);
localparam integer ROB_W   = (ROB_DEPTH <= 2) ? 1 : clog2(ROB_DEPTH);
localparam integer LANE_W  = (N <= 2) ? 1 : clog2(N);

reg [127:0] bcast_plaintext;
reg [127:0] bcast_key;
reg         pending_valid;

reg [127:0] lane_plaintext_reg [0:N-1];
reg [127:0] lane_key_reg       [0:N-1];

reg [PHASE_W-1:0] phase_counter;
reg [N-1:0]       lane_start;
wire [N-1:0]      lane_ce;
wire [N-1:0]      lane_busy;
wire [N-1:0]      lane_done;
wire [127:0]      lane_ciphertext [0:N-1];

reg               lane_active_valid [0:N-1];
reg [SEQ_W-1:0]   lane_seq          [0:N-1];
reg [SEQ_W-1:0]   seq_in;
reg [SEQ_W-1:0]   seq_out;

reg [127:0]       rob_data  [0:ROB_DEPTH-1];
reg               rob_valid [0:ROB_DEPTH-1];

reg               busy_r;
assign busy  = busy_r;
assign ready = !pending_valid;

// Completion MUX-style collection path
reg               comp_fire_valid;
reg [127:0]       comp_fire_data;
reg [SEQ_W-1:0]   comp_fire_seq;
reg [LANE_W-1:0]  comp_fire_lane;

reg               comp_valid_r;
reg [127:0]       comp_data_r;
reg [SEQ_W-1:0]   comp_seq_r;
reg [LANE_W-1:0]  comp_lane_r;

// Dispatch decision
reg               dispatch_valid;
integer           dispatch_lane_idx;

wire [ROB_W-1:0]  retire_slot = seq_out[ROB_W-1:0];
wire [ROB_W-1:0]  comp_slot   = comp_seq_r[ROB_W-1:0];
wire              retire_valid = rob_valid[retire_slot];

integer i;

always @(*) begin
    busy_r = pending_valid;
    for (i = 0; i < N; i = i + 1) begin
        if (lane_active_valid[i] || lane_busy[i])
            busy_r = 1'b1;
    end
    for (i = 0; i < ROB_DEPTH; i = i + 1) begin
        if (rob_valid[i])
            busy_r = 1'b1;
    end
end

always @(*) begin
    comp_fire_valid = 1'b0;
    comp_fire_data  = 128'h0;
    comp_fire_seq   = {SEQ_W{1'b0}};
    comp_fire_lane  = {LANE_W{1'b0}};

    for (i = 0; i < N; i = i + 1) begin
        if (!comp_fire_valid && lane_done[i]) begin
            comp_fire_valid = 1'b1;
            comp_fire_data  = lane_ciphertext[i];
            comp_fire_seq   = lane_seq[i];
            comp_fire_lane  = i;
        end
    end
end

always @(*) begin
    dispatch_valid    = 1'b0;
    dispatch_lane_idx = 0;

    if (pending_valid) begin
        for (i = 0; i < N; i = i + 1) begin
            if (!dispatch_valid && lane_ce[i] && !lane_active_valid[i] && !lane_busy[i]) begin
                dispatch_valid    = 1'b1;
                dispatch_lane_idx = i;
            end
        end
    end
end

genvar gi;
generate
    for (gi = 0; gi < N; gi = gi + 1) begin : GEN_LANES
        localparam [PHASE_W-1:0] LANE_ID = gi;

        assign lane_ce[gi] = (phase_counter == LANE_ID);

        aes128_core_ce u_core_ce (
            .clk(clk),
            .rst(rst),
            .start(lane_start[gi]),
            .ce(lane_ce[gi]),
            .plaintext(lane_plaintext_reg[gi]),
            .key(lane_key_reg[gi]),
            .ciphertext(lane_ciphertext[gi]),
            .done(lane_done[gi]),
            .busy(lane_busy[gi])
        );
    end
endgenerate

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bcast_plaintext <= 128'h0;
        bcast_key       <= 128'h0;
        pending_valid   <= 1'b0;

        phase_counter   <= {PHASE_W{1'b0}};
        lane_start      <= {N{1'b0}};

        seq_in          <= {SEQ_W{1'b0}};
        seq_out         <= {SEQ_W{1'b0}};

        comp_valid_r    <= 1'b0;
        comp_data_r     <= 128'h0;
        comp_seq_r      <= {SEQ_W{1'b0}};
        comp_lane_r     <= {LANE_W{1'b0}};

        ciphertext      <= 128'h0;
        done            <= 1'b0;

        for (i = 0; i < N; i = i + 1) begin
            lane_active_valid[i] <= 1'b0;
            lane_seq[i]          <= {SEQ_W{1'b0}};
            lane_plaintext_reg[i] <= 128'h0;
            lane_key_reg[i]       <= 128'h0;
        end

        for (i = 0; i < ROB_DEPTH; i = i + 1) begin
            rob_data[i]  <= 128'h0;
            rob_valid[i] <= 1'b0;
        end
    end
    else begin
        // Defaults for one-cycle pulses
        lane_start <= {N{1'b0}};
        done       <= retire_valid;
        ciphertext <= retire_valid ? rob_data[retire_slot] : ciphertext;

        // Global phase drives per-lane CE ticks (effective lane rate = f_sample/N)
        if (phase_counter == (N - 1))
            phase_counter <= {PHASE_W{1'b0}};
        else
            phase_counter <= phase_counter + {{(PHASE_W-1){1'b0}}, 1'b1};

        // Capture one incoming block into the broadcast register when empty
        if (start && !pending_valid) begin
            bcast_plaintext <= plaintext;
            bcast_key       <= key;
            pending_valid   <= 1'b1;
        end

        // Dispatch pending work to the currently enabled free lane
        if (dispatch_valid) begin
            lane_start[dispatch_lane_idx]      <= 1'b1;
            lane_active_valid[dispatch_lane_idx] <= 1'b1;
            lane_seq[dispatch_lane_idx]        <= seq_in;
            lane_plaintext_reg[dispatch_lane_idx] <= bcast_plaintext;
            lane_key_reg[dispatch_lane_idx]       <= bcast_key;
            seq_in                             <= seq_in + {{(SEQ_W-1){1'b0}}, 1'b1};
            pending_valid                      <= 1'b0;
        end

        // Commit buffered lane completion into ROB.
        if (comp_valid_r) begin
            rob_data[comp_slot]        <= comp_data_r;
            rob_valid[comp_slot]       <= 1'b1;
            lane_active_valid[comp_lane_r] <= 1'b0;
        end

        // Capture new completion into one-cycle staging registers.
        if (comp_fire_valid) begin
            comp_valid_r <= 1'b1;
            comp_data_r  <= comp_fire_data;
            comp_seq_r   <= comp_fire_seq;
            comp_lane_r  <= comp_fire_lane;
        end else if (comp_valid_r) begin
            comp_valid_r <= 1'b0;
        end

        // Retire results in-order
        if (retire_valid) begin
            rob_valid[retire_slot] <= 1'b0;
            seq_out              <= seq_out + {{(SEQ_W-1){1'b0}}, 1'b1};
        end
    end
end

endmodule
