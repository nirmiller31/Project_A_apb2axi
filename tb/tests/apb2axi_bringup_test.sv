
//------------------------------------------------------------------------------
// File          : apb2axi_bringup_test.sv
// Project       : APB2AXI
// Description   : Minimal directed UVM test for bring-up
//------------------------------------------------------------------------------

class apb2axi_bringup_test extends apb2axi_base_test;
     `uvm_component_utils(apb2axi_bringup_test)

     function new(string name = "apb2axi_bringup_test",uvm_component parent = null);
          super.new(name, parent);
     endfunction

     task run_phase(uvm_phase phase);
          apb2axi_bringup_seq seq;

          phase.raise_objection(this);
          `uvm_info("BRINGUP_TEST", "Starting bring-up test", apb2axi_verbosity)

          seq = apb2axi_bringup_seq::type_id::create("seq");
          seq.m_env = env;
          seq.start(env.apb_ag.seqr);

          `uvm_info("BRINGUP_TEST", "Bring-up sequence finished", apb2axi_verbosity)
          phase.drop_objection(this);
     endtask
endclass