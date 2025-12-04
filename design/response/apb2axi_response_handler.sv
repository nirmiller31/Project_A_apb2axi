import apb2axi_pkg::*;

module apb2axi_response_handler #(
     parameter int TAG_W        = TAG_W,        // TAG bits
     parameter int DATA_W       = AXI_DATA_W,   // AXI data width (64/128/256...)
     parameter int COMPLETION_W = COMPLETION_W,
     parameter int N_TAG        = (1 << TAG_W),
     parameter int APB_W        = APB_DATA_W    // APB is always 32b
)(
     // ----------------------------
     // PCLK Domain
     // ----------------------------
     input  logic                pclk,
     input  logic                presetn,

     // ----------------------------
     // RDF FIFO (ACLK → PCLK)
     // full AXI beats arriving in arbitrary RID order
     // ----------------------------
     input  logic                rdf_pop_valid,
     input  rdf_entry_t          rdf_pop_payload,
     output logic                rdf_pop_ready,

     // ----------------------------
     // Completion FIFO (ACLK → PCLK)
     // One entry per completed read or write
     // ----------------------------
     input  logic                cq_pop_valid,
     input  logic [COMPLETION_W-1:0] cq_pop_data,
     output logic                cq_pop_ready,

     // ----------------------------
     // APB Data Drain Interface
     // APB requests: "give me the next 32-bit word for this tag"
     // ----------------------------
     input  logic                data_req,        // pulse
     input  logic [TAG_W-1:0]    data_req_tag,

     output logic                data_valid,
     output logic [APB_W-1:0]    data_out,
     output logic                data_last,       // A1: end of full burst

     // ----------------------------
     // Directory completion interface
     // ----------------------------
     output logic                dir_cpl_valid,
     output logic [TAG_W-1:0]    dir_cpl_tag,
     output logic                dir_cpl_is_write,
     output logic [1:0]          dir_cpl_resp,
     output logic                dir_cpl_error,
     output logic [7:0]          dir_cpl_num_beats,
     input  logic                dir_cpl_ready,

     // ----------------------------
     // Regfile completion interface
     // (APB-visible status)
     // ----------------------------
     output logic                rd_status_valid,
     output logic [TAG_W-1:0]    rd_status_tag,
     output logic [7:0]          rd_status_num_beats,
     output logic [1:0]          rd_status_resp,
     output logic                rd_status_error,
     input  logic                rd_status_ready
);

     // =========================================================================
     // 1) Per-tag beat FIFOs (PCLK domain)
     // =========================================================================
     typedef struct packed {
          logic [DATA_W-1:0] data;
          logic [1:0]        resp;
          logic              last;     // AXI RLAST per beat
     } beat_t;

     // per-tag queues stored as dynamic arrays
     beat_t tag_q [N_TAG][$];

     // slicing state per tag
     logic [DATA_W-1:0]               cur_data      [N_TAG];
     logic [$clog2(DATA_W):0]         cur_idx       [N_TAG];   // next bit index
     logic                            cur_valid     [N_TAG];   // is there an active beat being sliced?
     logic                            cur_last_flag [N_TAG];   // does this beat end with AXI RLAST?

     localparam int WORDS_PER_BEAT = DATA_W / APB_W;

     // =========================================================================
     // 2) BLOCK A — STATUS PATH (CQ → DIR + REGS)
     // =========================================================================

     always_ff @(posedge pclk or negedge presetn) begin
          if (!presetn) begin
               dir_cpl_valid   <= 1'b0;
               rd_status_valid <= 1'b0;
               cq_pop_ready    <= 1'b0;
          end
          else begin
               // same ready condition as before
               cq_pop_ready <= dir_cpl_ready && rd_status_ready;
               // cq_pop_ready <= cq_pop_valid && dir_cpl_ready && rd_status_ready;

               // dir_cpl_valid is a pulse
               dir_cpl_valid <= 1'b0;
               // rd_status_valid was intentionally *sticky* in your code,
               // so we do NOT clear it every cycle.

               if (cq_pop_valid && cq_pop_ready) begin
                    completion_entry_t cpl;
                    cpl = cq_pop_data;

                    // → Directory
                    dir_cpl_valid     <= 1'b1;
                    dir_cpl_tag       <= cpl.tag;
                    dir_cpl_is_write  <= cpl.is_write;
                    dir_cpl_resp      <= cpl.resp;
                    dir_cpl_error     <= cpl.error;
                    dir_cpl_num_beats <= cpl.num_beats;

                    // → Regfile only for reads (sticky valid)
                    if (!cpl.is_write) begin
                         rd_status_valid     <= 1'b1;
                         rd_status_tag       <= cpl.tag;
                         rd_status_resp      <= cpl.resp;
                         rd_status_error     <= cpl.error;
                         rd_status_num_beats <= cpl.num_beats;
                    end

                    $display("%t [RH_DBG] STATUS UPDATED rd_status_valid=%0h rd_status_tag=%0h rd_status_resp=%0h rd_status_error=%0h rd_status_num_beats=%0h",
                              $time, rd_status_valid, rd_status_tag, rd_status_resp, rd_status_error, rd_status_num_beats);
               end
          end
     end


     // =========================================================================
     // 3) BLOCK B — DATA PATH (RDF ingest + APB slicing)
     // =========================================================================

     integer t;
     integer tag_idx;                      // decoded data_req_tag
     logic [$clog2(DATA_W):0] next_idx;    // next bit index within current beat

     assign rdf_pop_ready = '1;

     always_ff @(posedge pclk) begin
          if (!presetn) begin
               // Reset: clear slicing state
               for (t = 0; t < N_TAG; t++) begin
                    tag_q[t].delete();
                    cur_data[t]      <= '0;
                    cur_idx[t]       <= '0;
                    cur_valid[t]     <= 1'b0;
                    cur_last_flag[t] <= 1'b0;
               end

               data_valid    <= 1'b0;
               data_last     <= 1'b0;
               // rdf_pop_ready <= 1'b0;
          end
          else begin
               // defaults per-cycle
               data_valid    <= 1'b0;
               data_last     <= 1'b0;

               // rdf_pop_ready <= data_req;

               // ================================================================
               // (A) Handle incoming RDF beats → demux by tag
               // ================================================================
               if (rdf_pop_valid) begin
                    beat_t beat;
                    beat.data = rdf_pop_payload.data;
                    beat.resp = rdf_pop_payload.resp;
                    beat.last = rdf_pop_payload.last;
                    tag_q[rdf_pop_payload.tag].push_back(beat);
               end

               // ================================================================
               // (C) APB Draining request: 32-bit word for tag=T
               // ================================================================
               tag_idx = data_req_tag;
               if (data_req) begin
                    if (!cur_valid[tag_idx]) begin      // If no "current beat" for this TAG, load one
                         if (tag_q[tag_idx].size() > 0) begin
                              beat_t beat;
                              beat = tag_q[tag_idx].pop_front();

                              cur_data[tag_idx]      <= beat.data;
                              cur_idx[tag_idx]       <= 0;          // start slicing at LSBs
                              cur_last_flag[tag_idx] <= beat.last;  // AXI RLAST for this beat
                              cur_valid[tag_idx]     <= 1'b1;
                         end
                    end

                    // If we have valid beat data, slice APB word
                    if (cur_valid[tag_idx]) begin
                         data_out   <= cur_data[tag_idx][cur_idx[tag_idx] +: APB_W];
                         data_valid <= 1'b1;

                         next_idx = cur_idx[tag_idx] + APB_W;

                         if (next_idx == DATA_W) begin   // End of this AXI beat
                         cur_valid[tag_idx] <= 1'b0;

                         if (cur_last_flag[tag_idx] && tag_q[tag_idx].size() == 0)
                              data_last <= 1'b1;      // End of transaction
                         end

                         cur_idx[tag_idx] <= next_idx;
                    end
               end
          end
     end


     // ======================================================================
     // DEBUG BLOCK — PCLK DOMAIN
     // ======================================================================
     always_ff @(posedge pclk) begin
          if (!presetn) begin
               $display("%0t [RH_DBG] RESET asserted", $time);
          end
          else begin
               // A) RDF Incoming beats
               if (rdf_pop_valid && rdf_pop_ready) begin
                    $display("%0t [RH_DBG] RDF_PUSH  tag=%0d  last=%0b  resp=%0d  q_size(next)=%0d",
                         $time,
                         rdf_pop_payload.tag,
                         rdf_pop_payload.last,
                         rdf_pop_payload.resp,
                         tag_q[rdf_pop_payload.tag].size() + 1
                    );
               end

               // B) Completion (CQ)
               if (cq_pop_valid && cq_pop_ready) begin
                    completion_entry_t cpl = cq_pop_data;

                    $display("%0t [RH_DBG] CQ_POP    tag=%0d  is_wr=%0b  beats=%0d  resp=%0d  err=%0b",
                         $time,
                         cpl.tag,
                         cpl.is_write,
                         cpl.num_beats,
                         cpl.resp,
                         cpl.error
                    );

                    $display("[RH_DBG] POP_READY=%0b POP_VALID=%0b",
                         cq_pop_ready,
                         cq_pop_valid
                    );
               end

               // C) APB requesting a word
               if (data_req) begin
                    int t = data_req_tag;

                    $display("%0t [RH_DBG] DATA_REQ tag=%0d cur_valid=%0b cur_idx=%0d q_size=%0d",
                         $time,
                         t,
                         cur_valid[t],
                         cur_idx[t],
                         tag_q[t].size()
                    );
               end

               // D) Slicing events
               for (int t = 0; t < N_TAG; t++) begin
                    if (cur_valid[t]) begin
                         if (data_valid && data_req_tag == t) begin
                         $display("%0t [RH_DBG] SLICE    tag=%0d  idx=%0d  data_out=%h",
                              $time,
                              t,
                              cur_idx[t],
                              data_out
                         );
                         end

                         if (data_last && data_req_tag == t) begin
                         $display("%0t [RH_DBG] DATA_LAST tag=%0d", $time, t);
                         end
                    end
               end
          end
     end

endmodule