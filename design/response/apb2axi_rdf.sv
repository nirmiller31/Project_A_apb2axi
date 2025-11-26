//------------------------------------------------------------------------------
// apb2axi_rdf.sv
// Read Data FIFO: stores per-beat R data tagged by TAG.
//  - AXI/ACLK side: push interface from response_collector
//  - APB/PCLK side: TAG-aware "give me next beat for TAG" interface
//
// Phase 1: assumes single ID / non-interleaved bursts,
//          implemented as simple FIFO. data_req_tag is ignored,
//          but kept in the interface for future multi-ID support.
//------------------------------------------------------------------------------

import apb2axi_pkg::*;

module apb2axi_rdf #(
     parameter int RDF_W_P  = RDF_W,
     parameter int TAG_W_P  = TAG_W,
     parameter int DATA_W_P = AXI_DATA_W
)(
     // AXI side
     input  logic                ACLK,
     input  logic                ARESETn,
     input  logic                rdf_push_valid,
     input  rdf_entry_t          rdf_push_payload,
     output logic                rdf_push_ready,

     // APB side
     input  logic                PCLK,
     input  logic                PRESETn,

     // APB consumer: request "next beat for TAG"
     input  logic                data_req,       // 1-cycle pulse or level
     input  logic [TAG_W_P-1:0]  data_req_tag,   // for future interleaving

     output logic                data_valid,
     output logic [DATA_W_P-1:0] data_out,
     output logic                data_last
);

     // Phase 1: assume aclk == pclk and aresetn == presetn.
     // FIXME when clocks differ, replace this FIFO with a proper async FIFO later.

     // Flattened FIFO signals
     logic [RDF_W_P-1:0] push_data_flat;
     logic [RDF_W_P-1:0] pop_data_flat;
     logic               push_ready;
     logic               pop_valid;
     logic               pop_ready;

     assign push_data_flat = rdf_push_payload;
     assign rdf_push_ready = push_ready;

     rdf_entry_t pop_payload;

     assign pop_payload = pop_data_flat;

     apb2axi_fifo #(
          .ENTRY_WIDTH(RDF_W_P)
     ) u_rdf_fifo (
          .clk        (ACLK),      // = pclk for now
          .resetn     (ARESETn),   // = presetn
          .push_valid (rdf_push_valid),
          .push_data  (push_data_flat),
          .push_ready (push_ready),
          .pop_ready  (pop_ready),
          .pop_valid  (pop_valid),
          .pop_data   (pop_data_flat)
     );

     // Simple consumer: ignore data_req_tag in phase 1,
     // just pop in order when data_req is asserted.
     always_ff @(posedge PCLK) begin
          if (!PRESETn) begin
               data_valid <= 1'b0;
               data_out   <= '0;
               data_last  <= 1'b0;
               pop_ready  <= 1'b0;
          end
          else begin
               data_valid <= 1'b0;
               pop_ready  <= 1'b0;

               if (data_req && pop_valid) begin
                    data_out   <= pop_payload.data;
                    data_last  <= pop_payload.last;
                    data_valid <= 1'b1;
                    pop_ready  <= 1'b1;
                    // FIXME interleave handling: check pop_payload.tag == data_req_tag
               end
          end
     end

endmodule