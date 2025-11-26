class apb_driver extends uvm_driver #(apb_seq_item);

    `uvm_component_utils(apb_driver)

    virtual apb_if vif;

    function new(string name = "apb_drv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);

        super.build_phase(phase);
        if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb_vif", vif)) `uvm_fatal("APB_DRIVER", "No virtual interface bound to apb_driver")

    endfunction

    task run_phase(uvm_phase phase);

        apb_seq_item req;
        `uvm_info("APB_DRIVER","Entering run_phase() loop",apb2axi_verbosity)
        forever begin
            fork
                begin
                    seq_item_port.get_next_item(req);
                    `uvm_info("APB_DRIVER", $sformatf("Got item addr=0x%0h", req.addr), apb2axi_verbosity)
                    drive_apb(req);
                    seq_item_port.item_done();
                end
                begin
                    #100us; // sim-time watchdog to catch handshake issues
                    $finish;
                    // `uvm_fatal("APB_DRIVER", "Timeout waiting on get_next_item(). Is the sequence running on this sequencer?")
                end
            join_any
            disable fork;
        end

    endtask


    task drive_apb(apb_seq_item req);

        `uvm_info("APB_DRIVER", $sformatf("Driving APB transaction: addr=0x%0h write=%0b data=0x%0h", req.addr, req.write, req.data), apb2axi_verbosity)
        @(posedge vif.PCLK);
        wait (vif.PRESETn == 1'b1);

        vif.PSEL <= 1;
        vif.PADDR <= req.addr;
        vif.PWRITE <= req.write;
        vif.PWDATA <= req.data;
        vif.PENABLE <= 0;
        @(posedge vif.PCLK);
        vif.PENABLE <= 1;
        @(posedge vif.PCLK);
        vif.PSEL <= 0;
        vif.PENABLE <= 0;

    endtask

endclass
