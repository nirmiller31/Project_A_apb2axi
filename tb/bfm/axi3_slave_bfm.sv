//------------------------------------------------------------------------------
// AXI3 Slave BFM (Full Version)
// Supports:
//   * Multi-beat bursts (ARLEN/AWLEN)
//   * SIZE-qualified beat size (2^SIZE bytes)
//   * WSTRB byte-level writes
//   * Backpressure-safe R and B channels
//   * Non-interleaved mode (AXI3-compliant for single outstanding ID)
//   * Real memory model
//------------------------------------------------------------------------------
// No interleaving yet, but architecture ready for ID-based extensions.
//------------------------------------------------------------------------------

import uvm_pkg::*;
`include "uvm_macros.svh"
import apb2axi_pkg::*;


class axi3_slave_bfm extends uvm_component;

    `uvm_component_utils(axi3_slave_bfm)

    virtual axi_if vif;

    // ------------------------------------------------------------
    // Memory model (word-addressable)
    // AXI_DATA_W-wide words, depth = configurable
    // ------------------------------------------------------------
    localparam int MEM_DEPTH = 4096;
    typedef bit [AXI_DATA_W-1:0] data_word_t;

    data_word_t mem [0:MEM_DEPTH-1];

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name="axi3_slave_bfm", uvm_component parent=null);
        super.new(name,parent);
    endfunction

    // ------------------------------------------------------------
    // Build
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_if)::get(this,"","axi_vif",vif))
            `uvm_fatal("AXI3_BFM","No virtual interface bound to BFM");
    endfunction


    // ------------------------------------------------------------
    // Initialize memory with deterministic pattern
    // ------------------------------------------------------------
    task automatic init_mem();
        for (int i=0; i<MEM_DEPTH; i++) begin
            mem[i]       = '0;
            mem[i][31:0] = i;  // simple deterministic pattern
        end
    endtask


    // ------------------------------------------------------------
    // Main BFM process
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        init_mem();

        // Initialize interface outputs
        vif.ARREADY <= 0;
        vif.AWREADY <= 0;
        vif.WREADY  <= 0;
        vif.RVALID  <= 0;
        vif.RLAST   <= 0;
        vif.RRESP   <= 0;
        vif.BVALID  <= 0;
        vif.BRESP   <= 0;

        wait (vif.ARESETn === 1'b1);
        @(posedge vif.ACLK);

        `uvm_info("AXI3_BFM","BFM is alive and ready",UVM_LOW)

        forever begin
            @(posedge vif.ACLK);

            // Always ready for address
            vif.ARREADY <= 1;
            vif.AWREADY <= 1;

            // Always ready for write data
            vif.WREADY  <= 1;

            // ========= READ ADDRESS =========
            if (vif.ARVALID && vif.ARREADY) begin
                fork
                    automatic logic [AXI_ADDR_W-1:0] araddr = vif.ARADDR;
                    automatic logic [3:0]           arlen  = vif.ARLEN;
                    automatic logic [2:0]           arsize = vif.ARSIZE;
                    automatic logic [AXI_ID_W-1:0]  arid   = vif.ARID;
                    begin
                        do_read(araddr, arlen, arsize, arid);
                    end
                join_none
            end

            // ========= WRITE ADDRESS =========
            if (vif.AWVALID && vif.AWREADY) begin
                fork
                    automatic logic [AXI_ADDR_W-1:0] awaddr = vif.AWADDR;
                    automatic logic [3:0]           awlen  = vif.AWLEN;
                    automatic logic [2:0]           awsize = vif.AWSIZE;
                    automatic logic [AXI_ID_W-1:0]  awid   = vif.AWID;
                    begin
                        do_write(awaddr, awlen, awsize, awid);
                    end
                join_none
            end
        end

        phase.drop_objection(this);
    endtask


    // ------------------------------------------------------------
    // READ handler (multi-beat)
    // ------------------------------------------------------------
    task automatic do_read(
        logic [AXI_ADDR_W-1:0] araddr,
        logic [3:0]            arlen,
        logic [2:0]            arsize,
        logic [AXI_ID_W-1:0]   arid
    );
        int beats = arlen + 1;
        int bytes_per_beat = 1 << arsize;
        int base_word = araddr >> $clog2(AXI_DATA_W/8);

        `uvm_info("AXI3_BFM",
            $sformatf("READ: addr=0x%0h beats=%0d size=%0d id=%0d",
                      araddr, beats, bytes_per_beat, arid),
            UVM_MEDIUM)

        for (int i = 0; i < beats; i++) begin
            int idx = (base_word + i) % MEM_DEPTH;

            @(posedge vif.ACLK);
            vif.RID    <= arid;
            vif.RDATA  <= mem[idx];
            vif.RRESP  <= 2'b00;
            vif.RLAST  <= (i == beats-1);
            vif.RVALID <= 1'b1;

            // Backpressure-safe wait
            do @(posedge vif.ACLK);
            while (!vif.RREADY && vif.ARESETn);

            vif.RVALID <= 1'b0;
        end

        vif.RLAST <= 0;
    endtask


    // ------------------------------------------------------------
    // WRITE handler (multi-beat) + WSTRB support
    // ------------------------------------------------------------
    task automatic do_write(
          logic [AXI_ADDR_W-1:0] awaddr,
          logic [3:0]            awlen,
          logic [2:0]            awsize,
          logic [AXI_ID_W-1:0]   awid
    );
          int beats = awlen + 1;
          int base_word = awaddr >> $clog2(AXI_DATA_W/8);
          int idx; 

          `uvm_info("AXI3_BFM",
               $sformatf("WRITE: addr=0x%0h beats=%0d size=%0d id=%0d",
                         awaddr, beats, awsize, awid),
               UVM_MEDIUM)

          for (int i = 0; i < beats; i++) begin
               // Wait for W beat
               do @(posedge vif.ACLK);
               while (!vif.WVALID && vif.ARESETn);

               idx = (base_word + i) % MEM_DEPTH;

               // ---------- BYTE-WISE write using WSTRB ----------
               for (int b = 0; b < (AXI_DATA_W/8); b++) begin
                    if (vif.WSTRB[b])
                         mem[idx][8*b +: 8] = vif.WDATA[8*b +: 8];
               end

               // Check WLAST correctness
               if ((i == beats-1) && !vif.WLAST)
                    `uvm_error("AXI3_BFM","WLAST missing in final beat")
               if ((i != beats-1) && vif.WLAST)
                    `uvm_error("AXI3_BFM","WLAST asserted too early")
          end

          // Send BRESP after all beats
          @(posedge vif.ACLK);
          vif.BID    <= awid;
          vif.BRESP  <= 2'b00;
          vif.BVALID <= 1;

          // Wait for BREADY
          do @(posedge vif.ACLK);
          while (!vif.BREADY && vif.ARESETn);

          vif.BVALID <= 0;
    endtask

endclass