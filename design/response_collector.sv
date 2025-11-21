/*------------------------------------------------------------------------------
 * File          : response_collector.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Creation date : Nov 2, 2025
 * Description   : Collects AXI3 responses (R/B), bundles them into completion entries and push them into a completion FIFO.
 *------------------------------------------------------------------------------*/
import apb2axi_pkg::*;

module response_collector #(    
    parameter int TAG_NUM = TAG_NUM,
    parameter int TAG_W = TAG_W
    parameter int DATA_W = APB_DATA_W,
    parameter int FIFO_W = COMPLETION_W,
    parameter int MAX_BEATS_NUM = MAX_BEATS_NUM,
)(
    input  logic                  aclk,
    input  logic                  aresetn,
    //------------------------------
    //AXI Write Response Channel (B)
    //------------------------------
    input  logic [AXI_ID_W-1:0]   bid,
    input  logic   [1:0]          bresp,
    input  logic                  bvalid,
    input  logic                  bready,

    //------------------------------
    //AXI Read Data Response (R)
    //------------------------------ 
    input  logic [AXI_ID_W-1:0]   rid,
    input  logic [AXI_DATA_W-1:0] rdata,
    input  logic [1:0]            rresp,
    input  logic                  rlast,
    input  logic                  rvalid,
    input  logic                  rready,

    //------------------------------
    // Completion FIFO IF (AXI side)
    //------------------------------
    output  logic                       cpl_push_valid; 
    output  logic [COMPLETION_W-1:0]    cpl_push_data;
    input   logic                       cpl_push_ready;




);
endmodule