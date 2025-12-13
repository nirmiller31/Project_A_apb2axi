import uvm_pkg::*;
`include "uvm_macros.svh"
import apb2axi_tb_pkg::*;

class apb2axi_base_seq extends uvm_sequence #(apb_seq_item);

     `uvm_object_utils(apb2axi_base_seq)

     // ------------------------------------------------
     // Common register addresses (keep in one place)
     // ------------------------------------------------
     localparam int REG_ADDR_LO        = 'h00;
     localparam int REG_ADDR_HI        = 'h04;
     localparam int REG_CMD            = 'h08;
     localparam int REG_RD_STATUS      = 'h0C;
     localparam int REG_RD_DATA        = 'h10;
     localparam int REG_TAG_TO_CONSUME = 'h14;

     apb2axi_env m_env;

     function new(string name = "apb2axi_base_seq");
          super.new(name);
     endfunction

     task body();

          uvm_phase phase = get_starting_phase();
          if (phase != null) phase.raise_objection(this);

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

          if (phase != null) phase.drop_objection(this);
     endtask

     // ---------------------------------------------------------
     // Common helper for all derived sequences
     // ---------------------------------------------------------
     task apb_write_reg(bit [APB_ADDR_W-1:0] addr_i, bit [APB_DATA_W-1:0] data_i);
          apb_seq_item req;
          req = apb_seq_item::type_id::create("req");
          start_item(req);
          req.addr  = addr_i;
          req.write = 1'b1;
          req.data  = data_i;     // use your 'data' field
          finish_item(req);
     endtask

     task apb_read_reg(bit [APB_ADDR_W-1:0] addr_i, output bit [APB_DATA_W-1:0] data_o);
          apb_seq_item req;
          req = apb_seq_item::type_id::create("req");
          start_item(req);
          req.addr  = addr_i;
          req.write = 1'b0;
          finish_item(req);

          data_o = req.data;
     endtask

     task automatic set_tag_to_consume(bit [TAG_W-1:0] tag);
          bit [31:0] data;
          data = '0;
          data[TAG_W-1:0] = tag;
          apb_write_reg(REG_TAG_TO_CONSUME, data);
          `uvm_info("BASE_SEQ", $sformatf("TAG_TO_CONSUME <= %0d (0x%0h)", tag, data), apb2axi_verbosity)
     endtask

endclass
