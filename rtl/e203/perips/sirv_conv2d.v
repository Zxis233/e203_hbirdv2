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
// Designer   : 2D Convolution Accelerator
//
// Description:
//  Simple 2D convolution accelerator with ICB bus interface for E203 SoC
//  Supports 3x3 kernel convolution on 3x3 image patch
//  Uses DMA for writing results to memory
//
// ====================================================================

module sirv_conv2d #(
  parameter AW = 32,
  parameter DW = 32
)(
  input                clk,
  input                rst_n,

  // Configuration Interface (ICB Slave - from CPU)
  input                cfg_icb_cmd_valid,
  output               cfg_icb_cmd_ready,
  input  [AW-1:0]      cfg_icb_cmd_addr,
  input                cfg_icb_cmd_read,
  input  [DW-1:0]      cfg_icb_cmd_wdata,
  input  [DW/8-1:0]    cfg_icb_cmd_wmask,
  
  output               cfg_icb_rsp_valid,
  input                cfg_icb_rsp_ready,
  output [DW-1:0]      cfg_icb_rsp_rdata,
  output               cfg_icb_rsp_err,

  // DMA Interface (ICB Master - to DMA/memory)
  output               dma_icb_cmd_valid,
  input                dma_icb_cmd_ready,
  output [AW-1:0]      dma_icb_cmd_addr,
  output               dma_icb_cmd_read,
  output [DW-1:0]      dma_icb_cmd_wdata,
  output [DW/8-1:0]    dma_icb_cmd_wmask,
  
  input                dma_icb_rsp_valid,
  output               dma_icb_rsp_ready,
  input  [DW-1:0]      dma_icb_rsp_rdata,
  input                dma_icb_rsp_err,

  // Interrupt output
  output               conv_irq
);

  // Register offsets (7-bit address space: 128 bytes total)
  // Control/Status registers
  localparam REG_CTRL      = 7'h00;  // 0x00: Control register
  localparam REG_STATUS    = 7'h04;  // 0x04: Status register
  localparam REG_DST_ADDR  = 7'h08;  // 0x08: Destination address for DMA write
  localparam REG_RESULT    = 7'h0C;  // 0x0C: Convolution result (read-only)
  
  // Image data registers (3x3 = 9 values, each 8-bit stored in 32-bit registers)
  localparam REG_IMG_0     = 7'h10;  // 0x10: Image row 0 (pixels 0,1,2 packed)
  localparam REG_IMG_1     = 7'h14;  // 0x14: Image row 1 (pixels 3,4,5 packed)
  localparam REG_IMG_2     = 7'h18;  // 0x18: Image row 2 (pixels 6,7,8 packed)
  
  // Kernel data registers (3x3 = 9 values, each 8-bit signed stored in 32-bit registers)
  localparam REG_KER_0     = 7'h20;  // 0x20: Kernel row 0 (weights 0,1,2 packed)
  localparam REG_KER_1     = 7'h24;  // 0x24: Kernel row 1 (weights 3,4,5 packed)
  localparam REG_KER_2     = 7'h28;  // 0x28: Kernel row 2 (weights 6,7,8 packed)

  // Control register bits
  localparam CTRL_ENABLE   = 0;  // Enable convolution
  localparam CTRL_START    = 1;  // Start computation
  localparam CTRL_DMA_EN   = 2;  // Enable DMA write after computation

  // Status register bits
  localparam STATUS_BUSY   = 0;  // Busy computing
  localparam STATUS_DONE   = 1;  // Computation done
  localparam STATUS_ERROR  = 2;  // Error occurred (DMA error)

  // State machine states
  localparam STATE_IDLE      = 3'b000;
  localparam STATE_COMPUTE   = 3'b001;
  localparam STATE_DMA_WRITE = 3'b010;
  localparam STATE_DMA_RSP   = 3'b011;
  localparam STATE_DONE      = 3'b100;

  // Registers
  reg [DW-1:0]    ctrl_reg;
  reg [DW-1:0]    status_reg;
  reg [AW-1:0]    dst_addr_reg;
  reg signed [DW-1:0] result_reg;  // Convolution result (signed)
  
  // Image data registers (3 rows, packed as [pixel2:pixel1:pixel0])
  reg [DW-1:0]    img_reg_0;
  reg [DW-1:0]    img_reg_1;
  reg [DW-1:0]    img_reg_2;
  
  // Kernel data registers (3 rows, packed as [weight2:weight1:weight0])
  reg [DW-1:0]    ker_reg_0;
  reg [DW-1:0]    ker_reg_1;
  reg [DW-1:0]    ker_reg_2;
  
  // Internal signals
  reg [2:0]       state;
  
  wire            conv_enable;
  wire            conv_start;
  wire            dma_enable;
  wire            conv_busy;
  wire            conv_done;
  wire            conv_error;
  
  assign conv_enable = ctrl_reg[CTRL_ENABLE];
  assign conv_start  = ctrl_reg[CTRL_START];
  assign dma_enable  = ctrl_reg[CTRL_DMA_EN];
  assign conv_busy   = status_reg[STATUS_BUSY];
  assign conv_done   = status_reg[STATUS_DONE];
  assign conv_error  = status_reg[STATUS_ERROR];
  
  // Interrupt generation
  assign conv_irq = conv_done | conv_error;

  // Configuration interface handshake
  wire cfg_cmd_hsked = cfg_icb_cmd_valid & cfg_icb_cmd_ready;
  wire cfg_rsp_hsked = cfg_icb_rsp_valid & cfg_icb_rsp_ready;
  
  // DMA interface handshake
  wire dma_cmd_hsked = dma_icb_cmd_valid & dma_icb_cmd_ready;
  wire dma_rsp_hsked = dma_icb_rsp_valid & dma_icb_rsp_ready;

  // Configuration register access
  wire [6:0] cfg_addr_offset = cfg_icb_cmd_addr[6:0];
  wire cfg_sel_ctrl     = (cfg_addr_offset == REG_CTRL);
  wire cfg_sel_status   = (cfg_addr_offset == REG_STATUS);
  wire cfg_sel_dst_addr = (cfg_addr_offset == REG_DST_ADDR);
  wire cfg_sel_result   = (cfg_addr_offset == REG_RESULT);
  wire cfg_sel_img_0    = (cfg_addr_offset == REG_IMG_0);
  wire cfg_sel_img_1    = (cfg_addr_offset == REG_IMG_1);
  wire cfg_sel_img_2    = (cfg_addr_offset == REG_IMG_2);
  wire cfg_sel_ker_0    = (cfg_addr_offset == REG_KER_0);
  wire cfg_sel_ker_1    = (cfg_addr_offset == REG_KER_1);
  wire cfg_sel_ker_2    = (cfg_addr_offset == REG_KER_2);

  // Configuration read data
  reg [DW-1:0] cfg_rdata;
  always @(*) begin
    case (cfg_addr_offset)
      REG_CTRL:     cfg_rdata = ctrl_reg;
      REG_STATUS:   cfg_rdata = status_reg;
      REG_DST_ADDR: cfg_rdata = dst_addr_reg;
      REG_RESULT:   cfg_rdata = result_reg;
      REG_IMG_0:    cfg_rdata = img_reg_0;
      REG_IMG_1:    cfg_rdata = img_reg_1;
      REG_IMG_2:    cfg_rdata = img_reg_2;
      REG_KER_0:    cfg_rdata = ker_reg_0;
      REG_KER_1:    cfg_rdata = ker_reg_1;
      REG_KER_2:    cfg_rdata = ker_reg_2;
      default:      cfg_rdata = {DW{1'b0}};
    endcase
  end

  // Configuration response
  reg cfg_rsp_valid_r;
  reg [DW-1:0] cfg_rsp_rdata_r;
  
  assign cfg_icb_cmd_ready = ~cfg_rsp_valid_r | cfg_rsp_hsked;
  assign cfg_icb_rsp_valid = cfg_rsp_valid_r;
  assign cfg_icb_rsp_rdata = cfg_rsp_rdata_r;
  assign cfg_icb_rsp_err   = 1'b0;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cfg_rsp_valid_r <= 1'b0;
      cfg_rsp_rdata_r <= {DW{1'b0}};
    end else if (cfg_cmd_hsked) begin
      cfg_rsp_valid_r <= 1'b1;
      cfg_rsp_rdata_r <= cfg_rdata;
    end else if (cfg_rsp_hsked) begin
      cfg_rsp_valid_r <= 1'b0;
    end
  end

  // Write enable signals
  wire ctrl_wr_ena     = cfg_cmd_hsked & (~cfg_icb_cmd_read) & cfg_sel_ctrl;
  wire dst_addr_wr_ena = cfg_cmd_hsked & (~cfg_icb_cmd_read) & cfg_sel_dst_addr & ~conv_busy;
  wire img0_wr_ena     = cfg_cmd_hsked & (~cfg_icb_cmd_read) & cfg_sel_img_0 & ~conv_busy;
  wire img1_wr_ena     = cfg_cmd_hsked & (~cfg_icb_cmd_read) & cfg_sel_img_1 & ~conv_busy;
  wire img2_wr_ena     = cfg_cmd_hsked & (~cfg_icb_cmd_read) & cfg_sel_img_2 & ~conv_busy;
  wire ker0_wr_ena     = cfg_cmd_hsked & (~cfg_icb_cmd_read) & cfg_sel_ker_0 & ~conv_busy;
  wire ker1_wr_ena     = cfg_cmd_hsked & (~cfg_icb_cmd_read) & cfg_sel_ker_1 & ~conv_busy;
  wire ker2_wr_ena     = cfg_cmd_hsked & (~cfg_icb_cmd_read) & cfg_sel_ker_2 & ~conv_busy;
  
  wire status_clr_done  = cfg_cmd_hsked & (~cfg_icb_cmd_read) & cfg_sel_status & cfg_icb_cmd_wdata[STATUS_DONE];
  wire status_clr_error = cfg_cmd_hsked & (~cfg_icb_cmd_read) & cfg_sel_status & cfg_icb_cmd_wdata[STATUS_ERROR];
  
  // Control register write
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_reg <= {DW{1'b0}};
    end else if (ctrl_wr_ena) begin
      ctrl_reg <= cfg_icb_cmd_wdata;
    end else if (state == STATE_DONE) begin
      // Clear start bit when done
      ctrl_reg[CTRL_START] <= 1'b0;
    end
  end

  // Status register
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      status_reg <= {DW{1'b0}};
    end else begin
      // Busy bit
      status_reg[STATUS_BUSY] <= (state != STATE_IDLE) && (state != STATE_DONE);
      
      // Done bit - set when computation/DMA completes, cleared by writing 1
      if (state == STATE_DONE)
        status_reg[STATUS_DONE] <= 1'b1;
      else if (status_clr_done)
        status_reg[STATUS_DONE] <= 1'b0;
        
      // Error bit - set on DMA error, cleared by writing 1
      if (state == STATE_DMA_RSP && dma_rsp_hsked && dma_icb_rsp_err)
        status_reg[STATUS_ERROR] <= 1'b1;
      else if (status_clr_error)
        status_reg[STATUS_ERROR] <= 1'b0;
    end
  end

  // Destination address register
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      dst_addr_reg <= {AW{1'b0}};
    else if (dst_addr_wr_ena)
      dst_addr_reg <= cfg_icb_cmd_wdata[AW-1:0];
  end

  // Image data registers
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      img_reg_0 <= {DW{1'b0}};
      img_reg_1 <= {DW{1'b0}};
      img_reg_2 <= {DW{1'b0}};
    end else begin
      if (img0_wr_ena) img_reg_0 <= cfg_icb_cmd_wdata;
      if (img1_wr_ena) img_reg_1 <= cfg_icb_cmd_wdata;
      if (img2_wr_ena) img_reg_2 <= cfg_icb_cmd_wdata;
    end
  end

  // Kernel data registers
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ker_reg_0 <= {DW{1'b0}};
      ker_reg_1 <= {DW{1'b0}};
      ker_reg_2 <= {DW{1'b0}};
    end else begin
      if (ker0_wr_ena) ker_reg_0 <= cfg_icb_cmd_wdata;
      if (ker1_wr_ena) ker_reg_1 <= cfg_icb_cmd_wdata;
      if (ker2_wr_ena) ker_reg_2 <= cfg_icb_cmd_wdata;
    end
  end

  // Extract individual pixel values (unsigned 8-bit) from packed registers
  wire [7:0] img_p0 = img_reg_0[7:0];
  wire [7:0] img_p1 = img_reg_0[15:8];
  wire [7:0] img_p2 = img_reg_0[23:16];
  wire [7:0] img_p3 = img_reg_1[7:0];
  wire [7:0] img_p4 = img_reg_1[15:8];
  wire [7:0] img_p5 = img_reg_1[23:16];
  wire [7:0] img_p6 = img_reg_2[7:0];
  wire [7:0] img_p7 = img_reg_2[15:8];
  wire [7:0] img_p8 = img_reg_2[23:16];

  // Extract individual kernel weights (signed 8-bit) from packed registers
  wire signed [7:0] ker_w0 = ker_reg_0[7:0];
  wire signed [7:0] ker_w1 = ker_reg_0[15:8];
  wire signed [7:0] ker_w2 = ker_reg_0[23:16];
  wire signed [7:0] ker_w3 = ker_reg_1[7:0];
  wire signed [7:0] ker_w4 = ker_reg_1[15:8];
  wire signed [7:0] ker_w5 = ker_reg_1[23:16];
  wire signed [7:0] ker_w6 = ker_reg_2[7:0];
  wire signed [7:0] ker_w7 = ker_reg_2[15:8];
  wire signed [7:0] ker_w8 = ker_reg_2[23:16];

  // Convolution computation (multiply-accumulate)
  // Result = sum(img[i] * ker[i]) for i = 0 to 8
  wire signed [15:0] prod0 = $signed({1'b0, img_p0}) * ker_w0;
  wire signed [15:0] prod1 = $signed({1'b0, img_p1}) * ker_w1;
  wire signed [15:0] prod2 = $signed({1'b0, img_p2}) * ker_w2;
  wire signed [15:0] prod3 = $signed({1'b0, img_p3}) * ker_w3;
  wire signed [15:0] prod4 = $signed({1'b0, img_p4}) * ker_w4;
  wire signed [15:0] prod5 = $signed({1'b0, img_p5}) * ker_w5;
  wire signed [15:0] prod6 = $signed({1'b0, img_p6}) * ker_w6;
  wire signed [15:0] prod7 = $signed({1'b0, img_p7}) * ker_w7;
  wire signed [15:0] prod8 = $signed({1'b0, img_p8}) * ker_w8;

  wire signed [31:0] conv_sum = prod0 + prod1 + prod2 + prod3 + prod4 +
                                 prod5 + prod6 + prod7 + prod8;

  // State machine
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= STATE_IDLE;
      result_reg <= {DW{1'b0}};
    end else begin
      case (state)
        STATE_IDLE: begin
          if (conv_enable && conv_start) begin
            state <= STATE_COMPUTE;
          end
        end
        
        STATE_COMPUTE: begin
          // Perform convolution (single cycle for 3x3)
          result_reg <= conv_sum;
          if (dma_enable) begin
            state <= STATE_DMA_WRITE;
          end else begin
            state <= STATE_DONE;
          end
        end
        
        STATE_DMA_WRITE: begin
          if (dma_cmd_hsked) begin
            state <= STATE_DMA_RSP;
          end
        end
        
        STATE_DMA_RSP: begin
          if (dma_rsp_hsked) begin
            state <= STATE_DONE;
          end
        end
        
        STATE_DONE: begin
          state <= STATE_IDLE;
        end
        
        default: begin
          state <= STATE_IDLE;
        end
      endcase
    end
  end

  // DMA interface outputs
  assign dma_icb_cmd_valid = (state == STATE_DMA_WRITE);
  assign dma_icb_cmd_addr  = dst_addr_reg;
  assign dma_icb_cmd_read  = 1'b0;  // Always write
  assign dma_icb_cmd_wdata = result_reg;
  assign dma_icb_cmd_wmask = {(DW/8){1'b1}};
  
  assign dma_icb_rsp_ready = (state == STATE_DMA_RSP);

endmodule
