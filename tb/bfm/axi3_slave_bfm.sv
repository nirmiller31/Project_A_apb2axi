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
// Modes:
//   - refular (default)
//   - outstanding (+LINEAR_OUTSTANDING)
//   - extreme    (+EXTREME_OUTSTANDING)
//------------------------------------------------------------------------------

import uvm_pkg::*;
`include "uvm_macros.svh"
import apb2axi_pkg::*;


class axi3_slave_bfm extends uvm_component;

     `uvm_component_utils(axi3_slave_bfm)

     virtual axi_if vif;

     // ---- Logging of read consumption order ----
     bit [AXI_ID_W-1:0] beat_order_q[$];   // one entry per R beat
     bit [AXI_ID_W-1:0] burst_order_q[$];  // one entry per completed burst

     // ------------------------------------------------------------
     // Read mode
     // ------------------------------------------------------------
     typedef enum int { MODE_REGULAR = 0,
                         MODE_OUTSTANDING = 1,
                         MODE_EXTREME = 2 } read_mode_e;

     read_mode_e read_mode = MODE_REGULAR;

     // ------------------------------------------------------------
     // Queue for outstanding reads (extreme)
     // ------------------------------------------------------------
     typedef struct packed {
          logic [AXI_ADDR_W-1:0] addr;
          logic [3:0]            len;
          logic [2:0]            size;
          logic [AXI_ID_W-1:0]   id;
          logic [1:0]            burst;
     } read_req_t;

     read_req_t read_q[$];
     // ------------------------------------------------------------
     // Queue for interleaving reads (extreme)
     // ------------------------------------------------------------
     typedef struct {
          logic [AXI_ADDR_W-1:0] addr;
          logic [3:0]            beats_left;  // remaining beats
          logic [2:0]            size;
          logic [AXI_ID_W-1:0]   id;
          logic [1:0]            burst;
          int unsigned           mem_idx;     // pointer to memory
     } active_read_t;

     active_read_t active_reads[$];

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

          if ($test$plusargs("EXTREME_OUTSTANDING")) begin
               read_mode = MODE_EXTREME;
               `uvm_info("AXI3_BFM", "Read mode: EXTREME_OUTSTANDING", apb2axi_verbosity)
          end
          else if ($test$plusargs("LINEAR_OUTSTANDING")) begin
               read_mode = MODE_OUTSTANDING;
               `uvm_info("AXI3_BFM", "Read mode: LINEAR_OUTSTANDING", apb2axi_verbosity)
          end
          else begin
               read_mode = MODE_REGULAR;
               `uvm_info("AXI3_BFM", "Read mode: LINEAR (default)", apb2axi_verbosity)
          end
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
     // R-channel driver when using outstanding modes
     // ------------------------------------------------------------
     task automatic drive_read_queue();
     int idx;
     active_read_t ar;
     logic [AXI_DATA_W-1:0] rdata;
          forever begin
               @(posedge vif.ACLK);
               // No active reads -> wait
               if (active_reads.size() == 0)
                    continue;

               // Scheduling policy
               case (read_mode)
                    MODE_REGULAR:       idx = 0;
                    MODE_OUTSTANDING:  idx = 0;
                    MODE_EXTREME:      idx = $urandom_range(0, active_reads.size()-1);
               endcase

               // Pick a random outstanding burst
               // idx = $urandom_range(0, active_reads.size()-1);
               ar = active_reads[idx];

               // RANDOM latency before issuing the beat (optional)
               repeat ($urandom_range(0,3)) @(posedge vif.ACLK);

               // ======== SEND ONE R BEAT ========
               if (ar.mem_idx < MEM_DEPTH)
                    rdata = MEM[ar.mem_idx];
               else
                    rdata = '0;

               `uvm_info("AXI3_BFM", $sformatf("TOOK READ: id=%d, idx=0x%0d rdata=%0h", ar.id, idx, rdata), apb2axi_verbosity)

               vif.RID    <= ar.id;
               vif.RDATA  <= rdata;
               vif.RRESP  <= 2'b00;
               vif.RLAST  <= (ar.beats_left == 1);
               vif.RVALID <= 1'b1;

               `uvm_info("AXI3_BFM", $sformatf("%t BFM_DRIVE_R rid=%0d rlast=%0b rvalid=%0b", $time, ar.id, (ar.beats_left == 1), vif.RVALID), apb2axi_verbosity)

               // Wait for RREADY
               do @(posedge vif.ACLK);
               while (!vif.RREADY && vif.ARESETn);

               vif.RVALID <= 0;

               beat_order_q.push_back(ar.id);

               if (ar.beats_left == 1) burst_order_q.push_back(ar.id);

               // ======== UPDATE STATE ========
               // Move memory pointer
               if (ar.burst == 2'b01) // INCR
                    ar.mem_idx++;

               ar.beats_left--;

               if (ar.beats_left == 0) begin
                    active_reads.delete(idx);
               end else begin
                    active_reads[idx] = ar;
               end
          end
     endtask

     // ------------------------------------------------------------
     // Main BFM process
     // ------------------------------------------------------------
     task run_phase(uvm_phase phase);
          active_read_t arx;

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

          `uvm_info("AXI3_BFM","BFM is alive and ready", apb2axi_verbosity)

          fork
               drive_read_queue();
          join_none

          forever begin
               @(posedge vif.ACLK);

               // Always ready for address
               vif.ARREADY <= 1;
               vif.AWREADY <= 1;

               // Always ready for write data
               vif.WREADY  <= 1;

               // ========= READ ADDRESS =========
               if (vif.ARVALID && vif.ARREADY) begin
                    active_read_t arx;

                    arx.addr       = vif.ARADDR;
                    arx.beats_left = vif.ARLEN + 1;
                    arx.size       = vif.ARSIZE;
                    arx.id         = vif.ARID;
                    arx.burst      = vif.ARBURST;
                    arx.mem_idx    = addr2idx(vif.ARADDR);

                    case (read_mode)
                         MODE_REGULAR: begin
                              // Allow only one outstanding
                              wait (active_reads.size() == 0);
                              active_reads.push_back(arx);
                         end

                         MODE_OUTSTANDING: begin
                              // Multiple outstanding, but ordered issue
                              active_reads.push_back(arx);
                         end

                         MODE_EXTREME: begin
                              // Same as outstanding, scheduling handled later
                              active_reads.push_back(arx);
                         end
                    endcase

            end

               // ========= WRITE ADDRESS =========
               if (vif.AWVALID && vif.AWREADY) begin
                    fork
                         automatic logic [AXI_ADDR_W-1:0]   awaddr = vif.AWADDR;
                         automatic logic [3:0]              awlen  = vif.AWLEN;
                         automatic logic [2:0]              awsize = vif.AWSIZE;
                         automatic logic [AXI_ID_W-1:0]     awid   = vif.AWID;
                         begin
                              do_write(awaddr, awlen, awsize, awid);
                         end
                    join_none
               end
          end

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

     function void report_phase(uvm_phase phase);
          string s;

          if (burst_order_q.size() > 0) begin
               s = "{";
               foreach (burst_order_q[i]) begin
                    if (i) s = {s, ", "};
                    s = {s, $sformatf("%0d", burst_order_q[i])};
                    // or "%0h" if you prefer hex
               end
               s = {s, "}"};
               `uvm_info("AXI3_BFM", $sformatf("Burst completion RID order = %s", s), apb2axi_verbosity)
          end

          if (beat_order_q.size() > 0) begin
               s = "{";
               foreach (beat_order_q[i]) begin
                    if (i) s = {s, ", "};
                    s = {s, $sformatf("%0d", beat_order_q[i])};
               end
               s = {s, "}"};
               `uvm_info("AXI3_BFM", $sformatf("Beat-level RID order   = %s", s), apb2axi_verbosity)
          end
     endfunction

endclass