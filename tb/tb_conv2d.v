/*                                                                      
Copyright 2018-2020 Nuclei System Technology, Inc.                
                                                                    
Licensed under the Apache License, Version 2.0 (the "License");         
you may not use this file except in compliance with the License.        
You may obtain a copy of the License at                                 
                                                                    
    http://www.apache.org/licenses/LICENSE-2.0                          
                                                                    
 Unless required by applicable law or agreed to in writing, software    
distributed under the License is distributed on an "AS IS" BASIS,       
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and     
limitations under the License.                                          
*/                                                                      
                                                                    
                                                                    
                                                                    
//=====================================================================
//
// Designer   : 2D Convolution Testbench
//
// Description:
//  Testbench for 2D convolution accelerator verification
//  Tests 3x3 convolution with DMA memory write
//
// ====================================================================

`timescale 1ns / 1ps

module tb_conv2d();

  // Memory model parameters
  localparam MEM_SIZE = 256;        // Memory size in words
  localparam MEM_ADDR_WIDTH = 8;    // log2(MEM_SIZE)

  // Clock and reset
  reg clk;
  reg rst_n;
  
  // Configuration ICB signals
  wire        cfg_icb_cmd_valid;
  wire        cfg_icb_cmd_ready;
  wire [31:0] cfg_icb_cmd_addr;
  wire        cfg_icb_cmd_read;
  wire [31:0] cfg_icb_cmd_wdata;
  wire [3:0]  cfg_icb_cmd_wmask;
  
  wire        cfg_icb_rsp_valid;
  wire        cfg_icb_rsp_ready;
  wire [31:0] cfg_icb_rsp_rdata;
  wire        cfg_icb_rsp_err;
  
  // DMA ICB signals
  wire        dma_icb_cmd_valid;
  wire        dma_icb_cmd_ready;
  wire [31:0] dma_icb_cmd_addr;
  wire        dma_icb_cmd_read;
  wire [31:0] dma_icb_cmd_wdata;
  wire [3:0]  dma_icb_cmd_wmask;
  
  wire        dma_icb_rsp_valid;
  wire        dma_icb_rsp_ready;
  wire [31:0] dma_icb_rsp_rdata;
  wire        dma_icb_rsp_err;
  
  wire        conv_irq;
  
  // Test control signals
  reg         cfg_cmd_valid_r;
  reg [31:0]  cfg_cmd_addr_r;
  reg         cfg_cmd_read_r;
  reg [31:0]  cfg_cmd_wdata_r;
  reg [3:0]   cfg_cmd_wmask_r;
  reg         cfg_rsp_ready_r;
  
  assign cfg_icb_cmd_valid = cfg_cmd_valid_r;
  assign cfg_icb_cmd_addr  = cfg_cmd_addr_r;
  assign cfg_icb_cmd_read  = cfg_cmd_read_r;
  assign cfg_icb_cmd_wdata = cfg_cmd_wdata_r;
  assign cfg_icb_cmd_wmask = cfg_cmd_wmask_r;
  assign cfg_icb_rsp_ready = cfg_rsp_ready_r;

  // Simple memory model for DMA writes
  reg [31:0] memory [0:MEM_SIZE-1];
  reg        dma_rsp_valid_r;
  reg [31:0] dma_rsp_rdata_r;
  
  assign dma_icb_cmd_ready = 1'b1;  // Always ready
  assign dma_icb_rsp_valid = dma_rsp_valid_r;
  assign dma_icb_rsp_rdata = dma_rsp_rdata_r;
  assign dma_icb_rsp_err   = 1'b0;
  
  // Memory model logic (DMA writes)
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dma_rsp_valid_r <= 1'b0;
      dma_rsp_rdata_r <= 32'h0;
    end else begin
      dma_rsp_valid_r <= 1'b0;
      
      if (dma_icb_cmd_valid && dma_icb_cmd_ready) begin
        if (dma_icb_cmd_read) begin
          // Read operation
          dma_rsp_rdata_r <= memory[dma_icb_cmd_addr[MEM_ADDR_WIDTH+1:2]];
          dma_rsp_valid_r <= 1'b1;
        end else begin
          // Write operation
          memory[dma_icb_cmd_addr[MEM_ADDR_WIDTH+1:2]] <= dma_icb_cmd_wdata;
          dma_rsp_valid_r <= 1'b1;
        end
      end
    end
  end

  // DUT instantiation
  sirv_conv2d #(
    .AW(32),
    .DW(32)
  ) u_conv2d (
    .clk                (clk),
    .rst_n              (rst_n),
    
    .cfg_icb_cmd_valid  (cfg_icb_cmd_valid),
    .cfg_icb_cmd_ready  (cfg_icb_cmd_ready),
    .cfg_icb_cmd_addr   (cfg_icb_cmd_addr),
    .cfg_icb_cmd_read   (cfg_icb_cmd_read),
    .cfg_icb_cmd_wdata  (cfg_icb_cmd_wdata),
    .cfg_icb_cmd_wmask  (cfg_icb_cmd_wmask),
    
    .cfg_icb_rsp_valid  (cfg_icb_rsp_valid),
    .cfg_icb_rsp_ready  (cfg_icb_rsp_ready),
    .cfg_icb_rsp_rdata  (cfg_icb_rsp_rdata),
    .cfg_icb_rsp_err    (cfg_icb_rsp_err),
    
    .dma_icb_cmd_valid  (dma_icb_cmd_valid),
    .dma_icb_cmd_ready  (dma_icb_cmd_ready),
    .dma_icb_cmd_addr   (dma_icb_cmd_addr),
    .dma_icb_cmd_read   (dma_icb_cmd_read),
    .dma_icb_cmd_wdata  (dma_icb_cmd_wdata),
    .dma_icb_cmd_wmask  (dma_icb_cmd_wmask),
    
    .dma_icb_rsp_valid  (dma_icb_rsp_valid),
    .dma_icb_rsp_ready  (dma_icb_rsp_ready),
    .dma_icb_rsp_rdata  (dma_icb_rsp_rdata),
    .dma_icb_rsp_err    (dma_icb_rsp_err),
    
    .conv_irq           (conv_irq)
  );

  // Clock generation: 100MHz (10ns period)
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Task: Write to configuration register
  task conv_write;
    input [31:0] addr;
    input [31:0] data;
    begin
      @(posedge clk);
      cfg_cmd_valid_r <= 1'b1;
      cfg_cmd_addr_r  <= addr;
      cfg_cmd_read_r  <= 1'b0;
      cfg_cmd_wdata_r <= data;
      cfg_cmd_wmask_r <= 4'hF;
      cfg_rsp_ready_r <= 1'b1;
      
      @(posedge clk);
      while (!cfg_icb_cmd_ready) @(posedge clk);
      
      cfg_cmd_valid_r <= 1'b0;
      
      while (!cfg_icb_rsp_valid) @(posedge clk);
      @(posedge clk);
      cfg_rsp_ready_r <= 1'b0;
    end
  endtask

  // Task: Read from configuration register
  task conv_read;
    input  [31:0] addr;
    output [31:0] data;
    begin
      @(posedge clk);
      cfg_cmd_valid_r <= 1'b1;
      cfg_cmd_addr_r  <= addr;
      cfg_cmd_read_r  <= 1'b1;
      cfg_cmd_wdata_r <= 32'h0;
      cfg_cmd_wmask_r <= 4'h0;
      cfg_rsp_ready_r <= 1'b1;
      
      @(posedge clk);
      while (!cfg_icb_cmd_ready) @(posedge clk);
      
      cfg_cmd_valid_r <= 1'b0;
      
      while (!cfg_icb_rsp_valid) @(posedge clk);
      data = cfg_icb_rsp_rdata;
      @(posedge clk);
      cfg_rsp_ready_r <= 1'b0;
    end
  endtask

  // Test variables
  integer i;
  reg [31:0] read_data;
  reg signed [31:0] expected_result;
  integer errors;
  
  // Test data
  // Image 3x3 (unsigned 8-bit values): 
  //   1  2  3
  //   4  5  6
  //   7  8  9
  // Packed as: row0=[0x00030201], row1=[0x00060504], row2=[0x00090807]
  
  // Kernel 3x3 (signed 8-bit weights):
  //   1  0 -1
  //   2  0 -2
  //   1  0 -1
  // Packed as: row0=[0x00FF0001], row1=[0x00FE0002], row2=[0x00FF0001]
  // This is a Sobel horizontal edge detector
  
  // Expected result:
  // 1*1 + 2*0 + 3*(-1) + 4*2 + 5*0 + 6*(-2) + 7*1 + 8*0 + 9*(-1)
  // = 1 + 0 - 3 + 8 + 0 - 12 + 7 + 0 - 9 = -8
  
  initial begin
    // Initialize signals
    rst_n = 0;
    cfg_cmd_valid_r = 0;
    cfg_cmd_addr_r  = 0;
    cfg_cmd_read_r  = 0;
    cfg_cmd_wdata_r = 0;
    cfg_cmd_wmask_r = 0;
    cfg_rsp_ready_r = 0;
    errors = 0;
    
    // Initialize memory
    for (i = 0; i < MEM_SIZE; i = i + 1) begin
      memory[i] = 32'h0;
    end
    
    // Reset
    #100;
    rst_n = 1;
    #50;
    
    $display("=========================================");
    $display("2D Convolution Accelerator Testbench");
    $display("=========================================");
    
    // ====== Test 1: Register read/write ======
    $display("\nTest 1: Register Access");
    conv_write(32'h00, 32'h00000001);  // Write CTRL (enable)
    conv_read(32'h00, read_data);
    if (read_data == 32'h00000001) begin
      $display("  CTRL register write/read: PASS");
    end else begin
      $display("  CTRL register write/read: FAIL (expected 0x00000001, got 0x%08h)", read_data);
      errors = errors + 1;
    end
    conv_write(32'h00, 32'h00000000);  // Clear CTRL
    
    // ====== Test 2: Convolution without DMA ======
    $display("\nTest 2: 3x3 Convolution (without DMA)");
    $display("  Image data:");
    $display("    [ 1  2  3 ]");
    $display("    [ 4  5  6 ]");
    $display("    [ 7  8  9 ]");
    $display("  Kernel (Sobel horizontal):");
    $display("    [ 1  0 -1 ]");
    $display("    [ 2  0 -2 ]");
    $display("    [ 1  0 -1 ]");
    
    // Configure image data (packed format)
    conv_write(32'h10, 32'h00030201);  // IMG row 0: pixels 1,2,3
    conv_write(32'h14, 32'h00060504);  // IMG row 1: pixels 4,5,6
    conv_write(32'h18, 32'h00090807);  // IMG row 2: pixels 7,8,9
    
    // Configure kernel data (packed format, signed 8-bit)
    // -1 in 8-bit signed = 0xFF
    // -2 in 8-bit signed = 0xFE
    conv_write(32'h20, 32'h00FF0001);  // KER row 0: 1, 0, -1
    conv_write(32'h24, 32'h00FE0002);  // KER row 1: 2, 0, -2
    conv_write(32'h28, 32'h00FF0001);  // KER row 2: 1, 0, -1
    
    // Start convolution (enable + start, no DMA)
    conv_write(32'h00, 32'h00000003);
    
    // Wait for completion
    $display("  Computing...");
    read_data = 0;
    while ((read_data & 32'h00000002) == 0) begin
      #50;
      conv_read(32'h04, read_data);  // Read STATUS
    end
    
    // Read result
    conv_read(32'h0C, read_data);
    expected_result = -32'd8;  // Expected: -8
    if ($signed(read_data) == expected_result) begin
      $display("  Convolution result: PASS (result = %0d)", $signed(read_data));
    end else begin
      $display("  Convolution result: FAIL (expected %0d, got %0d)", expected_result, $signed(read_data));
      errors = errors + 1;
    end
    
    // Clear done status
    conv_write(32'h04, 32'h00000002);
    
    // ====== Test 3: Convolution with DMA ======
    $display("\nTest 3: 3x3 Convolution (with DMA write)");
    
    // Configure destination address
    conv_write(32'h08, 32'h00000040);  // DST_ADDR = 0x40 (word 16)
    
    // Use same image and kernel, start with DMA enabled
    // enable + start + dma_en = 0x07
    conv_write(32'h00, 32'h00000007);
    
    // Wait for completion
    $display("  Computing and writing to memory...");
    read_data = 0;
    while ((read_data & 32'h00000002) == 0) begin
      #50;
      conv_read(32'h04, read_data);
    end
    
    // Check memory location
    if ($signed(memory[16]) == expected_result) begin
      $display("  DMA write verification: PASS (memory[16] = %0d)", $signed(memory[16]));
    end else begin
      $display("  DMA write verification: FAIL (expected %0d, got %0d)", expected_result, $signed(memory[16]));
      errors = errors + 1;
    end
    
    // Clear done status
    conv_write(32'h04, 32'h00000002);
    
    // ====== Test 4: Interrupt verification ======
    $display("\nTest 4: Interrupt Verification");
    // Start another convolution
    conv_write(32'h00, 32'h00000003);
    
    // Wait for done
    read_data = 0;
    while ((read_data & 32'h00000002) == 0) begin
      #50;
      conv_read(32'h04, read_data);
    end
    
    if (conv_irq) begin
      $display("  Interrupt signal asserted: PASS");
    end else begin
      $display("  Interrupt signal not asserted: FAIL");
      errors = errors + 1;
    end
    
    // Clear done status
    conv_write(32'h04, 32'h00000002);
    #50;
    
    if (!conv_irq) begin
      $display("  Interrupt signal cleared: PASS");
    end else begin
      $display("  Interrupt signal not cleared: FAIL");
      errors = errors + 1;
    end
    
    // ====== Test 5: Identity kernel ======
    $display("\nTest 5: Identity Kernel (center weight = 1, others = 0)");
    
    // Identity kernel: only center element is 1
    // Kernel:
    //   0  0  0
    //   0  1  0
    //   0  0  0
    // Packed: [w2:w1:w0] where w1 is center for row 1
    conv_write(32'h20, 32'h00000000);  // KER row 0: 0, 0, 0
    conv_write(32'h24, 32'h00000100);  // KER row 1: 0, 1, 0 (center weight at byte[1])
    conv_write(32'h28, 32'h00000000);  // KER row 2: 0, 0, 0
    
    // Start convolution
    conv_write(32'h00, 32'h00000003);
    
    // Wait for completion
    read_data = 0;
    while ((read_data & 32'h00000002) == 0) begin
      #50;
      conv_read(32'h04, read_data);
    end
    
    // Read result - should be center pixel value (5)
    conv_read(32'h0C, read_data);
    expected_result = 32'd5;
    if ($signed(read_data) == expected_result) begin
      $display("  Identity kernel result: PASS (result = %0d)", $signed(read_data));
    end else begin
      $display("  Identity kernel result: FAIL (expected %0d, got %0d)", expected_result, $signed(read_data));
      errors = errors + 1;
    end
    
    // Clear done status
    conv_write(32'h04, 32'h00000002);
    
    // ====== Test 6: All-ones kernel (box filter) ======
    $display("\nTest 6: Box Filter (all weights = 1)");
    
    // Box kernel: all elements are 1
    conv_write(32'h20, 32'h00010101);  // KER row 0: 1, 1, 1
    conv_write(32'h24, 32'h00010101);  // KER row 1: 1, 1, 1
    conv_write(32'h28, 32'h00010101);  // KER row 2: 1, 1, 1
    
    // Start convolution
    conv_write(32'h00, 32'h00000003);
    
    // Wait for completion
    read_data = 0;
    while ((read_data & 32'h00000002) == 0) begin
      #50;
      conv_read(32'h04, read_data);
    end
    
    // Read result - should be sum of all pixels (1+2+3+4+5+6+7+8+9 = 45)
    conv_read(32'h0C, read_data);
    expected_result = 32'd45;
    if ($signed(read_data) == expected_result) begin
      $display("  Box filter result: PASS (result = %0d)", $signed(read_data));
    end else begin
      $display("  Box filter result: FAIL (expected %0d, got %0d)", expected_result, $signed(read_data));
      errors = errors + 1;
    end
    
    // Clear done status
    conv_write(32'h04, 32'h00000002);
    
    // ====== Final result ======
    $display("\n=========================================");
    if (errors == 0) begin
      $display("All tests PASSED!");
    end else begin
      $display("Tests FAILED with %0d errors", errors);
    end
    $display("=========================================\n");
    
    #100;
    $finish;
  end

  // VCD dump for waveform viewing
  initial begin
    $dumpfile("tb_conv2d.vcd");
    $dumpvars(0, tb_conv2d);
  end

  // Timeout watchdog
  initial begin
    #200000;
    $display("ERROR: Simulation timeout!");
    $finish;
  end

endmodule
