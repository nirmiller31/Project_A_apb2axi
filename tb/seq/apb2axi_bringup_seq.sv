
//------------------------------------------------------------------------------
// File          : apb2axi_bringup_seq.sv
// Project       : APB2AXI
// Author        : Nir Miller & Ido Oreg
// Description   : Minimal directed APB sequence to trigger a single commit_pulse
//------------------------------------------------------------------------------

`ifndef APB2AXI_BRINGUP_SEQ_SV
`define APB2AXI_BRINGUP_SEQ_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import apb2axi_tb_pkg::*;

class apb2axi_bringup_seq extends apb2axi_base_seq;

     `uvm_object_utils(apb2axi_bringup_seq)

     function new(string name = "apb2axi_bringup_seq");
          super.new(name);
     endfunction

     task body();
          apb_seq_item req;

          `uvm_info("BRINGUP_SEQ", "Starting APB2AXI bringup sequence", UVM_LOW)

          // 1) Program addr_hi = 0
          apb_write_reg(16'h0004, 32'h0000_0000);

          // 2) Program CMD    = read, len=1, size=0  (you can tweak later)
          apb_write_reg(16'h0008, 32'h0000_0001);

          // 3) Program addr_lo and trigger commit_pulse
          apb_write_reg(16'h0000, 32'h0000_1000);

          #200ns;

     endtask

endclass

`endif