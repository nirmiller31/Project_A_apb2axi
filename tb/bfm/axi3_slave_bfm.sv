//------------------------------------------------------------------------------
// AXI3 Slave BFM (for apb2axi project)
// - DUT is AXI3 master
// - This BFM acts as a simple memory-mapped AXI3 slave
//   * Supports bursts (INCR / FIXED)
//   * Handles IDs
//   * No write interleaving, no WID, no LOCKed sequences
//------------------------------------------------------------------------------

import uvm_pkg::*;
`include "uvm_macros.svh"
import apb2axi_pkg::*;

class axi3_slave_bfm extends uvm_component;

     `uvm_component_utils(axi3_slave_bfm)

     virtual axi_if vif;

     // Simple memory model: word-addressable
     typedef logic [AXI_ADDR_W-1:0] addr_t;
     typedef logic [AXI_DATA_W-1:0] data_t;
     typedef logic [AXI_ID_W-1:0]   id_t;

     data_t mem[addr_t];   // associative array: addr -> data

     // Optional latency knobs (can be overridden via config_db)
     int unsigned rd_latency_min        = 0;
     int unsigned rd_latency_max        = 0;
     int unsigned wr_resp_latency_min   = 0;
     int unsigned wr_resp_latency_max   = 0;

     // Simple descriptor for AW/AR commands
     typedef struct packed {
          addr_t        addr;
          logic [7:0]   len;    // AXI3: beats-1 (0..15); we keep 8 bits for simplicity
          logic [2:0]   size;   // log2(bytes per beat)
          logic [1:0]   burst;  // 01=INCR, 00=FIXED
          id_t          id;
     } axi_cmd_t;

     // Queues for outstanding commands (responses return in acceptance order)
     axi_cmd_t rd_q[$];
     axi_cmd_t wr_q[$];

     function new(string name = "axi3_slave_bfm", uvm_component parent=null);
          super.new(name, parent);
     endfunction

     function void build_phase(uvm_phase phase);
          super.build_phase(phase);

          if (!uvm_config_db#(virtual axi_if)::get(this, "", "axi_vif", vif)) `uvm_fatal("AXI3_SLV", "No axi_vif found for axi3_slave_bfm")

          // FIXME get latency knobs via config_db if you want later
     endfunction

     task run_phase(uvm_phase phase);
          // Default slave outputs
          vif.AWREADY <= 0;
          vif.WREADY  <= 0;
          vif.BVALID  <= 0;
          vif.BRESP   <= 2'b00;
          vif.BID     <= '0;

          vif.ARREADY <= 0;
          vif.RVALID  <= 0;
          vif.RDATA   <= '0;
          vif.RRESP   <= 2'b00;
          vif.RLAST   <= 0;
          vif.RID     <= '0;

          // Wait for reset deassert
          @(posedge vif.ACLK);
          wait (vif.ARESETn);

          // Run write and read channels in parallel
          fork
               handle_writes();
               handle_reads();
          join
     endtask

     //============================================================================
     // WRITE CHANNELS: AW, W, B
     //============================================================================
     task handle_writes();
          axi_cmd_t cur_aw;
          bit       have_aw = 0;
          int       beats_left;
          addr_t    cur_addr;

          vif.AWREADY <= 1;
          vif.WREADY  <= 1;
          vif.BVALID  <= 0;

          forever @(posedge vif.ACLK) begin
               if (!vif.ARESETn) begin
                    have_aw    = 0;
                    vif.AWREADY <= 1;
                    vif.WREADY  <= 1;
                    vif.BVALID  <= 0;
               end
               else begin
                    // Accept a write address
                    if (!have_aw && vif.AWVALID && vif.AWREADY) begin
                         cur_aw.addr  = vif.AWADDR;
                         cur_aw.len   = vif.AWLEN;
                         cur_aw.size  = vif.AWSIZE;
                         cur_aw.burst = vif.AWBURST;
                         cur_aw.id    = vif.AWID;
                         have_aw      = 1;
                         beats_left   = cur_aw.len + 1;
                         cur_addr     = cur_aw.addr;

                         `uvm_info("AXI3_SLV",
                                   $sformatf("AW: addr=0x%0h len=%0d size=%0d id=%0d",
                                             cur_aw.addr, cur_aw.len, cur_aw.size, cur_aw.id),
                                   UVM_MEDIUM)
                    end

                    // Consume W data once we have an AW
                    if (have_aw && vif.WVALID && vif.WREADY) begin
                         // Write into memory model; simple word-aligned model
                         mem[cur_addr] = vif.WDATA;

                         // Next address for INCR burst
                         if (cur_aw.burst == 2'b01) begin // INCR
                         int beat_bytes = 1 << cur_aw.size;
                         cur_addr += beat_bytes;
                         end

                         beats_left--;

                         // Last beat?
                         if (vif.WLAST || (beats_left == 0)) begin
                         have_aw = 0;
                         send_bresp(cur_aw.id);
                         end
                    end
               end
          end
     endtask

    task send_bresp(id_t id);
        int delay = (wr_resp_latency_max > wr_resp_latency_min)
                    ? $urandom_range(wr_resp_latency_min, wr_resp_latency_max)
                    : wr_resp_latency_min;

        repeat (delay) @(posedge vif.ACLK);

        vif.BID    <= id;
        vif.BRESP  <= 2'b00; // OKAY
        vif.BVALID <= 1'b1;

        `uvm_info("AXI3_SLV",
                  $sformatf("B: id=%0d resp=OKAY", id),
                  UVM_MEDIUM)

        // Wait for master to consume
        do @(posedge vif.ACLK); while (!vif.BREADY);
        vif.BVALID <= 0;
    endtask

    //============================================================================
    // READ CHANNELS: AR, R
    //============================================================================
    task handle_reads();
    
        bit busy_read = 0;

        vif.ARREADY <= 1;
        vif.RVALID  <= 0;
        vif.RLAST   <= 0;

        forever @(posedge vif.ACLK) begin
            if (!vif.ARESETn) begin
                rd_q.delete();
                busy_read  = 0;
                vif.ARREADY <= 1;
                vif.RVALID  <= 0;
                vif.RLAST   <= 0;
            end
            else begin
                // Accept AR
                if (vif.ARVALID && vif.ARREADY) begin
                    axi_cmd_t ar;

                    ar.addr  = vif.ARADDR;
                    ar.len   = vif.ARLEN;
                    ar.size  = vif.ARSIZE;
                    ar.burst = vif.ARBURST;
                    ar.id    = vif.ARID;

                    rd_q.push_back(ar);

                    `uvm_info("AXI3_SLV",
                              $sformatf("AR: addr=0x%0h len=%0d size=%0d id=%0d",
                                        ar.addr, ar.len, ar.size, ar.id),
                              UVM_MEDIUM)
                end

                // Serve one burst at a time, in acceptance order
                if (!busy_read && rd_q.size() > 0) begin
                    busy_read = 1;
                    drive_read_burst(rd_q.pop_front(), busy_read);
                end
            end
        end
    endtask

    task drive_read_burst(axi_cmd_t ar, output bit busy_read);
        int beat_bytes = 1 << ar.size;
        addr_t addr    = ar.addr;
        int beats      = ar.len + 1;

        int delay = (rd_latency_max > rd_latency_min)
                    ? $urandom_range(rd_latency_min, rd_latency_max)
                    : rd_latency_min;
        repeat (delay) @(posedge vif.ACLK);

        for (int i = 0; i < beats; i++) begin
            data_t rdata = mem.exists(addr) ? mem[addr] : '0;

            vif.RID    <= ar.id;
            vif.RDATA  <= rdata;
            vif.RRESP  <= 2'b00;          // OKAY
            vif.RLAST  <= (i == beats-1);
            vif.RVALID <= 1'b1;

            // Wait for master to accept this beat
            do @(posedge vif.ACLK); while (!vif.RREADY);

            vif.RVALID <= 0;
            vif.RLAST  <= 0;

            if (ar.burst == 2'b01) // INCR
                addr += beat_bytes;
        end

        busy_read = 0;
    endtask

endclass