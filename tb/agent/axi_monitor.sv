
class axi_monitor extends uvm_monitor;

     `uvm_component_utils(axi_monitor)

     // Observes transactions for:
     uvm_analysis_port #(axi_seq_item)     ap;

     virtual axi_if                        vif;

     function new(string name = "axi_monitor", uvm_component parent=null);
          super.new(name, parent);
          ap                                = new("ap", this);
     endfunction

     function void build_phase(uvm_phase phase);
          
          super.build_phase(phase);
          if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif)) `uvm_fatal("AXI_MONITOR", "No virtual interface bound to axi_monitor")

     endfunction

     task run_phase(uvm_phase phase);

          wait (vif.ARESETn === 1'b1);
          @(posedge vif.ACLK);

          // forever begin
          while (phase.get_objection_count() > 0) begin
               @(posedge vif.ACLK);
               // --- Detect Write Address handshake ---
               if (vif.AWVALID && vif.AWREADY) begin
                    axi_seq_item tr     = axi_seq_item::type_id::create("axi_wr_tr", this);
                    tr.write            = 1;
                    tr.addr             = vif.AWADDR;
                    tr.id               = vif.AWID;
                    tr.len              = vif.AWLEN;
                    tr.size             = vif.AWSIZE;
                    tr.burst            = vif.AWBURST;

                    // Capture data once WVALID/WREADY handshake completes
                    fork
                         begin
                              wait (vif.WVALID && vif.WREADY);
                              tr.data   = vif.WDATA;
                         end
                    join_none

                    // Capture response when BVALID/BREADY occurs
                    fork
                         begin
                              wait (vif.BVALID && vif.BREADY);
                              tr.resp   = vif.BRESP;
                              ap.write(tr);
                              `uvm_info("AXI_MONITOR", $sformatf("Observed WRITE: addr=0x%08h data=0x%08h resp=%0d", tr.addr, tr.data, tr.resp), apb2axi_verbosity)
                         end
                    join_none
               end

               // --- Detect Read Address handshake ---
               else if (vif.ARVALID && vif.ARREADY) begin
                    axi_seq_item tr     = axi_seq_item::type_id::create("axi_rd_tr", this);
                    tr.write            = 0;
                    tr.addr             = vif.ARADDR;
                    tr.id               = vif.ARID;
                    tr.len              = vif.ARLEN;
                    tr.size             = vif.ARSIZE;
                    tr.burst            = vif.ARBURST;

                    // Wait for data return
                    fork
                         begin
                         wait (vif.RVALID && vif.RREADY);
                         tr.data        = vif.RDATA;
                         tr.resp        = vif.RRESP;
                         ap.write(tr);
                         `uvm_info("AXI_MONITOR", $sformatf("Observed READ:  addr=0x%08h data=0x%08h resp=%0d", tr.addr, tr.data, tr.resp), apb2axi_verbosity)
                         end
                    join_none
               end
          end
     endtask

endclass
