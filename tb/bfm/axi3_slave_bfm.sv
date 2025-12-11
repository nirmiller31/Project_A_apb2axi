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
//   - linear (default)            : AR handled immediately (blocking do_read)
//   - outstanding (+OUTSTANDING_READS)
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
     typedef enum int { MODE_LINEAR = 0,
                         MODE_OUTSTANDING = 1,
                         MODE_EXTREME = 2 } read_mode_e;

     read_mode_e read_mode = MODE_LINEAR;

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
               `uvm_info("AXI3_BFM", "Read mode: EXTREME_OUTSTANDING", UVM_NONE)
          end
          else if ($test$plusargs("OUTSTANDING_READS")) begin
               read_mode = MODE_OUTSTANDING;
               `uvm_info("AXI3_BFM", "Read mode: OUTSTANDING_READS", UVM_NONE)
          end
          else begin
               read_mode = MODE_LINEAR;
               `uvm_info("AXI3_BFM", "Read mode: LINEAR (default)", UVM_NONE)
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

               // Pick a random outstanding burst
               idx = $urandom_range(0, active_reads.size()-1);
               ar = active_reads[idx];

               // RANDOM latency before issuing the beat (optional)
               repeat ($urandom_range(0,3)) @(posedge vif.ACLK);

               // ======== SEND ONE R BEAT ========
               if (ar.mem_idx < MEM_DEPTH)
                    rdata = MEM[ar.mem_idx];
               else
                    rdata = '0;

                    `uvm_info("AXI3_BFM", $sformatf("TOOK READ: idx=0x%0d rdata=%0h", idx, rdata), UVM_NONE)

               vif.RID    <= ar.id;
               vif.RDATA  <= rdata;
               vif.RRESP  <= 2'b00;
               vif.RLAST  <= (ar.beats_left == 1);
               vif.RVALID <= 1'b1;

               // Wait for RREADY
               do @(posedge vif.ACLK);
               while (!vif.RREADY && vif.ARESETn);

               vif.RVALID <= 0;

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

          `uvm_info("AXI3_BFM","BFM is alive and ready", UVM_NONE)

          if (read_mode == MODE_EXTREME) begin         // Start R driver for outstanding modes
               fork
                    drive_read_queue();
               join_none
          end

          forever begin
               @(posedge vif.ACLK);

               // Always ready for address
               vif.ARREADY <= 1;
               vif.AWREADY <= 1;

               // Always ready for write data
               vif.WREADY  <= 1;

               // ========= READ ADDRESS =========
               if (vif.ARVALID && vif.ARREADY) begin
                    automatic read_req_t req;
                    req.addr            = vif.ARADDR;
                    req.len             = vif.ARLEN;
                    req.size            = vif.ARSIZE;
                    req.id              = vif.ARID;
                    req.burst           = vif.ARBURST;
`uvm_info("AXI3_BFM",
  $sformatf("AR HANDSHAKE: id=%0d addr=0x%0h len=%0d time=%0t",
            req.id, req.addr, req.len, $time),
  UVM_NONE)
                    case (read_mode)
                    MODE_LINEAR: begin
                        
                        do_read(req.addr, req.len, req.size, req.id, req.burst);
                    end

                    MODE_OUTSTANDING: begin
                         fork
                              begin
                                   // repeat ($urandom_range(0,10)) @(posedge vif.ACLK);
                                   do_read(req.addr, req.len, req.size, req.id, req.burst);
                              end
                         join_none
                    end
                    MODE_EXTREME: begin
                         arx.addr       = req.addr;
                         arx.beats_left = req.len + 1;
                         arx.size       = req.size;
                         arx.id         = req.id;
                         arx.burst      = req.burst;

                         arx.mem_idx = addr2idx(req.addr);


                         `uvm_info("AXI3_BFM", $sformatf("PUSHING READ: addr=0x%0h beats=%0d size=%0d id=%0d, idx=%d", arx.addr, arx.beats_left, arx.size, arx.id, arx.mem_idx), UVM_MEDIUM)
                         active_reads.push_back(arx);                    
                    end
                endcase

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
          logic [AXI_ADDR_W-1:0]  araddr,
          logic [3:0]             arlen,
          logic [2:0]             arsize,
          logic [AXI_ID_W-1:0]    arid,
          logic [1:0]             arburst
     );
          int unsigned            idx;
          mem_word_t              rdata;

          int unsigned beats          = arlen + 1;
          int unsigned bytes_per_beat = (1 << arsize);

          idx = addr2idx(araddr);

          `uvm_info("AXI3_BFM", $sformatf("READ: addr=0x%0h beats=%0d size=%0d id=%0d", araddr, beats, bytes_per_beat, arid), UVM_MEDIUM)

          vif.RVALID <= 1'b0;
          vif.RLAST  <= 1'b0;

          for (int i = 0; i < beats; i++) begin

               if (idx < MEM_WORDS)
                    rdata = MEM[idx];
               else
                    rdata = '0;            

               @(posedge vif.ACLK);
               vif.RID    <= arid;
               vif.RDATA  <= rdata;
               vif.RRESP  <= 2'b00;            // OKAY, simulate later
               vif.RLAST  <= (i == beats-1);
               vif.RVALID <= 1'b1;

               // Backpressure-safe wait
               do @(posedge vif.ACLK);
               while (!vif.RREADY && vif.ARESETn);

               vif.RVALID <= 1'b0;

               if (read_mode != MODE_LINEAR) begin
                    beat_order_q.push_back(arid);
                    if (i == beats-1) burst_order_q.push_back(arid);
               end

               if (arburst == 2'b01) begin // INCR
                    idx++;
               end
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
               `uvm_info("AXI3_BFM",
                         $sformatf("Burst completion RID order = %s", s),
                         UVM_NONE)
          end

          if (beat_order_q.size() > 0) begin
               s = "{";
               foreach (beat_order_q[i]) begin
                    if (i) s = {s, ", "};
                    s = {s, $sformatf("%0d", beat_order_q[i])};
               end
               s = {s, "}"};
               `uvm_info("AXI3_BFM",
                         $sformatf("Beat-level RID order   = %s", s),
                         UVM_NONE)
          end
     endfunction

endclass