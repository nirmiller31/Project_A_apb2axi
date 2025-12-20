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
          int unsigned           beats;             // len+1
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

     virtual task body();
          uvm_phase phase;

          int unsigned num_txns;

          rd_txn_t txns[NUM_TXNS_MAX];

          int eligible[$];
          int pick_i;
          int last_pick;
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
          last_pick   = -1;
          global_step = 0;

          `uvm_info("RD_SEQ", $sformatf("Start READ outstanding+interleaved : num_txns=%0d", num_txns), UVM_NONE)

          // -----------------------------------------
          // 1) Plan txns
          // -----------------------------------------
          for (int i = 0; i < int'(num_txns); i++) begin
               txns[i].tag            = i[TAG_W-1:0];
               txns[i].addr           = rand_addr_in_range_aligned();
               txns[i].len            = $urandom_range(0, MAX_BEATS_NUM-2);
               txns[i].beats          = axi_beats_from_len(txns[i].len);
               txns[i].total_apb_words= txns[i].beats * apb_words_per_axi_beat();
               txns[i].drained_words  = 0;
               `uvm_info("RD_SEQ", $sformatf("PLAN: TXN=%0d TAG=%0d ADDR=0x%0h LEN=%0d (beats=%0d apb_words=%0d)",i, txns[i].tag, txns[i].addr, txns[i].len, txns[i].beats, txns[i].total_apb_words), UVM_NONE)
          end

          // -----------------------------------------
          // 2) Issue all ARs first
          // -----------------------------------------
          for (int i = 0; i < int'(num_txns); i++) begin
               `uvm_info("RD_AR",$sformatf("ISSUE_AR: TXN=%0d TAG=%0d ADDR=0x%0h LEN=%0d", i, txns[i].tag, txns[i].addr, txns[i].len), UVM_NONE)
               program_read_cmd(txns[i].len);
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

			exp32 = calc_expected_rdata(txns[pick_i].addr, txns[pick_i].drained_words);

               drain_q.push_back('{
                    step    : global_step,
                    txn     : pick_i,
                    tag     : txns[pick_i].tag,
                    word_idx: txns[pick_i].drained_words,
                    got32   : got32,
                    exp32   : exp32
               });

			`uvm_info("RD_DRAIN", $sformatf("DRAIN step=%0d TXN=%0d TAG=%0d word=%0d/%0d got=0x%08x exp=0x%08x", global_step, pick_i, txns[pick_i].tag, txns[pick_i].drained_words, txns[pick_i].total_apb_words-1, got32, exp32), UVM_NONE)

			if (got32 !== exp32) begin
                    print_drain_order(drain_q);
				`uvm_fatal("RD_CMP", $sformatf("MISMATCH TXN=%0d TAG=%0d addr=0x%0h word=%0d got=0x%08x exp=0x%08x", pick_i, txns[pick_i].tag, txns[pick_i].addr, txns[pick_i].drained_words, got32, exp32))
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