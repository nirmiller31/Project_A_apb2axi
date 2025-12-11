class apb2axi_multiple_read_drain_seq extends apb2axi_base_seq;
     `uvm_object_utils(apb2axi_multiple_read_drain_seq)

     localparam int REG_ADDR_LO   = 'h00;
     localparam int REG_ADDR_HI   = 'h04;
     localparam int REG_CMD       = 'h08;
     localparam int REG_RD_STATUS = 'h0C;
     localparam int REG_RD_DATA   = 'h10;

     // Number of reads to issue (you control it)
     rand int unsigned num_reads;
     rand bit [63:0]   addrs   [FIFO_DEPTH];    // support up to 16 outstanding
     rand bit [63:0]   exp_data[FIFO_DEPTH];

     constraint c_num_reads { num_reads inside {[1:FIFO_DEPTH]}; }

     constraint addr_range_c {
          foreach (addrs[i]) if (i < num_reads) {
               addrs[i] inside {
               [64'h0000_0000_0000_1000 : 64'h0000_0000_0000_17F8]
               };
               addrs[i][2:0] == 3'b000;   // 8-byte aligned
          }
     }

     function new(string name = "apb2axi_multiple_read_drain_seq");
          super.new(name);
     endfunction

     // ------------------------------
     // Helper: Program 1 read command
     // ------------------------------
     task program_read(int idx); bit [31:0] cmd, addr_hi, addr_lo;
          addr_lo = addrs[idx][31:0];
          addr_hi = addrs[idx][63:32];

          cmd        = '0;
          cmd[31]    = 1'b0;     // READ
          cmd[10:8]  = 3'd3;     // size=8 bytes
          cmd[7:0]   = 8'd2;     // len=0 → 1 AXI beat

          apb_write_reg(REG_CMD,     cmd);
          apb_write_reg(REG_ADDR_HI, addr_hi);
          apb_write_reg(REG_ADDR_LO, addr_lo);   // commit_pulse
     endtask

     // ------------------------------
     // Helper: Drain + check data
     // ------------------------------
     task drain_and_check(int idx);
          bit [31:0] status, word32, exp32;
          int num_beats, total_words;
          int word_idx = 0;
          // Decode RD_STATUS fields exactly as in regfile
          bit [3:0]  st_tag;
          bit [7:0]  st_beats;
          bit [1:0]  st_resp;
          bit        st_err;
          bit        st_valid;
          const int WORDS_PER_BEAT = AXI_DATA_W / APB_DATA_W;

          // poll until valid (2-cycle hazard safe)
          // repeat (2) 
          apb_read_reg(REG_RD_STATUS, status);

          st_tag   = status[3:0];
          st_beats = status[11:4];
          st_resp  = status[13:12];
          st_err   = status[14];
          st_valid = status[15];
          `uvm_info("MULTI_READ", $sformatf("RD_STATUS RAW=0x%08h  | valid=%0b err=%0b resp=%0d tag=%0d beats=%0d", status, st_valid, st_err, st_resp, st_tag, st_beats ), UVM_NONE)

          total_words = (st_beats + 1) * WORDS_PER_BEAT;

          for (int w = 0; w < total_words; w++) begin
               apb_read_reg(REG_RD_DATA, word32);
               exp32 = calc_expected_rdata(addrs[idx], word_idx);

               if (word32 !== exp32)
               `uvm_error("MULTI_READ", $sformatf("addr=%h word_idx=%0d EXP=%h GOT=%h", addrs[idx], word_idx, exp32, word32))
               else
               `uvm_info("MULTI_READ", $sformatf("addr=%h word_idx=%0d OK: %h", addrs[idx], word_idx, word32), UVM_NONE)

               word_idx++;
          end
     endtask

     // ------------------------------
     // Expected 32-bit word
     // ------------------------------
     function automatic bit [APB_DATA_W-1:0] calc_expected_rdata(bit [63:0] base_addr, int word_idx);

          const int WORDS_PER_BEAT = AXI_DATA_W / APB_DATA_W;
          int unsigned base_idx;
          int unsigned axi_idx;
          int unsigned word_in_beat;
          mem_word_t beat;

          base_idx     = addr2idx(base_addr);
          axi_idx      = base_idx + (word_idx / WORDS_PER_BEAT);
          word_in_beat = word_idx % WORDS_PER_BEAT;

          if (axi_idx >= MEM_WORDS)
               return '0;

          beat = MEM[axi_idx];

          case (word_in_beat)
               0: return beat[31:0];
               1: return beat[63:32];
               default: return '0;
          endcase
          
     endfunction

     // ============================================================
     //                       MAIN BODY
     // ============================================================
     virtual task body();
          bit [31:0] status;
          int drain_order[$];

          if (!randomize()) begin
               `uvm_fatal("SEQ", "Randomization failed")
          end

          `uvm_info(get_type_name(), $sformatf("Starting multi-read test, num_reads=%0d", num_reads), UVM_NONE)

          // --------------------------------------
          // 1) Program N READ commands
          // --------------------------------------
          for (int i = 0; i < num_reads; i++) begin
               program_read(i);
               #50;
          end

          #5000;

          // --------------------------------------
          // 2) Drain in ANY ORDER the test desires
          // --------------------------------------

          for (int i = 0; i < num_reads; i++)
               drain_order.push_back(i);
          drain_order.shuffle();                  // Allow randomized draining order

          `uvm_info(get_type_name(), $sformatf("Drain order = %p", drain_order), UVM_NONE)

          foreach (drain_order[j]) begin
               int tag = drain_order[j];
               set_tag_to_consume(tag);
               // apb_read_reg(REG_RD_STATUS, status);
               drain_and_check(tag);
               `uvm_info("MULTI_READ", $sformatf("tag=%h Consumed OK", tag), UVM_NONE)
          end
     endtask

endclass