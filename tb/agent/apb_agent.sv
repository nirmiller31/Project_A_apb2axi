
class apb_agent extends uvm_agent;

     `uvm_component_utils(apb_agent)

     apb_driver                         drv;
     apb_monitor                        mon;
     apb_sequencer                      seqr;

     virtual apb_if                     vif;

     function new(string name = "apb_agent", uvm_component parent=null);
          super.new(name, parent);
     endfunction

     function void build_phase(uvm_phase phase);

          super.build_phase(phase);
          if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif)) `uvm_fatal("APB_AGENT", "No virtual interface bound to apb_agent")

          drv                        = apb_driver     ::type_id::create("drv", this);
          mon                        = apb_monitor    ::type_id::create("mon", this);
          seqr                       = apb_sequencer  ::type_id::create("seqr", this);

          uvm_config_db#(virtual apb_if)::set(this, "drv", "vif", vif);
          uvm_config_db#(virtual apb_if)::set(this, "mon", "vif", vif);

          `uvm_info("APB_AGENT", $sformatf("Sequencer path = %s", seqr.get_full_name()), apb2axi_verbosity)

     endfunction

     function void connect_phase(uvm_phase phase);

          super.connect_phase(phase);
          drv.seq_item_port.connect(seqr.seq_item_export);

     endfunction

endclass
