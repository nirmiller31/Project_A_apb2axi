

import apb2axi_pkg::*;

module apb2axi_directory #()(
     input  logic                       pclk,
     input  logic                       presetn,

     input  logic                       reg_dir_alloc_vld,            // new descriptor available
     input  directory_entry_t           reg_dir_alloc_entry,          // descriptor
     output logic                       reg_dir_alloc_rdy,            // can accept?

     input  logic                       reg_dir_entry_consumed,       // APB says: done with this TAG (consumed)

     input  logic [TAG_W-1:0]           reg_dir_tag_sel,              // which TAG to inspect (status read)
     output directory_entry_t           reg_dir_entry,
     output entry_state_e               reg_dir_entry_state,

     output logic                       dir_mgr_pop_vld,              // We have an entry ready to FIFO'ed
     output directory_entry_t           dir_mgr_pop_entry,            // The ready entry
     input  logic                       dir_mgr_pop_rdy,              // FIFO can accept

     input  logic                       cq_dir_cpl_vld,               // Txn stored in handler, all beats recieved from AXI
     input  completion_entry_t          cq_dir_cpl_entry,             // The completion entry
     output logic                       cq_dir_cpl_rdy

);

     // =============================================================
     // Entry state machine
     // =============================================================

     entry_state_e                      state [DIR_ENTRIES];
     directory_entry_t                  entry [DIR_ENTRIES];

     logic                              found_alloc;
     logic [TAG_W-1:0]                  oldest_tag;

     logic [TAG_W-1:0]                  next_free_ptr;

     always_comb begin
          reg_dir_alloc_rdy             = (state[next_free_ptr] == ST_EMPTY);    // Free entry detection

          dir_mgr_pop_vld               = found_alloc;
          dir_mgr_pop_entry             = entry[oldest_tag];

          reg_dir_entry                 = entry[reg_dir_tag_sel];
          reg_dir_entry_state           = state[reg_dir_tag_sel];
     end

     // =============================================================
     // State Handling block
     // =============================================================
     always_ff @(posedge pclk) begin
          if (!presetn) begin
               next_free_ptr                                <= '0;
               cq_dir_cpl_rdy                               <= '1;
               for (int i = 0; i < DIR_ENTRIES; i++) begin
                    state[i]                                <= ST_EMPTY;
                    entry[i]                                <= '0;
               end
          end
          else begin
               if (reg_dir_alloc_vld && reg_dir_alloc_rdy) begin                        // EMPTY -> ALLOCATED (commited vie regs)
                    entry[next_free_ptr]                    <= reg_dir_alloc_entry;
                    entry[next_free_ptr].tag                <= next_free_ptr;
                    state[next_free_ptr]                    <= ST_ALLOCATED;
                    next_free_ptr                           <= next_free_ptr + 1'b1;
               end
               if (dir_mgr_pop_vld && dir_mgr_pop_rdy) begin                          // ALLOCATED -> PENDING (once popped to FIFO)
                    state[oldest_tag]                       <= ST_PENDING;
               end
               if (cq_dir_cpl_vld && cq_dir_cpl_rdy) begin
                    state[cq_dir_cpl_entry.tag]             <= ST_COMPLETE;               // PENDING -> COMPLETE (after all data recieved)
                    entry[cq_dir_cpl_entry.tag].resp        <= cq_dir_cpl_entry.resp;
                    entry[cq_dir_cpl_entry.tag].num_beats   <= cq_dir_cpl_entry.num_beats;
                    entry[cq_dir_cpl_entry.tag].state       <= cq_dir_cpl_entry.error ? DIR_ST_ERROR : DIR_ST_DONE;
               end
               if (reg_dir_entry_consumed & state[reg_dir_tag_sel] == ST_COMPLETE) begin  // COMPLETE -> EMPTY (all consumed, can be cleared)
                    state[reg_dir_tag_sel]                  <= ST_EMPTY;
                    entry[reg_dir_tag_sel]                  <= '0;
               end
          end
     end

     // =============================================================
     // POP block (ALLOCATED -> PENDING)
     // Scan for oldest ALLOCATED entry
     // =============================================================
     always_comb begin
          found_alloc                   = 1'b0;
          oldest_tag                    = '0;
          for (int i = 0; i < DIR_ENTRIES; i++) begin       // Simple linear scan for now
               if (state[i] == ST_ALLOCATED && !found_alloc) begin
                    found_alloc         = 1'b1;
                    oldest_tag          = i;
               end
          end
     end


// ==========================================================================================================================
// =================================================== DEBUG infra ==========================================================
// ==========================================================================================================================

     bit dir_debug_en;

     initial begin
          dir_debug_en = $test$plusargs("APB2AXI_DIR_DEBUG");
          if (dir_debug_en)
               $display("%t [DIR_DBG] Directory debug ENABLED (+APB2AXI_DIR_DEBUG)", $time);
     end

     function automatic string state2str(entry_state_e s);
          case (s)
               ST_EMPTY:     return "EMPTY   ";
               ST_ALLOCATED: return "ALLOC   ";
               ST_PENDING:   return "PENDING ";
               ST_COMPLETE:  return "COMPLETE";
               default:      return "UNKNOWN ";
          endcase
     endfunction

     task automatic dir_dump(string reason = "");
          if (!dir_debug_en) return;

          $display("%t [DIR_DUMP] ---- Directory dump (%s) ----", $time, reason);
          for (int i = 0; i < DIR_ENTRIES; i++) begin
               $display("  idx=%0d state=%s tag=%0d addr=%h len=%0d size=%0d is_wr=%0b resp=%0d beats=%0d",
                        i,
                        state2str(state[i]),
                        entry[i].tag,
                        entry[i].addr,
                        entry[i].len,
                        entry[i].size,
                        entry[i].is_write,
                        entry[i].resp,
                        entry[i].num_beats);
          end
          $display("%t [DIR_DUMP] ---------------------------------", $time);
     endtask

     // =============================================================
     // PER-CYCLE DIRECTORY DUMP (when enabled)
     // =============================================================
     always_ff @(posedge pclk) begin
          if (dir_debug_en) begin
               if (!presetn)
                    dir_dump("RESET");
               else
                    dir_dump("CYCLE");
          end
     end

// ==========================================================================================================================
// ==========================================================================================================================
// ==========================================================================================================================



endmodule