//------------------------------------------------------------------------------
// Outstanding AR issue + randomized interleaved drain (APB-word granularity)
//------------------------------------------------------------------------------

class apb2axi_read_seq extends apb2axi_base_seq;
     `uvm_object_utils(apb2axi_read_seq)

     // -------------------------------
     // Knobs
     // -------------------------------
     localparam int unsigned NUM_TXNS_MAX = TAG_NUM;

     typedef struct {
          bit [TAG_W-1:0]        tag;
          bit [AXI_ADDR_W-1:0]   addr;
          bit [AXI_LEN_W-1:0]    len;               // beats-1
          bit [AXI_SIZE_W-1:0]   size;
          int unsigned           beats;             // len+1
          int unsigned           apb_words_per_beat;
          int unsigned           total_apb_words;   // beats * APB_WORDS_PER_AXI_BEAT
          int unsigned           drained_words;     // APB words drained so far
     } rd_txn_t;

     typedef struct {
          int unsigned           step;
          int unsigned           txn;
          bit [TAG_W-1:0]        tag;
          int unsigned           word_idx;
          bit [APB_DATA_W-1:0]   got32;
          bit [APB_DATA_W-1:0]   exp32;
     } drain_evt_t;

     function new(string name="apb2axi_read_seq");
          super.new(name);
     endfunction

     // =================================================
     // expected model
     // =================================================
     function automatic bit [APB_DATA_W-1:0] calc_expected_rdata(
          bit [63:0]            base_addr,
          bit [AXI_SIZE_W-1:0]  size,
          int                   word_idx
     );
          int unsigned bytes_per_beat;
          int unsigned apb_words_per_beat;
          int unsigned beat_i;
          int unsigned slice_i;

          bit [63:0] beat_addr;
          bit [AXI_DATA_W-1:0] rdata64;
          bit [APB_DATA_W-1:0] w;

          // AXI semantics
          bytes_per_beat     = (1 << int'(size));                 // 1,2,4,8 for size 0..3 (64b bus)
          apb_words_per_beat = (bytes_per_beat + 3) / 4;          // ceil(bytes/4): 1 for 1/2/4B, 2 for 8B

          beat_i  = word_idx / apb_words_per_beat;
          slice_i = word_idx % apb_words_per_beat;

          // Beat start address (INCR)
          beat_addr = base_addr + (beat_i * bytes_per_beat);

          // Build expected RDATA (low bytes filled, rest zero)
          rdata64 = '0;
          for (int b = 0; b < int'(bytes_per_beat); b++) begin
               bit [63:0] a;
               int unsigned idx;
               int unsigned byte_off;
               bit [7:0]    byt;

               a        = beat_addr + b;
               idx      = addr2idx(a);          // your MEM is 8-byte words (>>3)
               byte_off = a[2:0];               // byte within the 64-bit word

               if (idx < MEM_WORDS)
                    byt = MEM[idx][8*byte_off +: 8];
               else
                    byt = 8'h00;

               rdata64[8*b +: 8] = byt;         // little-endian placement inside the beat
          end

          // Slice to APB 32-bit word
          if (slice_i == 0) w = rdata64[31:0];
          else              w = rdata64[63:32];

          return w;
     endfunction

     virtual task body();
          uvm_phase phase;

          int unsigned num_txns;

          rd_txn_t txns[NUM_TXNS_MAX];

          int eligible[$];
          int pick_i;
          int tries;

          bit [APB_DATA_W-1:0] got32;
          bit [APB_DATA_W-1:0] exp32;
          bit slverr;

          bit done, error;
          bit [1:0] resp;
          bit [7:0] num_beats_hw;

          int unsigned global_step;

          drain_evt_t drain_q[$];

          phase = get_starting_phase();
          if (phase != null) phase.raise_objection(this);

          num_txns    = $urandom_range(1, NUM_TXNS_MAX);
          global_step = 0;

          `uvm_info("RD_SEQ", $sformatf("Start READ outstanding+interleaved : num_txns=%0d", num_txns), UVM_NONE)

          // -----------------------------------------
          // 1) Plan txns
          // -----------------------------------------
          for (int i = 0; i < int'(num_txns); i++) begin
               txns[i].tag             = i[TAG_W-1:0];
               txns[i].addr            = rand_addr_in_range_aligned();
               txns[i].len             = $urandom_range(0, MAX_BEATS_NUM-2);
               txns[i].size            = $urandom_range(0, $clog2(AXI_DATA_W/8)); // 0..3 for 64b
               txns[i].beats           = axi_beats_from_len(txns[i].len);
               txns[i].apb_words_per_beat = apb_words_per_beat_from_size(txns[i].size);
               txns[i].total_apb_words = txns[i].beats * txns[i].apb_words_per_beat;
               txns[i].drained_words   = 0;
               `uvm_info("RD_SEQ", $sformatf("PLAN: TXN=%0d TAG=%0d ADDR=0x%0h LEN=%0d SIZE=%0d (beats=%0d apb_words=%0d apb_words_per_beat=%0d)",i, txns[i].tag, txns[i].addr, txns[i].len, txns[i].size, txns[i].beats, txns[i].total_apb_words, txns[i].apb_words_per_beat), UVM_NONE)
          end

          // -----------------------------------------
          // 2) Issue all ARs first
          // -----------------------------------------
          for (int i = 0; i < int'(num_txns); i++) begin
               `uvm_info("RD_AR",$sformatf("ISSUE_AR: TXN=%0d TAG=%0d ADDR=0x%0h LEN=%0d, SIZE=%0d", i, txns[i].tag, txns[i].addr, txns[i].len, txns[i].size), UVM_NONE)
               program_read_cmd(txns[i].len, txns[i].size);
               program_addr(txns[i].addr);
          end

          #($urandom_range(0, 5000));

          // -----------------------------------------
          // 3) Randomized interleaved drain (APB-word granularity)
          // -----------------------------------------
		while (1) begin
			eligible.delete();

			for (int i = 0; i < int'(num_txns); i++) begin
				if (txns[i].drained_words < txns[i].total_apb_words)
					eligible.push_back(i);
			end

			if (eligible.size() == 0)
				break;

			pick_i = eligible[$urandom_range(0, eligible.size()-1)];

			read_status(txns[pick_i].tag, done, error, resp, num_beats_hw);
			if (error) begin
                    print_drain_order(drain_q);
                    `uvm_fatal("RD_SEQ", $sformatf("TAG %0d ERROR while draining resp=%0d",txns[pick_i].tag, resp))
               end

			pop_rd_apb_word(txns[pick_i].tag, got32, slverr);

               if(slverr) begin
                    #($urandom_range(10, 120));
                    `uvm_info("RD_AR",$sformatf("I jumped"), UVM_NONE)
                    continue;
               end

			exp32 = calc_expected_rdata(txns[pick_i].addr, txns[pick_i].size, txns[pick_i].drained_words);

               drain_q.push_back('{
                    step    : global_step,
                    txn     : pick_i,
                    tag     : txns[pick_i].tag,
                    word_idx: txns[pick_i].drained_words,
                    got32   : got32,
                    exp32   : exp32
               });

               `uvm_info("RD_DRAIN", $sformatf("DRAIN step=%0d TXN=%0d TAG=%0d word=%0d/%0d size=%0d got=0x%08x exp=0x%08x", global_step, pick_i, txns[pick_i].tag, txns[pick_i].drained_words, txns[pick_i].total_apb_words-1, txns[pick_i].size, got32, exp32), UVM_NONE)

               if (got32 !== exp32) begin
                    print_drain_order(drain_q);
                    `uvm_fatal("RD_CMP", $sformatf("MISMATCH TXN=%0d TAG=%0d addr=0x%0h size=%0d word=%0d got=0x%08x exp=0x%08x", pick_i, txns[pick_i].tag, txns[pick_i].addr, txns[pick_i].size, txns[pick_i].drained_words, got32, exp32))
               end

			txns[pick_i].drained_words++;
			global_step++;

			#($urandom_range(10, 120));
		end

          print_drain_order(drain_q);
          `uvm_info("RD_SEQ", "Outstanding + interleaved READ test PASSED", UVM_MEDIUM)

          if (phase != null) phase.drop_objection(this);
     endtask

     task automatic print_drain_order(drain_evt_t q[$]);
          `uvm_info("RD_ORDER", $sformatf("Drain order summary: %0d pops", q.size()), UVM_NONE)
          foreach (q[i]) begin
               `uvm_info("RD_ORDER", $sformatf("step=%0d  txn=%0d  tag=%0d  word=%0d  got=0x%08x  exp=0x%08x", q[i].step, q[i].txn, q[i].tag, q[i].word_idx, q[i].got32, q[i].exp32), UVM_NONE)
          end
     endtask

endclass