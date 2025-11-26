/*------------------------------------------------------------------------------
 * File          : apb2axi.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Creation date : Nov 2025
 * Description   : Top-level APB2AXI bridge.
 *                 Current version connects the Gateway (APB-side)
 *                 and exposes a placeholder AXI master interface.
 *------------------------------------------------------------------------------*/

import apb2axi_pkg::*;

module apb2axi #(
     parameter int APB_ADDR_W = APB_ADDR_W,
     parameter int APB_DATA_W = APB_DATA_W,
     parameter int AXI_ADDR_W = AXI_ADDR_W,
     parameter int AXI_DATA_W = AXI_DATA_W,
     parameter int AXI_ID_W   = AXI_ID_W
)(
     // -------------------------
     // APB Slave Interface
     // -------------------------
     input  logic                  PCLK,
     input  logic                  PRESETn,
     input  logic [APB_ADDR_W-1:0] PADDR,
     input  logic [APB_DATA_W-1:0] PWDATA,
     input  logic                  PWRITE,
     input  logic                  PSEL,
     input  logic                  PENABLE,
     output logic [APB_DATA_W-1:0] PRDATA,
     output logic                  PREADY,
     output logic                  PSLVERR,

     // -------------------------
     // AXI Master Interface (AXI3)
     // -------------------------
     input  logic                  ACLK,
     input  logic                  ARESETn,

     // Write Address Channel
     output logic [AXI_ID_W-1:0]   AWID,
     output logic [AXI_ADDR_W-1:0] AWADDR,
     output logic [3:0]            AWLEN,
     output logic [2:0]            AWSIZE,
     output logic [1:0]            AWBURST,
     output logic                  AWLOCK,
     output logic [3:0]            AWCACHE,
     output logic [2:0]            AWPROT,
     output logic                  AWVALID,
     input  logic                  AWREADY,

     // Write Data Channel
     output logic [AXI_DATA_W-1:0] WDATA,
     output logic [AXI_DATA_W/8-1:0] WSTRB,
     output logic                  WLAST,
     output logic                  WVALID,
     input  logic                  WREADY,

     // Write Response Channel
     input  logic [3:0]            BID,
     input  logic [1:0]            BRESP,
     input  logic                  BVALID,
     output logic                  BREADY,

     // Read Address Channel
     output logic [3:0]            ARID,
     output logic [AXI_ADDR_W-1:0] ARADDR,
     output logic [3:0]            ARLEN,
     output logic [2:0]            ARSIZE,
     output logic [1:0]            ARBURST,
     output logic                  ARLOCK,
     output logic [3:0]            ARCACHE,
     output logic [2:0]            ARPROT,
     output logic                  ARVALID,
     input  logic                  ARREADY,

     // Read Data Channel
     input  logic [3:0]            RID,
     input  logic [AXI_DATA_W-1:0] RDATA,
     input  logic [1:0]            RRESP,
     input  logic                  RLAST,
     input  logic                  RVALID,
     output logic                  RREADY
);

     // ============================================================
     // Internal wiring from Gateway (APB side)
     // ============================================================
     logic                  dir_pending_valid;
     directory_entry_t      dir_pending_entry;
     logic [TAG_W-1:0]      dir_pending_tag;
     logic                  dir_pending_pop;

     logic             dir_cpl_valid;
     logic [TAG_W-1:0] dir_cpl_tag;
     logic             dir_cpl_is_write;
     logic             dir_cpl_error;
     logic [1:0]       dir_cpl_resp;
     logic [7:0]       dir_cpl_num_beats;

     // ============================================================
     // Instantiate Gateway (APB side = reg + directory)
     // ============================================================
     apb2axi_gateway #(
          .AXI_ADDR_W    (AXI_ADDR_W),
          .APB_ADDR_W    (APB_ADDR_W)
     ) u_apb2axi_gateway (
          .PCLK          (PCLK),
          .PRESETn       (PRESETn),
          .PSEL          (PSEL),
          .PENABLE       (PENABLE),
          .PWRITE        (PWRITE),
          .PADDR         (PADDR),
          .PWDATA        (PWDATA),
          .PREADY        (PREADY),
          .PSLVERR       (PSLVERR),

          .dir_pending_valid (dir_pending_valid),
          .dir_pending_entry (dir_pending_entry),
          .dir_pending_tag   (dir_pending_tag),
          .dir_pending_pop   (dir_pending_pop),

          .dir_cpl_valid     (dir_cpl_valid),
          .dir_cpl_tag       (dir_cpl_tag),
          .dir_cpl_is_write  (dir_cpl_is_write),
          .dir_cpl_error     (dir_cpl_error),
          .dir_cpl_resp      (dir_cpl_resp),
          .dir_cpl_num_beats (dir_cpl_num_beats)
     );

     // ============================================================
     // Internal wiring for Write FIFO
     // ============================================================

     logic                 wr_push_valid;
     logic                 wr_push_ready;
     logic [REQ_WIDTH-1:0] wr_push_data;

     logic                 wr_pop_valid;
     logic                 wr_pop_ready;
     logic [REQ_WIDTH-1:0] wr_pop_data;

     directory_entry_t     wr_entry_out;

     // assign wr_push_valid = commit_pulse & gw_entry.is_write;
     // assign wr_push_data  = gw_entry;

     // ============================================================
     // Instantiate Write_FIFO
     // ============================================================
     apb2axi_fifo #(
          .WIDTH(REQ_WIDTH)
     ) u_wr_apb2axi_fifo (
          .clk        (ACLK),
          .resetn     (ARESETn),

          .push_valid (wr_push_valid),
          .push_ready (wr_push_ready),
          .push_data  (wr_push_data),

          .pop_valid  (wr_pop_valid),
          .pop_ready  (wr_pop_ready),
          .pop_data   (wr_pop_data)
     );

     // ============================================================
     // Internal wiring for Read FIFO
     // ============================================================
     logic                 rd_push_valid;
     logic                 rd_push_ready;
     logic [REQ_WIDTH-1:0] rd_push_data;

     logic                 rd_pop_valid;
     logic                 rd_pop_ready;
     logic [REQ_WIDTH-1:0] rd_pop_data;

     directory_entry_t     rd_entry_out;

     // assign rd_push_valid = commit_pulse & ~gw_entry.is_write;
     // assign rd_push_data  = gw_entry;

     // ============================================================
     // Instantiate Write_FIFO
     // ============================================================
     apb2axi_fifo #(
          .WIDTH(REQ_WIDTH)
     ) u_rd_apb2axi_fifo (
          .clk        (ACLK),
          .resetn     (ARESETn),

          .push_valid (rd_push_valid),
          .push_ready (rd_push_ready),
          .push_data  (rd_push_data),

          .pop_valid  (rd_pop_valid),
          .pop_ready  (rd_pop_ready),
          .pop_data   (rd_pop_data)
     );

     assign rd_pop_ready = 1'b1;             // FIXME later

     // --------------------------------------------------------------------
     // Builders: consume FIFO, drive AXI
     // --------------------------------------------------------------------

     apb2axi_write_builder #(
          .AXI_ADDR_W   (AXI_ADDR_W),
          .AXI_DATA_W   (AXI_DATA_W),
          .AXI_ID_W     (AXI_ID_W),
          .FIFO_ENTRY_W (REQ_WIDTH)
     ) u_wr_builder (
          .aclk         (ACLK),
          .aresetn      (ARESETn),

          .wr_pop_valid (wr_pop_valid),
          .wr_pop_ready (wr_pop_ready),
          .wr_pop_data  (wr_pop_data),

          .awid         (AWID),
          .awaddr       (AWADDR),
          .awlen        (AWLEN),
          .awsize       (AWSIZE),
          .awburst      (AWBURST),
          .awlock       (AWLOCK),
          .awcache      (AWCACHE),
          .awprot       (AWPROT),
          .awvalid      (AWVALID),
          .awready      (AWREADY),

          .wdata        (WDATA),
          .wstrb        (WSTRB),
          .wlast        (WLAST),
          .wvalid       (WVALID),
          .wready       (WREADY)
          // ,

          // .bid          (BID),
          // .bresp        (BRESP),
          // .bvalid       (BVALID),
          // .bready       (BREADY)
     );

     logic rready_builder;
     assign RREADY = rready_builder;

     apb2axi_read_builder #(
          .AXI_ADDR_W   (AXI_ADDR_W),
          .AXI_DATA_W   (AXI_DATA_W),
          .AXI_ID_W     (AXI_ID_W),
          .FIFO_ENTRY_W (REQ_WIDTH)
     ) u_rd_builder (
          .aclk         (ACLK),
          .aresetn      (ARESETn),

          .rd_pop_valid (rd_pop_valid),
          .rd_pop_ready ('1), //(rd_pop_ready),
          .rd_pop_data  (rd_pop_data),

          .arid         (ARID),
          .araddr       (ARADDR),
          .arlen        (ARLEN),
          .arsize       (ARSIZE),
          .arburst      (ARBURST),
          .arlock       (ARLOCK),
          .arcache      (ARCACHE),
          .arprot       (ARPROT),
          .arvalid      (ARVALID),
          .arready      (ARREADY),

          .rid          (RID),
          .rdata        (RDATA),
          .rresp        (RRESP),
          .rlast        (RLAST),
          .rvalid       (RVALID),
          .rready       (rready_builder)
     );

     // ============================================================
    // Transaction Manager : route gateway entries to WR/RD FIFOs
    // ============================================================
     apb2axi_txn_mgr #(
          .FIFO_ENTRY_W(REQ_WIDTH)
     ) u_txn_mgr (
          .aclk          (ACLK),
          .aresetn       (ARESETn),

          .pending_valid (dir_pending_valid),
          .pending_entry (dir_pending_entry),
          .pending_tag   (dir_pending_tag),
          .pending_pop   (dir_pending_pop),

          .wr_push_valid (wr_push_valid),
          .wr_push_ready (wr_push_ready),
          .wr_push_data  (wr_push_data),

          .rd_push_valid (rd_push_valid),
          .rd_push_ready (rd_push_ready),
          .rd_push_data  (rd_push_data)
     );

     // ============================================================
     // Completion Queue (CQ) between response_collector and handler
     // ============================================================
     logic                    cq_push_valid;
     logic                    cq_push_ready;
     logic [COMPLETION_W-1:0] cq_push_data;

     logic                    cq_pop_valid;
     logic                    cq_pop_ready;
     logic [COMPLETION_W-1:0] cq_pop_data;

     // ============================================================
     // Completion FIFO (CQ)
     // ============================================================
     apb2axi_fifo #(
          .WIDTH      (COMPLETION_W)
     ) u_cq_fifo (
          .clk        (ACLK),
          .resetn     (ARESETn),

          .push_valid (cq_push_valid),
          .push_ready (cq_push_ready),
          .push_data  (cq_push_data),

          .pop_valid  (cq_pop_valid),
          .pop_ready  (cq_pop_ready),
          .pop_data   (cq_pop_data)
     );

     apb2axi_response_collector #(
          .AXI_ID_W      (AXI_ID_W),
          .TAG_W_P       (TAG_W),
          .COMPLETION_WP (COMPLETION_W)
     ) u_resp_collector (
          .aclk          (ACLK),
          .aresetn       (ARESETn),

          // AXI B channel
          .bid           (BID),
          .bresp         (BRESP),
          .bvalid        (BVALID),
          .bready        (BREADY),   // top-level BREADY now comes from here

          // AXI R channel
          .rid                (RID),
          .rdata              (RDATA),
          .rresp              (RRESP),
          .rlast              (RLAST),
          .rvalid             (RVALID),
          .rready             (rready_builder),   // top-level RREADY now comes from here

          .rdf_push_valid     (rdf_push_valid),
          .rdf_push_payload   (rdf_push_payload),
          .rdf_push_ready     (rdf_push_ready),

          // CQ write side
          .cpl_push_valid     (cq_push_valid),
          .cpl_push_ready     (cq_push_ready),
          .cpl_push_data      (cq_push_data)
     );

     apb2axi_response_handler #(
          .TAG_W_P            (TAG_W),
          .COMPLETION_WP      (COMPLETION_W)
     ) u_resp_handler (
          .pclk               (PCLK),
          .presetn            (PRESETn),

          .cq_pop_valid       (cq_pop_valid),
          .cq_pop_ready       (cq_pop_ready),
          .cq_pop_data        (cq_pop_data),

          .dir_cpl_valid      (dir_cpl_valid),
          .dir_cpl_tag        (dir_cpl_tag),
          .dir_cpl_error      (dir_cpl_error),
          .dir_cpl_resp       (dir_cpl_resp),
          .dir_cpl_num_beats  (dir_cpl_num_beats),
          .dir_cpl_is_write   (dir_cpl_is_write), 
          .dir_cpl_ready      ('1)
     );

     // ============================================================
     // RDF (Read Data FIFO) wiring
     // ============================================================
     logic        rdf_push_valid;
     rdf_entry_t  rdf_push_payload;
     logic        rdf_push_ready;

     // APB-side consumer (we’ll just park it for now)
     logic                     rdf_data_req;
     logic [TAG_W-1:0]         rdf_data_req_tag;
     logic                     rdf_data_valid;
     logic [AXI_DATA_W-1:0]    rdf_data_out;
     logic                     rdf_data_last;

     assign rdf_data_req     = dir_cpl_valid && !dir_cpl_is_write;
     assign rdf_data_req_tag = dir_cpl_tag;

     apb2axi_rdf #(
          .RDF_W_P  (RDF_W),
          .TAG_W_P  (TAG_W),
          .DATA_W_P (AXI_DATA_W)
     ) u_rdf (
          // AXI/ACLK side
          .ACLK           (ACLK),
          .ARESETn        (ARESETn),
          .rdf_push_valid (rdf_push_valid),
          .rdf_push_payload(rdf_push_payload),
          .rdf_push_ready (rdf_push_ready),

          // APB/PCLK side
          .PCLK           (PCLK),
          .PRESETn        (PRESETn),

          .data_req       (rdf_data_req),
          .data_req_tag   (rdf_data_req_tag),
          .data_valid     (rdf_data_valid),
          .data_out       (rdf_data_out),
          .data_last      (rdf_data_last)
     );


endmodule
