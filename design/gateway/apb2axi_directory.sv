

import apb2axi_pkg::*;

module apb2axi_directory #(
     parameter int TAG_NUM_P = TAG_NUM,
     parameter int TAG_W_P   = TAG_W
)(
     input  logic                       pclk,
     input  logic                       presetn,

     input  logic                       alloc_valid,       // new descriptor available
     input  directory_entry_t           alloc_entry,       // descriptor
     output logic                       alloc_ready,       // can accept?
     output logic [TAG_W_P-1:0]         alloc_tag,         // assigned TAG
     // txn_mgr signals
     output logic                       dir_pop_valid,
     output directory_entry_t           dir_pop_entry,
     output logic [TAG_W_P-1:0]         dir_pop_tag,
     input  logic                       dir_pop_ready,

     input  logic                       dir_cpl_valid,
     input  logic [TAG_W_P-1:0]         dir_cpl_tag,
     input  logic                       dir_cpl_is_write,
     input  logic                       dir_cpl_error,
     input  logic [1:0]                 dir_cpl_resp,
     input  logic [7:0]                 dir_cpl_num_beats,
     output logic                       dir_cpl_ready,

     input  logic                       dir_consumed_valid, // APB says: done with this TAG

     input  logic [TAG_W_P-1:0]         status_tag_sel,   // which TAG to inspect
     output directory_entry_t           status_dir_entry,
     output entry_state_e               status_dir_state
);

     // =============================================================
     // Entry state machine
     // =============================================================

     entry_state_e                      state [DIR_ENTRIES];
     directory_entry_t                  entry [DIR_ENTRIES];

     logic [TAG_W_P-1:0]                next_free_ptr;
     assign alloc_ready                 = (state[next_free_ptr] == ST_EMPTY);    // Free entry detection


     // =============================================================
     // DEBUG infra
     // =============================================================
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
     // ALLOCATION block
     // =============================================================
     always_ff @(posedge pclk) begin
          if (!presetn) begin
               next_free_ptr <= '0;
               alloc_tag     <= '0;
               dir_cpl_ready       <= '1;
               for (int i = 0; i < DIR_ENTRIES; i++) begin
                    state[i] <= ST_EMPTY;
                    entry[i] <= '0;
               end
          end
          else begin
               next_free_ptr <= next_free_ptr;
               if (alloc_valid && alloc_ready) begin
                    entry[next_free_ptr]     <= alloc_entry;
                    entry[next_free_ptr].tag <= next_free_ptr;
                    state[next_free_ptr]     <= ST_ALLOCATED;
                    alloc_tag                <= next_free_ptr;
                    next_free_ptr            <= next_free_ptr + 1'b1;       // Move to next slot (simple round robin)
               end
               if (dir_pop_valid && dir_pop_ready) begin
                    state[dir_pop_tag]  <= ST_PENDING;
               end
               if (dir_cpl_valid && dir_cpl_ready) begin
                    state[dir_cpl_tag]       <= ST_COMPLETE;
                    entry[dir_cpl_tag].resp  <= dir_cpl_resp;
                    entry[dir_cpl_tag].num_beats <= dir_cpl_num_beats;
                    entry[dir_cpl_tag].state <= dir_cpl_error ? DIR_ST_ERROR : DIR_ST_DONE;
                    // dir_cpl_ready            <= '0;
               end
               if (dir_consumed_valid & state[status_tag_sel] == ST_COMPLETE) begin
                    state[status_tag_sel] <= ST_EMPTY;
                    entry[status_tag_sel] <= '0;
               end
          end
     end

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

     // =============================================================
     // POP block (ALLOCATED → PENDING)
     // Scan for oldest ALLOCATED entry
     // =============================================================
     logic                   found_alloc;
     logic [TAG_W_P-1:0]     oldest_tag;

     always_comb begin
          found_alloc = 1'b0;
          oldest_tag  = '0;
          for (int i = 0; i < DIR_ENTRIES; i++) begin                // Simple linear scan
               if (state[i] == ST_ALLOCATED && !found_alloc) begin
                    found_alloc = 1'b1;
                    oldest_tag  = i;
               end
          end
     end

     assign dir_pop_valid = found_alloc;
     assign dir_pop_entry = entry[oldest_tag];
     assign dir_pop_tag   = oldest_tag;

     always_comb begin
     status_dir_entry = entry[status_tag_sel];
     status_dir_state = state[status_tag_sel];
     end



endmodule