

import apb2axi_pkg::*;

module apb2axi_directory #(
     parameter int TAG_NUM_P = TAG_NUM,
     parameter int TAG_W_P   = TAG_W
)(
     input  logic                       pclk,
     input  logic                       presetn,

     // From reg file (each APB commit)
     input  logic                       commit_pulse,
     input  logic [AXI_ADDR_W-1:0]      addr,
     input  logic [7:0]                 len,
     input  logic [2:0]                 size,
     input  logic                       is_write,

     input  logic                       cpl_valid,
     input  logic [TAG_W_P-1:0]         cpl_tag,
     input  logic                       cpl_error,

     output logic                       pending_valid,
     output directory_entry_t           pending_entry,
     output logic [TAG_W_P-1:0]         pending_tag,
     input  logic                       pending_pop
);
     // Directory entry array
     directory_entry_t                  dir_mem [TAG_NUM_P];
     logic [TAG_W_P-1:0]                dir_wr_ptr;   // simple incrementing tag pointer, FIXME- make it complex
     logic [TAG_W_P-1:0]                dir_rd_ptr;

     always_ff @(posedge pclk or negedge presetn) begin
          if (!presetn) begin
               dir_wr_ptr <= '0;
               dir_rd_ptr <= '0;
               for (int i = 0; i < TAG_NUM_P; i++) begin
                    dir_mem[i].state <= DIR_ST_EMPTY;
                    dir_mem[i].tag   <= i[TAG_W_P-1:0];
                    dir_mem[i].addr  <= '0;
                    dir_mem[i].len   <= '0;
                    dir_mem[i].size  <= '0;
                    dir_mem[i].burst <= 2'b01; // INCR default
                    dir_mem[i].is_write <= '0;
               end
          end else begin
               // New committed request
               if (commit_pulse) begin
                    dir_mem[dir_wr_ptr].addr     <= addr;
                    dir_mem[dir_wr_ptr].len      <= len;
                    dir_mem[dir_wr_ptr].size     <= size;
                    dir_mem[dir_wr_ptr].is_write <= is_write;
                    dir_mem[dir_wr_ptr].burst    <= 2'b01;        // INCR for now
                    dir_mem[dir_wr_ptr].tag      <= dir_wr_ptr;
                    dir_mem[dir_wr_ptr].state    <= DIR_ST_PENDING;
                    dir_wr_ptr                   <= dir_wr_ptr + 1'b1; // simple wrap
               end

               // Txn_mgr took one pending entry → mark as ISSUED
               if (pending_pop && pending_valid) begin
                    dir_mem[dir_rd_ptr].state <= DIR_ST_ISSUED;
                    dir_rd_ptr                <= dir_rd_ptr + 1'b1;
               end

               // Update directory entry according to the completion
               if (cpl_valid) begin
                    dir_mem[cpl_tag].state <= cpl_error ? DIR_ST_ERROR : DIR_ST_DONE;
               end
          end
     end

     // Combinational "next pending" view
     always_comb begin
          pending_tag   = dir_rd_ptr;
          pending_entry = dir_mem[dir_rd_ptr];
          pending_valid = (dir_mem[dir_rd_ptr].state == DIR_ST_PENDING);
     end

     // Debug
     // synthesis translate_off
     always_ff @(posedge pclk)
          if (commit_pulse)
               $display("%t [DIR] Enq TAG=%0d is_wr=%0b addr=%h len=%0d size=%0d", $time, dir_wr_ptr, is_write, addr, len, size);
     
     always_ff @(posedge pclk) begin
          if (pending_valid)
               $display("%t [DIR] PENDING TAG=%0d state=%0d addr=%h", $time, pending_tag, dir_mem[pending_tag].state, dir_mem[pending_tag].addr);
     end
     // synthesis translate_on

endmodule