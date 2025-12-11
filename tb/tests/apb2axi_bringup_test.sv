
//------------------------------------------------------------------------------
// File          : apb2axi_bringup_test.sv
// Project       : APB2AXI
// Description   : Minimal directed UVM test for bring-up
//------------------------------------------------------------------------------

class apb2axi_bringup_test extends apb2axi_base_test;
    `uvm_component_utils(apb2axi_bringup_test)

     function new(string name = "apb2axi_bringup_test",
                    uvm_component parent = null);
          super.new(name, parent);
     endfunction

     task run_phase(uvm_phase phase);
          string                             seq_sel;
          apb2axi_bringup_seq                bringup_seq;
          apb2axi_read_bringup_seq           rd_bringup_seq;
          apb2axi_multiple_beat_read_seq     mb_rd_bringup_seq;
          apb2axi_read_drain_seq             rd_drain_bringup_seq;
          apb2axi_multiple_read_drain_seq    multiple_rd_drain_bringup_seq;
          apb2axi_reconsume_same_tag_seq     reconsume_same_tag_seq;

          phase.raise_objection(this);

          // Default = BRINGUP bringup if plusarg not given
          if (!$value$plusargs("APB2AXI_SEQ=%s", seq_sel)) seq_sel = "BRINGUP";

          `uvm_info("BRINGUP_TEST", $sformatf("Starting bring-up test, seq_sel=%s", seq_sel), apb2axi_verbosity)

          if (seq_sel.tolower() == "read") begin
               `uvm_info("BRINGUP_TEST", "Running READ bringup sequence", apb2axi_verbosity)
               rd_bringup_seq         = apb2axi_read_bringup_seq::type_id::create("rd_seq");
               rd_bringup_seq.m_env   = env;
               rd_bringup_seq.start(env.apb_ag.apb_seqr);
          end
          else if (seq_sel.tolower() == "mulread") begin
               `uvm_info("BRINGUP_TEST", "Running MULTIPLE BEAT READ bringup sequence", apb2axi_verbosity)
               mb_rd_bringup_seq         = apb2axi_multiple_beat_read_seq::type_id::create("rd_seq");
               mb_rd_bringup_seq.m_env   = env;
               mb_rd_bringup_seq.start(env.apb_ag.apb_seqr);
          end
          else if (seq_sel.tolower() == "readdrain") begin
               `uvm_info("BRINGUP_TEST", "Running READ DRAIN bringup sequence", apb2axi_verbosity)
               rd_drain_bringup_seq         = apb2axi_read_drain_seq::type_id::create("rd_seq");
               rd_drain_bringup_seq.m_env   = env;
               rd_drain_bringup_seq.start(env.apb_ag.apb_seqr);
          end
          else if (seq_sel.tolower() == "mul_read_drain") begin
               `uvm_info("BRINGUP_TEST", "Running MULTIPLE READ DRAIN bringup sequence", apb2axi_verbosity)
               multiple_rd_drain_bringup_seq         = apb2axi_multiple_read_drain_seq::type_id::create("rd_seq");
               multiple_rd_drain_bringup_seq.m_env   = env;
               multiple_rd_drain_bringup_seq.start(env.apb_ag.apb_seqr);
          end
          else if (seq_sel.tolower() == "recon") begin
               `uvm_info("BRINGUP_TEST", "Running CONSUME bringup sequence", apb2axi_verbosity)
               reconsume_same_tag_seq         = apb2axi_reconsume_same_tag_seq::type_id::create("rd_seq");
               reconsume_same_tag_seq.m_env   = env;
               reconsume_same_tag_seq.start(env.apb_ag.apb_seqr);
          end          
          else begin
               `uvm_info("BRINGUP_TEST", "Running (original) bringup sequence", apb2axi_verbosity)
               bringup_seq      = apb2axi_bringup_seq::type_id::create("wr_seq");
               bringup_seq.m_env = env;
               bringup_seq.start(env.apb_ag.apb_seqr);
          end

          `uvm_info("BRINGUP_TEST", "Bring-up sequence finished", apb2axi_verbosity)

          phase.drop_objection(this);
          
     endtask
endclass