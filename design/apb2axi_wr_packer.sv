import apb2axi_pkg::*;

module apb2axi_wr_packer #()(
     input  logic                                pclk,
     input  logic                                presetn,

     // From apb2axi_reg (per-tag write window)
     input  logic                                wr_word_valid,
     input  logic [TAG_W-1:0]                    wr_word_tag,
     input  logic [APB_DATA_W-1:0]               wr_word_data,

     // To write-data FIFO (single stream of ready AXI beats)
     output logic                                wdf_pop_vld,     // change
     output logic [DATA_ENTRY_W-1:0]             wdf_pop_payload,    // change
     input  logic                                wdf_pop_rdy      // change
);

     // ----------------------------------------------------------------
     // Per-TAG pack state: accumulate APB words into one AXI beat
     // ----------------------------------------------------------------
     logic [AXI_DATA_W-1:0]                       pack_data [TAG_NUM];
     logic [$clog2(APB_WORDS_PER_AXI_BEAT+1)-1:0] pack_cnt  [TAG_NUM];

     // one-cycle output staging (so we can honor wdf_pop_rdy)
     logic                                        out_hold;
     wr_entry_t                                   out_ent;

     // drive flat vector
     assign wdf_pop_vld  = out_hold;              // change
     assign wdf_pop_payload = out_ent;               // change

     always_ff @(posedge pclk) begin
          if (!presetn) begin
               for (int t = 0; t < TAG_NUM; t++) begin
                    pack_data[t] <= '0;
                    pack_cnt[t]  <= '0;
               end
               out_hold <= 1'b0;
               out_ent  <= '0;
          end else begin
               // -----------------------------------------
               // If FIFO accepted our staged beat, clear hold
               // -----------------------------------------
               if (out_hold && wdf_pop_rdy) begin
                    out_hold <= 1'b0;
               end

               // -----------------------------------------
               // Accept one incoming APB word (if any)
               // If a beat completes, stage it for FIFO push.
               // If FIFO isn't ready, we HOLD (and DO NOT drop).
               // -----------------------------------------
               if (wr_word_valid) begin
                    int tg;
                    int bit_idx;
                    tg = wr_word_tag;
                    bit_idx = pack_cnt[tg] * APB_DATA_W;

                    // if we are currently holding an unpushed beat, we cannot accept more
                    // (since APB reg currently doesn't stall, you either:
                    //  A) assume wdf_pop_rdy always 1 in sim
                    //  B) later add APB backpressure)
                    if (!out_hold) begin
                         // store this word into pack buffer
                         pack_data[tg][bit_idx +: APB_DATA_W] <= wr_word_data;

                         if (pack_cnt[tg] == APB_WORDS_PER_AXI_BEAT-1) begin
                              // completed a full AXI beat -> stage output
                              wr_entry_t ent;
                              ent.tag   = tg[TAG_W-1:0];
                              ent.last  = 1'b0;       // builder computes true last via LEN tracking
                              ent.wstrb = '1;         // Option-1 for now
                              ent.data  = pack_data[tg];
                              ent.data[bit_idx +: APB_DATA_W] = wr_word_data; // ensure current word included

                              out_ent  <= ent;
                              out_hold <= 1'b1;

                              // reset packer for this tag
                              pack_cnt[tg]  <= '0;
                              pack_data[tg] <= '0;
                         end
                         else begin
                              pack_cnt[tg] <= pack_cnt[tg] + 1'b1;
                         end
                    end
               end
          end
     end

endmodule