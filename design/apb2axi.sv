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

     logic [TAG_W-1:0] status_tag_sel;
     directory_entry_t status_dir_entry;
     entry_state_e status_dir_state;



     logic                 rdf_push_valid;
     rdf_entry_t           rdf_push_payload;
     logic                 rdf_push_ready;

     logic                 rdf_pop_valid;
     rdf_entry_t           rdf_pop_payload;
     logic                 rdf_pop_ready;

     logic                    cq_push_valid;
     logic                    cq_push_ready;
     logic [COMPLETION_W-1:0] cq_push_data;

     logic                    cq_pop_valid;
     logic                    cq_pop_ready;
     logic [COMPLETION_W-1:0] cq_pop_data;

     // =========================================================================
     // 1. REGFILE
     // =========================================================================
     logic commit_pulse;
     logic [AXI_ADDR_W-1:0] addr;
     logic [7:0]            len;
     logic [2:0]            size;
     logic                  is_write;

     // From handler to regfile
     logic rd_status_valid, rd_status_error, rd_status_is_write;
     logic [1:0] rd_status_resp;
     logic [TAG_W-1:0] rd_status_tag;
     logic [7:0] rd_status_num_beats;
     logic        rsp_data_req;
     logic [TAG_W-1:0] rsp_data_req_tag;
     logic        rsp_data_valid;
     logic          rsp_data_ready;
     logic [APB_DATA_W-1:0] rsp_data_out;
     logic        rsp_data_last;

     logic                  rdf_data_valid;
     logic                  rdf_data_ready;
     logic [APB_DATA_W-1:0] rdf_data_out;
     logic                  rdf_data_last;

     logic                  rdf_data_req;
     logic [TAG_W-1:0]      rdf_data_req_tag;

     // From regfile to directory
     logic dir_cons_valid;

     apb2axi_reg u_reg (
          .pclk(PCLK), .presetn(PRESETn),
          .psel(PSEL), .penable(PENABLE), .pwrite(PWRITE),
          .paddr(PADDR), .pwdata(PWDATA),
          .prdata(PRDATA), .pready(PREADY), .pslverr(PSLVERR),

          .commit_pulse(commit_pulse),
          .addr(addr), .len(len), .size(size), .is_write(is_write),

          .rd_status_valid(rd_status_valid),
          .rd_status_error(rd_status_error),
          .rd_status_resp(rd_status_resp),
          .rd_status_tag(rd_status_tag),
          .rd_status_num_beats(rd_status_num_beats),
          .rd_status_is_write(rd_status_is_write),

          .rdf_data_valid(rdf_data_valid),
          .rdf_data_ready(rdf_data_ready),
          .rdf_data_out(rdf_data_out),
          .rdf_data_last(rdf_data_last),
          .rdf_data_req(rdf_data_req),
          .rdf_data_req_tag(rdf_data_req_tag),

          .dir_consumed_valid(dir_cons_valid),

          .status_tag_sel(status_tag_sel),
          .status_dir_entry(status_dir_entry),
          .status_dir_state(status_dir_state)
     );

     // =========================================================================
     // 2. DIRECTORY
     // =========================================================================
     logic dir_alloc_valid, dir_alloc_ready;
     logic [TAG_W-1:0] dir_alloc_tag;
     directory_entry_t dir_alloc_entry;

     logic dir_pop_valid, dir_pop_ready;
     directory_entry_t dir_pop_entry;
     logic [TAG_W-1:0] dir_pop_tag;

     // From handler
     logic dir_cpl_valid, dir_cpl_ready;
     logic [TAG_W-1:0] dir_cpl_tag;
     logic dir_cpl_error, dir_cpl_is_write;
     logic [1:0] dir_cpl_resp;
     logic [7:0] dir_cpl_num_beats;

     apb2axi_directory u_directory (
          .pclk(PCLK), 
          .presetn(PRESETn),

          // ALLOC
          .alloc_valid(dir_alloc_valid),
          .alloc_entry(dir_alloc_entry),
          .alloc_ready(dir_alloc_ready),
          .alloc_tag(dir_alloc_tag),

          // POP → txn_mgr
          .dir_pop_valid(dir_pop_valid),
          .dir_pop_entry(dir_pop_entry),
          .dir_pop_tag(dir_pop_tag),
          .dir_pop_ready(dir_pop_ready),

          // COMPLETION → COMPLETE
          .dir_cpl_valid(dir_cpl_valid),
          .dir_cpl_tag(dir_cpl_tag),
          .dir_cpl_is_write(dir_cpl_is_write),
          .dir_cpl_error(dir_cpl_error),
          .dir_cpl_resp(dir_cpl_resp),
          .dir_cpl_num_beats(dir_cpl_num_beats),
          .dir_cpl_ready(dir_cpl_ready),

          // APB CONSUME → EMPTY
          .dir_consumed_valid(dir_cons_valid),

          .status_tag_sel(status_tag_sel),
          .status_dir_entry(status_dir_entry),
          .status_dir_state(status_dir_state)
     );

     always_comb begin
          dir_alloc_valid           = commit_pulse;
          dir_alloc_entry.addr      = addr;
          dir_alloc_entry.len       = len;
          dir_alloc_entry.size      = size;
          dir_alloc_entry.is_write  = is_write;
          dir_alloc_entry.tag       = '0;
     end

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
          .rd_pop_ready (rd_pop_ready),
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

          .pending_valid (dir_pop_valid),
          .pending_entry (dir_pop_entry),
          .pending_tag   (dir_pop_tag),
          .pending_pop   (dir_pop_ready),

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

     apb2axi_fifo_async #(
          .WIDTH(COMPLETION_W)
     ) u_cq_fifo (
          .wr_clk   (ACLK),
          .wr_resetn(ARESETn),
          .wr_valid (cq_push_valid),
          .wr_data  (cq_push_data),
          .wr_ready (cq_push_ready),

          .rd_clk   (PCLK),
          .rd_resetn(PRESETn),
          .rd_valid (cq_pop_valid),
          .rd_data  (cq_pop_data),
          .rd_ready (cq_pop_ready)
     );

     // ============================================================
     // Completion FIFO (CQ)
     // ============================================================

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


     // handler
     apb2axi_response_handler u_handler (
          // PCLK
          .pclk(PCLK),
          .presetn(PRESETn),

          // RDF FIFO output
          .rdf_pop_valid(rdf_pop_valid),
          .rdf_pop_payload(rdf_pop_payload),
          .rdf_pop_ready(rdf_pop_ready),

          // CQ FIFO output
          .cq_pop_valid(cq_pop_valid),
          .cq_pop_data(cq_pop_data),
          .cq_pop_ready(cq_pop_ready),

          // APB drain
          .data_req(rsp_data_req),
          .data_req_tag(rsp_data_req_tag),
          .data_ready(rsp_data_ready),
          .data_valid(rsp_data_valid),
          .data_out(rsp_data_out),
          .data_last(rsp_data_last),

          // Directory completion
          .dir_cpl_valid(dir_cpl_valid),
          .dir_cpl_tag(dir_cpl_tag),
          .dir_cpl_is_write(dir_cpl_is_write),
          .dir_cpl_resp(dir_cpl_resp),
          .dir_cpl_error(dir_cpl_error),
          .dir_cpl_num_beats(dir_cpl_num_beats),
          .dir_cpl_ready(1'b1),

          // Regfile completion
          .rd_status_valid(rd_status_valid),
          .rd_status_tag(rd_status_tag),
          .rd_status_num_beats(rd_status_num_beats),
          .rd_status_resp(rd_status_resp),
          .rd_status_error(rd_status_error),
          .rd_status_ready(1'b1)
     );

     // Bridge regfile <-> handler RDF signals (same clock domain: PCLK)
     assign rsp_data_req      = rdf_data_req;
     assign rsp_data_req_tag  = rdf_data_req_tag;

     assign rdf_data_valid    = rsp_data_valid;
     assign rsp_data_ready    = rdf_data_ready;
     assign rdf_data_out      = rsp_data_out;
     assign rdf_data_last     = rsp_data_last;

     apb2axi_fifo_async #(
          .WIDTH($bits(rdf_entry_t))
     ) u_rdf_fifo (
          .wr_clk   (ACLK),
          .wr_resetn(ARESETn),
          .wr_valid (rdf_push_valid),
          .wr_data  (rdf_push_payload),
          .wr_ready (rdf_push_ready),

          .rd_clk   (PCLK),
          .rd_resetn(PRESETn),
          .rd_valid (rdf_pop_valid),
          .rd_data  (rdf_pop_payload),
          .rd_ready (rdf_pop_ready)
     );

endmodule
