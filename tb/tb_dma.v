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
// Designer   : DMA Testbench
//
// Description:
//  Testbench for DMA controller verification
//  Tests memory-to-memory data transfer
//
// ====================================================================

`timescale 1ns / 1ps

module tb_dma();

  // Clock and reset
  reg clk;
  reg rst_n;
  
  // DMA signals
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
  
  wire        mem_icb_cmd_valid;
  wire        mem_icb_cmd_ready;
  wire [31:0] mem_icb_cmd_addr;
  wire        mem_icb_cmd_read;
  wire [31:0] mem_icb_cmd_wdata;
  wire [3:0]  mem_icb_cmd_wmask;
  
  wire        mem_icb_rsp_valid;
  wire        mem_icb_rsp_ready;
  wire [31:0] mem_icb_rsp_rdata;
  wire        mem_icb_rsp_err;
  
  wire        dma_irq;
  
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

  // Simple memory model
  reg [31:0] memory [0:1023];
  reg        mem_rsp_valid_r;
  reg [31:0] mem_rsp_rdata_r;
  
  assign mem_icb_cmd_ready = 1'b1;  // Always ready
  assign mem_icb_rsp_valid = mem_rsp_valid_r;
  assign mem_icb_rsp_rdata = mem_rsp_rdata_r;
  assign mem_icb_rsp_err   = 1'b0;
  
  // Memory model logic
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mem_rsp_valid_r <= 1'b0;
      mem_rsp_rdata_r <= 32'h0;
    end else begin
      mem_rsp_valid_r <= 1'b0;
      
      if (mem_icb_cmd_valid && mem_icb_cmd_ready) begin
        if (mem_icb_cmd_read) begin
          // Read operation
          mem_rsp_rdata_r <= memory[mem_icb_cmd_addr[11:2]];
          mem_rsp_valid_r <= 1'b1;
        end else begin
          // Write operation
          memory[mem_icb_cmd_addr[11:2]] <= mem_icb_cmd_wdata;
          mem_rsp_valid_r <= 1'b1;
        end
      end
    end
  end

  // DUT instantiation
  sirv_dma #(
    .AW(32),
    .DW(32)
  ) u_dma (
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
    
    .mem_icb_cmd_valid  (mem_icb_cmd_valid),
    .mem_icb_cmd_ready  (mem_icb_cmd_ready),
    .mem_icb_cmd_addr   (mem_icb_cmd_addr),
    .mem_icb_cmd_read   (mem_icb_cmd_read),
    .mem_icb_cmd_wdata  (mem_icb_cmd_wdata),
    .mem_icb_cmd_wmask  (mem_icb_cmd_wmask),
    
    .mem_icb_rsp_valid  (mem_icb_rsp_valid),
    .mem_icb_rsp_ready  (mem_icb_rsp_ready),
    .mem_icb_rsp_rdata  (mem_icb_rsp_rdata),
    .mem_icb_rsp_err    (mem_icb_rsp_err),
    
    .dma_irq            (dma_irq)
  );

  // Clock generation: 100MHz (10ns period)
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Task: Write to DMA register
  task dma_write;
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

  // Task: Read from DMA register
  task dma_read;
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

  // Test stimulus
  integer i;
  reg [31:0] read_data;
  reg [31:0] expected_data;
  integer errors;
  
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
    
    // Initialize memory with test data
    for (i = 0; i < 1024; i = i + 1) begin
      memory[i] = 32'h0;
    end
    
    // Source data: addresses 0x00-0x3F (16 words)
    for (i = 0; i < 16; i = i + 1) begin
      memory[i] = 32'hA5A5_0000 + i;
    end
    
    // Reset
    #100;
    rst_n = 1;
    #50;
    
    $display("===================================");
    $display("DMA Controller Testbench Starting");
    $display("===================================");
    
    // Test 1: Register read/write
    $display("\nTest 1: Register Access");
    dma_write(32'h00, 32'h00000001);  // Write CTRL
    dma_read(32'h00, read_data);
    if (read_data == 32'h00000001) begin
      $display("  CTRL register write/read: PASS");
    end else begin
      $display("  CTRL register write/read: FAIL (expected 0x00000001, got 0x%08h)", read_data);
      errors = errors + 1;
    end
    
    // Test 2: Memory-to-memory transfer
    $display("\nTest 2: Memory-to-Memory DMA Transfer");
    $display("  Source address: 0x0000");
    $display("  Destination address: 0x0100");
    $display("  Transfer length: 64 bytes (16 words)");
    
    // Configure DMA
    dma_write(32'h08, 32'h00000000);  // SRC address = 0x0000
    dma_write(32'h0C, 32'h00000100);  // DST address = 0x0100
    dma_write(32'h10, 32'h00000040);  // LEN = 64 bytes
    dma_write(32'h00, 32'h00000003);  // CTRL: enable + start
    
    // Wait for completion
    $display("  Waiting for DMA transfer...");
    read_data = 0;
    while ((read_data & 32'h00000002) == 0) begin
      #100;
      dma_read(32'h04, read_data);  // Read STATUS
    end
    
    if ((read_data & 32'h00000004) != 0) begin
      $display("  DMA transfer: FAIL (error bit set)");
      errors = errors + 1;
    end else begin
      $display("  DMA transfer completed");
      
      // Verify transferred data
      $display("  Verifying transferred data...");
      for (i = 0; i < 16; i = i + 1) begin
        expected_data = 32'hA5A5_0000 + i;
        if (memory[64 + i] != expected_data) begin
          $display("    Mismatch at word %0d: expected 0x%08h, got 0x%08h", 
                   i, expected_data, memory[64 + i]);
          errors = errors + 1;
        end
      end
      
      if (errors == 0) begin
        $display("  Data verification: PASS");
      end else begin
        $display("  Data verification: FAIL (%0d errors)", errors);
      end
    end
    
    // Test 3: Interrupt verification
    $display("\nTest 3: Interrupt Verification");
    if (dma_irq) begin
      $display("  Interrupt signal asserted: PASS");
    end else begin
      $display("  Interrupt signal not asserted: FAIL");
      errors = errors + 1;
    end
    
    // Clear done status
    dma_write(32'h04, 32'h00000002);  // Clear DONE bit
    #50;
    
    if (!dma_irq) begin
      $display("  Interrupt signal cleared: PASS");
    end else begin
      $display("  Interrupt signal not cleared: FAIL");
      errors = errors + 1;
    end
    
    // Final result
    $display("\n===================================");
    if (errors == 0) begin
      $display("All tests PASSED!");
    end else begin
      $display("Tests FAILED with %0d errors", errors);
    end
    $display("===================================\n");
    
    #100;
    $finish;
  end

  // VCD dump for waveform viewing
  initial begin
    $dumpfile("tb_dma.vcd");
    $dumpvars(0, tb_dma);
  end

  // Timeout watchdog
  initial begin
    #100000;
    $display("ERROR: Simulation timeout!");
    $finish;
  end

endmodule
