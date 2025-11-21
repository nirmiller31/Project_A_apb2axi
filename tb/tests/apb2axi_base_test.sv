
class apb2axi_base_test extends uvm_test;

     `uvm_component_utils(apb2axi_base_test)

     apb2axi_env                   env;

     function new(string name = "apb2axi_base_test", uvm_component parent = null);
          super.new(name, parent);
     endfunction

     function void build_phase(uvm_phase phase);
          super.build_phase(phase);
          apb2axi_tb_pkg::apb2axi_configure_verbosity();
          env                    = apb2axi_env::type_id::create("env", this);
          uvm_top.print_topology();
     endfunction

     // task run_phase(uvm_phase phase);
     //      // phase.raise_objection(this);
     //      // `uvm_info("BASE_TEST", "APB2AXI environment bring-up successful!", UVM_LOW)
     //      // #100ns;
     //      // phase.drop_objection(this);
     //      apb2axi_base_seq main_seq;

     //      `uvm_info("BASE_TEST", $sformatf("Sequencer handle in test = %s", env.apb_ag.seqr.get_full_name()), UVM_NONE)
     //      if (env.apb_ag.drv.seq_item_port.is_connected())
     //           `uvm_info("BASE_TEST", "Driver’s seq_item_port is connected.", UVM_NONE)
     //      else
     //           `uvm_error("BASE_TEST", "Driver’s seq_item_port is NOT connected!")


     //      phase.raise_objection(this);
     //      `uvm_info("BASE_TEST", "Starting APB2AXI main sequence...", UVM_NONE)

     //      // Create and start the sequence
     //      main_seq = apb2axi_base_seq::type_id::create("main_seq");
     //      main_seq.start(env.apb_ag.seqr); // or a virtual sequencer later

     //      `uvm_info("BASE_TEST", "Main sequence finished, dropping objection.", UVM_NONE)
     //      phase.drop_objection(this);

     // endtask

task run_phase(uvm_phase phase);
    apb2axi_base_seq main_seq;

    `uvm_info("BASE_TEST",
              $sformatf("Sequencer handle in test = %s",
                        env.apb_ag.seqr.get_full_name()), apb2axi_verbosity)

    if (env.apb_ag.drv.seq_item_port != null)
        `uvm_info("BASE_TEST",
                  "Driver seq_item_port handle is valid (UVM-1.2 safe check).",
                  apb2axi_verbosity)
    else
        `uvm_error("BASE_TEST", "Driver seq_item_port handle is NULL!")

    phase.raise_objection(this);
    `uvm_info("BASE_TEST", "Starting APB2AXI main sequence...", apb2axi_verbosity)

    main_seq = apb2axi_base_seq::type_id::create("main_seq");
    main_seq.start(env.apb_ag.seqr);

    `uvm_info("BASE_TEST", "Main sequence finished, dropping objection.", apb2axi_verbosity)
    phase.drop_objection(this);
endtask


endclass  