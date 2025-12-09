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
// Designer   : DMA Wrapper
//
// Description:
//  Wrapper for DMA controller to integrate with E203 subsystem
//  Uses E203 standard macros and naming conventions
//
// ====================================================================

`include "e203_defines.v"

module e203_subsys_dma_wrapper (
  input                          clk,
  input                          rst_n,

  // Configuration Interface (ICB Slave - from CPU)
  input                          cfg_icb_cmd_valid,
  output                         cfg_icb_cmd_ready,
  input  [`E203_ADDR_SIZE-1:0]   cfg_icb_cmd_addr,
  input                          cfg_icb_cmd_read,
  input  [`E203_XLEN-1:0]        cfg_icb_cmd_wdata,
  input  [`E203_XLEN/8-1:0]      cfg_icb_cmd_wmask,
  
  output                         cfg_icb_rsp_valid,
  input                          cfg_icb_rsp_ready,
  output [`E203_XLEN-1:0]        cfg_icb_rsp_rdata,
  output                         cfg_icb_rsp_err,

  // Memory Interface (ICB Master - to memory)
  output                         mem_icb_cmd_valid,
  input                          mem_icb_cmd_ready,
  output [`E203_ADDR_SIZE-1:0]   mem_icb_cmd_addr,
  output                         mem_icb_cmd_read,
  output [`E203_XLEN-1:0]        mem_icb_cmd_wdata,
  output [`E203_XLEN/8-1:0]      mem_icb_cmd_wmask,
  
  input                          mem_icb_rsp_valid,
  output                         mem_icb_rsp_ready,
  input  [`E203_XLEN-1:0]        mem_icb_rsp_rdata,
  input                          mem_icb_rsp_err,

  // Interrupt output
  output                         dma_irq
);

  sirv_dma #(
    .AW(`E203_ADDR_SIZE),
    .DW(`E203_XLEN)
  ) u_sirv_dma (
    .clk                (clk),
    .rst_n              (rst_n),
    
    // Configuration Interface
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
    
    // Memory Interface
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
    
    // Interrupt
    .dma_irq            (dma_irq)
  );

endmodule
