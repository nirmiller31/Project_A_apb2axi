class apb2axi_write_error_seq extends apb2axi_base_seq;
     `uvm_object_utils(apb2axi_write_error_seq)

     function new(string name="apb2axi_write_error_seq");
          super.new(name);
     endfunction

     task body();
          bit [AXI_ADDR_W-1:0]     addr;
          bit                      done, error;
          bit [1:0]                resp;
          bit [7:0]                num_beats;

          bit [TAG_W-1:0]          tag = 0;

          addr = rand_addr_in_range_aligned();

          program_write_cmd(0); // single beat
          program_addr(addr);

          // Push one APB word
          push_wr_apb_word(tag, 32'hDEAD_BEEF);

          // Inject write error at B channel
          m_env.axi_bfm.inject_write_error(tag, AXI_RESP_DECERR);

          wait_completion(tag);

          read_status(tag, done, error, resp, num_beats);

          `uvm_info(get_name(), $sformatf("WRITE ERROR: done=%0b err=%0b resp=%0d", done, error, resp), UVM_NONE)
     endtask
endclass