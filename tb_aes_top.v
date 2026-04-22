`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Testbench: tb_aes_top
// What this does:
// - Applies a known AES-128 test vector
// - Pulses start
// - Waits for done
// - Prints the result
//
// Standard AES-128 known-answer test:
// Key       = 000102030405060708090a0b0c0d0e0f
// Plaintext = 00112233445566778899aabbccddeeff
// Expected  = 69c4e0d86a7b0430d8cdb78070b4c55a
//////////////////////////////////////////////////////////////////////////////////

module tb_aes_top;

reg         clk;
reg         rst;
reg         start;
reg  [127:0] plaintext;
reg  [127:0] key;
wire [127:0] ciphertext;
wire        done;
wire        busy;

aes_top dut (
    .clk(clk),
    .rst(rst),
    .start(start),
    .plaintext(plaintext),
    .key(key),
    .ciphertext(ciphertext),
    .done(done),
    .busy(busy)
);

// 100 MHz clock -> 10 ns period
always #5 clk = ~clk;

initial begin
    clk = 1'b0;
    rst = 1'b1;
    start = 1'b0;
    plaintext = 128'h0;
    key = 128'h0;

    // Hold reset for a few cycles
    #20;
    rst = 1'b0;

    // Apply standard AES-128 test vector
    key       = 128'h000102030405060708090a0b0c0d0e0f;
    plaintext = 128'h00112233445566778899aabbccddeeff;

    // Pulse start for one cycle
    #10;
    start = 1'b1;
    #10;
    start = 1'b0;

    // Wait until encryption is done
    wait(done == 1'b1);

    $display("==============================================");
    $display("AES-128 Encryption Finished");
    $display("Key        = %h", key);
    $display("Plaintext  = %h", plaintext);
    $display("Ciphertext = %h", ciphertext);
    $display("Expected   = 69c4e0d86a7b0430d8cdb78070b4c55a");
    if (ciphertext == 128'h69c4e0d86a7b0430d8cdb78070b4c55a)
        $display("RESULT     = PASS");
    else
        $display("RESULT     = CHECK BYTE ORDER / DEBUG");
    $display("==============================================");

    #20;
    $finish;
end

endmodule