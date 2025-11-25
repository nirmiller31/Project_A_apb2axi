import uvm_pkg::*;
`include "uvm_macros.svh"
import apb2axi_tb_pkg::*;

class apb2axi_base_seq extends uvm_sequence #(apb_seq_item);

     `uvm_object_utils(apb2axi_base_seq)

     function new(string name = "apb2axi_base_seq");
          super.new(name);
     endfunction

     task body();

          `uvm_info("BASE_SEQ", "Entered body() of base APB2AXI sequence", apb2axi_verbosity)

          // // Example: issue 5 APB transactions
          // repeat (5) begin
          //      apb_seq_item apb_req = apb_seq_item::type_id::create("apb_req");
          //      start_item(apb_req);
          //      assert(apb_req.randomize() with {
          //           addr inside {[0:1023]};
          //           write dist {0 := 50, 1 := 50};
          //      });
          //      finish_item(apb_req);
          //      `uvm_info("BASE_SEQ", $sformatf("Sent item: %s", apb_req.convert2string()), apb2axi_verbosity)
          // end

          `uvm_info("BASE_SEQ", "Sequence completed successfully", apb2axi_verbosity)
     endtask

     // ---------------------------------------------------------
     // Common helper for all derived sequences
     // ---------------------------------------------------------
     task apb_write_reg(bit [APB_ADDR_W-1:0] addr, bit [APB_DATA_W-1:0] data);
          apb_seq_item req;

          `uvm_create(req)
          req.addr  = addr;
          req.write = 1;
          req.data  = data;

          `uvm_send(req)

          `uvm_info("BASE_SEQ", $sformatf("APB WRITE helper: addr=0x%0h data=0x%0h", addr, data), apb2axi_verbosity)
     endtask     

endclass
