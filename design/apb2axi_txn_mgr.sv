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
     input  logic                       aclk,
     input  logic                       aresetn,

     // From Gateway (directory entry at commit time)
     input  logic                       pending_valid,
     input  directory_entry_t           pending_entry,
     input  logic [TAG_W-1:0]           pending_tag,
     output logic                       pending_pop,

     // To WRITE request FIFO
     output logic                       wr_push_valid,
     input  logic                       wr_push_ready,
     output logic [FIFO_ENTRY_W-1:0]    wr_push_data,

     // To READ request FIFO
     output logic                       rd_push_valid,
     input  logic                       rd_push_ready,
     output logic [FIFO_ENTRY_W-1:0]    rd_push_data

);

     // Packed view of the directory entry
     logic [FIFO_ENTRY_W-1:0] entry_packed;
     assign entry_packed = pending_entry;

     // Simple combinational dispatcher
     always_comb begin
          // Defaults
          pending_pop   = 1'b0;
          wr_push_valid = 1'b0;
          rd_push_valid = 1'b0;
          wr_push_data  = '0;
          rd_push_data  = '0;

          if (pending_valid) begin
               if (pending_entry.is_write) begin
                    // Write request -> WR FIFO
                    if (wr_push_ready) begin
                         wr_push_valid = 1'b1;
                         wr_push_data  = entry_packed;
                         pending_pop   = 1'b1;
                    end
               end else begin
                    // Read request -> RD FIFO
                    if (rd_push_ready) begin
                         rd_push_valid = 1'b1;
                         rd_push_data  = entry_packed;
                         pending_pop   = 1'b1;
                    end
               end
          end
     end

     // No sequential state yet – room for future credits / scheduling
     // always_ff @(posedge aclk or negedge aresetn) begin
     // end

     // Optional debug
     // synthesis translate_off
     always_ff @(posedge aclk) begin
          if (pending_valid && pending_pop) begin
               $display("%t [TXN_MGR] TAG=%0d -> %s FIFO", $time, pending_tag, pending_entry.is_write ? "WR" : "RD");
          end
          if (pending_valid && !pending_pop) begin
               $display("%t [TXN_MGR] BLOCKED pending_valid=1 is_write=%0b wr_ready=%0b rd_ready=%0b", $time, pending_entry.is_write, wr_push_ready, rd_push_ready);
          end
     end
     // synthesis translate_on

endmodule