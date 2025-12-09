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
// Designer   : DMA Controller
//
// Description:
//  DMA controller with ICB bus interface for E203 SoC
//  Supports memory-to-memory data transfer
//
// ====================================================================

module sirv_dma #(
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

  // Memory Interface (ICB Master - to memory)
  output               mem_icb_cmd_valid,
  input                mem_icb_cmd_ready,
  output [AW-1:0]      mem_icb_cmd_addr,
  output               mem_icb_cmd_read,
  output [DW-1:0]      mem_icb_cmd_wdata,
  output [DW/8-1:0]    mem_icb_cmd_wmask,
  
  input                mem_icb_rsp_valid,
  output               mem_icb_rsp_ready,
  input  [DW-1:0]      mem_icb_rsp_rdata,
  input                mem_icb_rsp_err,

  // Interrupt output
  output               dma_irq
);

  // Register offsets
  localparam REG_CTRL   = 5'h00;  // 0x00
  localparam REG_STATUS = 5'h04;  // 0x04
  localparam REG_SRC    = 5'h08;  // 0x08
  localparam REG_DST    = 5'h0C;  // 0x0C
  localparam REG_LEN    = 5'h10;  // 0x10

  // Control register bits
  localparam CTRL_ENABLE = 0;
  localparam CTRL_START  = 1;
  localparam CTRL_DIR    = 2;

  // Status register bits
  localparam STATUS_BUSY  = 0;
  localparam STATUS_DONE  = 1;
  localparam STATUS_ERROR = 2;

  // State machine states
  localparam STATE_IDLE      = 3'b000;
  localparam STATE_READ_REQ  = 3'b001;
  localparam STATE_READ_RSP  = 3'b010;
  localparam STATE_WRITE_REQ = 3'b011;
  localparam STATE_WRITE_RSP = 3'b100;
  localparam STATE_DONE      = 3'b101;

  // Registers
  reg [DW-1:0]    ctrl_reg;
  reg [DW-1:0]    status_reg;
  reg [AW-1:0]    src_reg;
  reg [AW-1:0]    dst_reg;
  reg [DW-1:0]    len_reg;
  
  // Internal signals
  reg [2:0]       state;
  reg [AW-1:0]    current_src;
  reg [AW-1:0]    current_dst;
  reg [DW-1:0]    remaining_len;
  reg [DW-1:0]    read_data_buf;
  
  wire            dma_enable;
  wire            dma_start;
  wire            dma_busy;
  wire            dma_done;
  wire            dma_error;
  
  assign dma_enable = ctrl_reg[CTRL_ENABLE];
  assign dma_start  = ctrl_reg[CTRL_START];
  assign dma_busy   = status_reg[STATUS_BUSY];
  assign dma_done   = status_reg[STATUS_DONE];
  assign dma_error  = status_reg[STATUS_ERROR];
  
  // Interrupt generation
  assign dma_irq = dma_done | dma_error;

  // Configuration interface handshake
  wire cfg_cmd_hsked = cfg_icb_cmd_valid & cfg_icb_cmd_ready;
  wire cfg_rsp_hsked = cfg_icb_rsp_valid & cfg_icb_rsp_ready;
  
  // Memory interface handshake
  wire mem_cmd_hsked = mem_icb_cmd_valid & mem_icb_cmd_ready;
  wire mem_rsp_hsked = mem_icb_rsp_valid & mem_icb_rsp_ready;

  // Configuration register access
  wire [4:0] cfg_addr_offset = cfg_icb_cmd_addr[4:0];
  wire cfg_sel_ctrl   = (cfg_addr_offset == REG_CTRL);
  wire cfg_sel_status = (cfg_addr_offset == REG_STATUS);
  wire cfg_sel_src    = (cfg_addr_offset == REG_SRC);
  wire cfg_sel_dst    = (cfg_addr_offset == REG_DST);
  wire cfg_sel_len    = (cfg_addr_offset == REG_LEN);

  // Configuration read data
  reg [DW-1:0] cfg_rdata;
  always @(*) begin
    case (cfg_addr_offset)
      REG_CTRL:   cfg_rdata = ctrl_reg;
      REG_STATUS: cfg_rdata = status_reg;
      REG_SRC:    cfg_rdata = {{(DW-AW){1'b0}}, src_reg};
      REG_DST:    cfg_rdata = {{(DW-AW){1'b0}}, dst_reg};
      REG_LEN:    cfg_rdata = len_reg;
      default:    cfg_rdata = {DW{1'b0}};
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

  // Control register write
  wire ctrl_wr_ena = cfg_cmd_hsked & (~cfg_icb_cmd_read) & cfg_sel_ctrl;
  wire status_clr_done  = cfg_cmd_hsked & (~cfg_icb_cmd_read) & cfg_sel_status & cfg_icb_cmd_wdata[STATUS_DONE];
  wire status_clr_error = cfg_cmd_hsked & (~cfg_icb_cmd_read) & cfg_sel_status & cfg_icb_cmd_wdata[STATUS_ERROR];
  
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
      
      // Done bit - set when transfer completes, cleared by writing 1
      if (state == STATE_DONE && (remaining_len == 0))
        status_reg[STATUS_DONE] <= 1'b1;
      else if (status_clr_done)
        status_reg[STATUS_DONE] <= 1'b0;
        
      // Error bit - set on error, cleared by writing 1
      if ((state == STATE_READ_RSP && mem_rsp_hsked && mem_icb_rsp_err) ||
          (state == STATE_WRITE_RSP && mem_rsp_hsked && mem_icb_rsp_err))
        status_reg[STATUS_ERROR] <= 1'b1;
      else if (status_clr_error)
        status_reg[STATUS_ERROR] <= 1'b0;
    end
  end

  // Source address register
  wire src_wr_ena = cfg_cmd_hsked & (~cfg_icb_cmd_read) & cfg_sel_src & ~dma_busy;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      src_reg <= {AW{1'b0}};
    else if (src_wr_ena)
      src_reg <= cfg_icb_cmd_wdata[AW-1:0];
  end

  // Destination address register
  wire dst_wr_ena = cfg_cmd_hsked & (~cfg_icb_cmd_read) & cfg_sel_dst & ~dma_busy;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      dst_reg <= {AW{1'b0}};
    else if (dst_wr_ena)
      dst_reg <= cfg_icb_cmd_wdata[AW-1:0];
  end

  // Length register
  wire len_wr_ena = cfg_cmd_hsked & (~cfg_icb_cmd_read) & cfg_sel_len & ~dma_busy;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      len_reg <= {DW{1'b0}};
    else if (len_wr_ena)
      len_reg <= cfg_icb_cmd_wdata;
  end

  // DMA state machine
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= STATE_IDLE;
      current_src <= {AW{1'b0}};
      current_dst <= {AW{1'b0}};
      remaining_len <= {DW{1'b0}};
      read_data_buf <= {DW{1'b0}};
    end else begin
      case (state)
        STATE_IDLE: begin
          if (dma_enable && dma_start && (len_reg > 0)) begin
            state <= STATE_READ_REQ;
            current_src <= src_reg;
            current_dst <= dst_reg;
            remaining_len <= len_reg;
          end
        end
        
        STATE_READ_REQ: begin
          if (mem_cmd_hsked) begin
            state <= STATE_READ_RSP;
          end
        end
        
        STATE_READ_RSP: begin
          if (mem_rsp_hsked) begin
            if (mem_icb_rsp_err) begin
              state <= STATE_DONE;
            end else begin
              read_data_buf <= mem_icb_rsp_rdata;
              state <= STATE_WRITE_REQ;
            end
          end
        end
        
        STATE_WRITE_REQ: begin
          if (mem_cmd_hsked) begin
            state <= STATE_WRITE_RSP;
          end
        end
        
        STATE_WRITE_RSP: begin
          if (mem_rsp_hsked) begin
            if (mem_icb_rsp_err) begin
              state <= STATE_DONE;
            end else begin
              current_src <= current_src + (DW/8);
              current_dst <= current_dst + (DW/8);
              remaining_len <= remaining_len - (DW/8);
              
              if (remaining_len <= (DW/8)) begin
                state <= STATE_DONE;
              end else begin
                state <= STATE_READ_REQ;
              end
            end
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

  // Memory interface outputs
  assign mem_icb_cmd_valid = (state == STATE_READ_REQ) || (state == STATE_WRITE_REQ);
  assign mem_icb_cmd_addr  = (state == STATE_READ_REQ) ? current_src : current_dst;
  assign mem_icb_cmd_read  = (state == STATE_READ_REQ);
  assign mem_icb_cmd_wdata = read_data_buf;
  assign mem_icb_cmd_wmask = {(DW/8){1'b1}};
  
  assign mem_icb_rsp_ready = (state == STATE_READ_RSP) || (state == STATE_WRITE_RSP);

endmodule
