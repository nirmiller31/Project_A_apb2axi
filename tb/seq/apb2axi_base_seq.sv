
class apb2axi_base_seq extends uvm_sequence #(apb_seq_item);

     `uvm_object_utils(apb2axi_base_seq)

     function new(string name = "apb2axi_base_seq");
          super.new(name);
     endfunction

     // Diagnostic: verify sequencer binding
     task pre_start();
     super.pre_start();
     `uvm_info("BASE_SEQ",
               $sformatf("pre_start on %s",
                         (get_sequencer() == null) ? "NULL" :
                         get_sequencer().get_full_name()),
               apb2axi_verbosity)
     endtask

     task body();

          `uvm_info("BASE_SEQ", "Entered body() of base APB2AXI sequence", apb2axi_verbosity)

          // Example: issue 5 APB transactions
          repeat (5) begin
               apb_seq_item apb_req = apb_seq_item::type_id::create("apb_req");
               start_item(apb_req);
               assert(apb_req.randomize() with {
                    addr inside {[0:1023]};
                    write dist {0 := 50, 1 := 50};
               });
               finish_item(apb_req);
               `uvm_info("BASE_SEQ", $sformatf("Sent item: %s", apb_req.convert2string()), apb2axi_verbosity)
          end

          `uvm_info("BASE_SEQ", "Sequence completed successfully", apb2axi_verbosity)
     endtask

endclass
