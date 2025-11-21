/*------------------------------------------------------------------------------
 * File          : apb2axi_txn_mgr.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Description   : Simple Transaction Manager
 *                 - Takes committed gateway entries
 *                 - Routes writes to WR FIFO, reads to RD FIFO
 *                 - All logic is in AXI clock domain (for now we assume
 *                   PCLK == ACLK; proper CDC can be added later).
 *------------------------------------------------------------------------------*/

import apb2axi_pkg::*;

module apb2axi_txn_mgr #(
     parameter int FIFO_ENTRY_W = REQ_WIDTH
)(
     input  logic                     aclk,
     input  logic                     aresetn,

     // From Gateway (directory entry at commit time)
     input  logic                     commit_pulse,
     input  directory_entry_t         gw_entry,

     // To WRITE request FIFO
     output logic                     wr_push_valid,
     input  logic                     wr_push_ready,
     output logic [FIFO_ENTRY_W-1:0]  wr_push_data,

     // To READ request FIFO
     output logic                     rd_push_valid,
     input  logic                     rd_push_ready,
     output logic [FIFO_ENTRY_W-1:0]  rd_push_data

     // Future hooks:
     // - inputs from B/R channels for outstanding counters
     // - backpressure to APB (PREADY) via gateway
);

     // Simple pass-through routing for now:
     // write entries -> WR FIFO, read entries -> RD FIFO.
     // Later we can add credits / outstanding limit / arbitration.

     // Pack struct into FIFO word
     wire [FIFO_ENTRY_W-1:0] entry_packed = gw_entry;

     always_comb begin
          // defaults
          wr_push_valid = 1'b0;
          wr_push_data  = '0;
          rd_push_valid = 1'b0;
          rd_push_data  = '0;

          if (commit_pulse) begin
               if (gw_entry.is_write) begin
                    wr_push_valid = 1'b1;
                    wr_push_data  = entry_packed;
                    // we ignore wr_push_ready for now – backpressure TBD
               end else begin
                    rd_push_valid = 1'b1;
                    rd_push_data  = entry_packed;
                    // similarly, ignore rd_push_ready for now
               end
          end
     end

     // No sequential state yet – reserved for future credits/scoreboard
     // always_ff @(posedge aclk or negedge aresetn) begin
     // end

endmodule
