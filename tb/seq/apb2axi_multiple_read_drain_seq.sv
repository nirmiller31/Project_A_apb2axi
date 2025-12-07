class apb2axi_multiple_read_drain_seq extends apb2axi_base_seq;
  `uvm_object_utils(apb2axi_multiple_read_drain_seq)

  localparam int REG_ADDR_LO   = 'h00;
  localparam int REG_ADDR_HI   = 'h04;
  localparam int REG_CMD       = 'h08;
  localparam int REG_RD_STATUS = 'h0C;
  localparam int REG_RD_DATA   = 'h10;

  // 4 target addresses + expected 64b data for each (single-beat reads)
  rand bit [63:0] addrs   [4];
  rand bit [63:0] exp_data[4];

  function new(string name = "apb2axi_multiple_read_drain_seq");
    super.new(name);
    // default example values – override from test if you want
    addrs[0] = 64'h0000_0000_0000_1000;
    addrs[1] = 64'h0000_0000_0000_1608;
    addrs[2] = 64'h0000_0000_0000_15B0;
    addrs[3] = 64'h0000_0000_0000_1420;
  endfunction

  // helper: program one read command (len=0 → 1 beat, size=3'd3 → 8 bytes)
  task program_read(int idx);
    bit [31:0] cmd, addr_hi, addr_lo;

    addr_lo = addrs[idx][31:0];
    addr_hi = addrs[idx][63:32];

    cmd             = '0;
    cmd[31]         = 1'b0;     // is_write = 0 → READ
    cmd[10:8]       = 3'd3;     // size = 8 bytes (log2 8)
    cmd[7:0]        = 8'd2;     // len = 0 → single beat

    apb_write_reg(REG_CMD,       cmd);
    apb_write_reg(REG_ADDR_HI,   addr_hi);
    apb_write_reg(REG_ADDR_LO,   addr_lo); // writing LO fires commit_pulse
  endtask

     //   helper: drain one 64b read result and compare
     task drain_and_check(int idx);
          bit [31:0] status, word32, exp32;
          int num_beats, total_words;
          int w, word_idx = 0;
          const int WORDS_PER_BEAT = AXI_DATA_W / APB_DATA_W;

          // wait for data ready
          // do begin
          //      apb_read_reg(REG_RD_STATUS, status);
          // end while (status[15] == 1'b0);

          num_beats = status[11:4];          // AXI beats from status
          // if (num_beats == 0)
          //      num_beats = 1; // len=0 case
          
          total_words = (num_beats + 1) * WORDS_PER_BEAT;

          for (w = 0; w < total_words; w++) begin
               apb_read_reg(REG_RD_DATA, word32); // one APB-sized word
               exp32 = calc_expected_rdata(addrs[idx], word_idx);
               if (word32 !== exp32)
                    `uvm_error("MULTI_READ", $sformatf("addr=%h word_idx=%0d EXP=%h GOT=%h", addrs[idx], word_idx, exp32, word32))
               else
                    `uvm_info("MULTI_READ", $sformatf("addr=%h word_idx=%0d OK: %h", addrs[idx], word_idx, word32), UVM_NONE)
               word_idx++;
          end
     endtask

     // Returns ONE APB word (32b) for a given AXI base_addr + APB word index
     function automatic bit [APB_DATA_W-1:0] calc_expected_rdata(bit [63:0] base_addr, int word_idx);

          const int WORDS_PER_BEAT = AXI_DATA_W / APB_DATA_W; // 2 for 64→32
          int unsigned base_idx;
          int unsigned axi_idx;
          int unsigned word_in_beat;
          mem_word_t   beat;

          // Same index computation as before, but per-transaction base_addr
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

  virtual task body();

  bit [31:0] status_0, status_1, status_2, status_3;
    `uvm_info(get_type_name(), "Starting 4-read queueing test", UVM_NONE)

    // -----------------------------
    // 1) Program 4 READ commands
    // -----------------------------
    foreach (addrs[i]) begin
      program_read(i);
    end

    // -----------------------------
    // 2) Let them queue / issue
    // -----------------------------
    #5000;

    // -----------------------------
    // 3) Drain data later via APB
    // -----------------------------
//     foreach (addrs[i]) begin
//           bit [31:0] status;
//           set_tag_to_consume(i);
//           apb_read_reg(REG_RD_STATUS, status);
//           drain_and_check(i);
//     end
     
     set_tag_to_consume(1);
     apb_read_reg(REG_RD_STATUS, status_1);
     drain_and_check(1);

     
     set_tag_to_consume(3);
     apb_read_reg(REG_RD_STATUS, status_3);
     drain_and_check(3);

     
     set_tag_to_consume(2);
     apb_read_reg(REG_RD_STATUS, status_2);
     drain_and_check(2);

     
     set_tag_to_consume(0);
     apb_read_reg(REG_RD_STATUS, status_0);
     drain_and_check(0);
  endtask

endclass