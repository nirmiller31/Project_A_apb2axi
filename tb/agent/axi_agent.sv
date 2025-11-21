
class axi_agent extends uvm_agent;

     `uvm_component_utils(axi_agent)

     axi_driver                         drv;
     axi_monitor                        mon;
     axi_sequencer                      seqr;

     virtual axi_if                     vif;

     function new(string name = "axi_agent", uvm_component parent=null);
          super.new(name, parent);
     endfunction

     function void build_phase(uvm_phase phase);

          super.build_phase(phase);
          if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif)) `uvm_fatal("AXI_AGENT", "No virtual interface bound to axi_agent")

          drv                        = axi_driver     ::type_id::create("drv", this);
          mon                        = axi_monitor    ::type_id::create("mon", this);
          seqr                       = axi_sequencer  ::type_id::create("seqr", this);

          uvm_config_db#(virtual axi_if)::set(this, "drv", "vif", vif);
          uvm_config_db#(virtual axi_if)::set(this, "mon", "vif", vif);

     endfunction

     function void connect_phase(uvm_phase phase);

          super.connect_phase(phase);
          drv.seq_item_port.connect(seqr.seq_item_export);

     endfunction

endclass
