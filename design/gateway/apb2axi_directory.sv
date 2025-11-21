

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
     input  logic                       is_write
);
     // Directory entry array
     directory_entry_t                  dir_mem [TAG_NUM_P];
     logic [TAG_W_P-1:0]                wr_ptr;   // simple incrementing tag pointer, FIXME- make it complex
     logic                              wr_fire;  // internal strobe

     always_ff @(posedge pclk) begin
     if (!presetn) begin
          wr_ptr                        <= '0;
          for (int i = 0; i < TAG_NUM_P; i++) begin
               dir_mem[i]               <= '0;
          end
     end else if (commit_pulse) begin
          dir_mem[wr_ptr].addr          <= addr;
          dir_mem[wr_ptr].len           <= len;
          dir_mem[wr_ptr].size          <= size;
          dir_mem[wr_ptr].is_write      <= is_write;
          dir_mem[wr_ptr].tag           <= wr_ptr;
          wr_ptr                        <= wr_ptr + 1'b1;  // simple wrap-around
     end
     end

     // (Optional) waveform debug: print each enqueue
     // synthesis translate_off
     always_ff @(posedge pclk)
     if (commit_pulse)
          $display("%t [GATEWAY] Enqueued TAG=%0d  is_write=%0b addr=%h len=%0d size=%0d",
                    $time, wr_ptr, is_write, addr, len, size);
     // synthesis translate_on

endmodule
