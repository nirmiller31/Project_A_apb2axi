import apb2axi_pkg::*;

module apb2axi_reg #(
     parameter int AXI_ADDR_W = AXI_ADDR_W,
     parameter int APB_ADDR_W = APB_ADDR_W
)(
     // APB Signals
     input  logic                  pclk,
     input  logic                  presetn,
     input  logic                  psel,
     input  logic                  penable,
     input  logic                  pwrite,
     input  logic [APB_ADDR_W-1:0] paddr,
     input  logic [APB_DATA_W-1:0] pwdata,
     output logic                  pready,
     output logic                  pslverr,
     output logic [APB_DATA_W-1:0] prdata,

     // Outputs to Directory
     output logic                  commit_pulse,
     output directory_entry_t      dir_alloc_entry,

     // Inputs from response_handler (PCLK domain)
     input  logic                  rd_status_valid,
     input  logic                  rd_status_error,
     input  logic [1:0]            rd_status_resp,
     input  logic [TAG_W-1:0]      rd_status_tag,
     input  logic [7:0]            rd_status_num_beats,
     input  logic                  rd_status_is_write,

     // From/To RDF (data beats)
     input  logic                  rdf_data_valid,
     output logic                  rdf_data_ready,     
     input  logic [APB_DATA_W-1:0] rdf_data_out,
     input  logic                  rdf_data_last,
     output logic                  rdf_data_req,
     output logic [TAG_W-1:0]      rdf_data_req_tag,

     // Ack back to Directory (SW consumed completion)
     output logic                  dir_consumed_valid,

     output logic [TAG_W-1:0]      status_tag_sel,
     input directory_entry_t       status_dir_entry,
     input entry_state_e           status_dir_state
);

     // ----------------------------------------------------------------
     // Local address decode (word-based, 32-bit aligned)
     //  0x00 : ADDR_LO
     //  0x04 : ADDR_HI
     //  0x08 : CMD
     //  0x0C : RD_STATUS (RO)
     //  0x10 : RD_DATA   (RO, streaming)
     //  0x14 : TAG_TO_CONSUME
     // ----------------------------------------------------------------
     localparam REG_ADDR_ADDR_LO   = 'h00;
     localparam REG_ADDR_ADDR_HI   = 'h04;
     localparam REG_ADDR_CMD       = 'h08;
     localparam REG_ADDR_RD_STATUS = 'h0C;
     localparam REG_ADDR_RD_DATA   = 'h10;
     localparam REG_RD_TAG_SEL     = 'h14;

     logic sel_addr_lo, sel_addr_hi, sel_cmd, sel_rd_status, sel_rd_data, sel_tag_to_consume;

     logic          addr_lo_we, addr_lo_we_d;
     logic [31:0]   addr_lo_rd_val;
     logic          addr_hi_we;
     logic [31:0]   addr_hi_rd_val;
     logic          cmd_we;
     logic [31:0]   cmd_rd_val;
     logic          tag_to_consume_we;
     logic [31:0]   tag_to_consume_rd_val;

     logic          rd_status_re;

     assign pslverr                = 1'b0;

     // Outputs for Directory
     assign dir_alloc_entry.addr        = {addr_hi_rd_val, addr_lo_rd_val};
     assign dir_alloc_entry.len         = cmd_rd_val[7:0];
     assign dir_alloc_entry.size        = cmd_rd_val[10:8];
     assign dir_alloc_entry.is_write    = cmd_rd_val[31];

     assign sel_addr_lo                 = ({paddr[4:2], 2'b00} == REG_ADDR_ADDR_LO);
     assign sel_addr_hi                 = ({paddr[4:2], 2'b00} == REG_ADDR_ADDR_HI);
     assign sel_cmd                     = ({paddr[4:2], 2'b00} == REG_ADDR_CMD);
     assign sel_rd_status               = ({paddr[4:2], 2'b00} == REG_ADDR_RD_STATUS);
     assign sel_rd_data                 = ({paddr[4:2], 2'b00} == REG_ADDR_RD_DATA);
     assign sel_tag_to_consume          = ({paddr[4:2], 2'b00} == REG_RD_TAG_SEL);  

     // Write enables for RW regs
     assign addr_lo_we                  = psel & penable & pwrite & sel_addr_lo;
     assign addr_hi_we                  = psel & penable & pwrite & sel_addr_hi;
     assign cmd_we                      = psel & penable & pwrite & sel_cmd;
     assign tag_to_consume_we           = psel & penable & pwrite & sel_tag_to_consume;

     // READ enable for RD_STATUS (used for consume)
     assign rd_status_re                = psel && penable && !pwrite && sel_rd_status;

     // ----------------------------------------------------------------
     // APB read mux (combinational PRDATA)
     // ----------------------------------------------------------------
     always_comb begin
          prdata = '0;
          if (!pwrite && psel) begin
               unique case (1'b1)
                    sel_addr_lo:   prdata = addr_lo_rd_val;
                    sel_addr_hi:   prdata = addr_hi_rd_val;
                    sel_cmd:       prdata = cmd_rd_val;

                    // KEEP YOUR ORIGINAL LAYOUT (TB IS ALIGNED TO THIS)
                    sel_rd_status: prdata = {
                         16'b0,
                         status_dir_entry.state == DIR_ST_DONE,       // bit 15
                         status_dir_entry.state == DIR_ST_ERROR,      // bit 14
                         status_dir_entry.resp,                       // [13:12]
                         status_dir_entry.num_beats,                  // [11:4]
                         status_dir_entry.tag                         // [3:0]
                    };

                    sel_rd_data:   prdata = rdf_data_out[APB_DATA_W-1:0];

                    default:       prdata = '0;
               endcase
          end
     end


     typedef enum logic [1:0] {
          S_IDLE,
          S_ARMED,
          S_STATUS_READ,
          S_DATA_READ
     } apb_state_e;

     apb_state_e state, next_state;
     logic [TAG_W-1:0] armed_tag, armed_tag_next;
     logic pready_next;
     logic rdf_data_req_next;
     logic [TAG_W-1:0] rdf_data_req_tag_next;
     logic dir_consumed_valid_next;

     // ----------------------------------------------------------------
     // APB pready + RDF handshake + SW consume pulse  (FSM)
     // ----------------------------------------------------------------
     always_ff @(posedge pclk) begin
          if (!presetn) begin
               state               <= S_IDLE;
               armed_tag           <= '0;

               pready              <= 1'b1;
               rdf_data_req        <= 1'b0;
               rdf_data_req_tag    <= '0;

               dir_consumed_valid  <= 1'b0;
          end else begin
               state            <= next_state;
               armed_tag        <= armed_tag_next;

               pready           <= pready_next;
               rdf_data_req     <= rdf_data_req_next;
               rdf_data_req_tag <= rdf_data_req_tag_next;

               dir_consumed_valid <= dir_consumed_valid_next;
          end
     end

     assign rdf_data_ready = psel && penable && !pwrite && sel_rd_data;

     assign status_tag_sel = tag_to_consume_rd_val;


     always_comb begin

          next_state               = state;
          armed_tag_next           = armed_tag;

          pready_next              = 1'b1;
          rdf_data_req_next        = 1'b0;
          rdf_data_req_tag_next    = rdf_data_req_tag;

          dir_consumed_valid_next = 1'b0;

          // RD_DATA FSM
          unique case (state)
               S_IDLE: begin
                    if (psel && penable && pwrite && sel_tag_to_consume) begin
                         next_state                    = S_STATUS_READ;
                    end
               end
               S_STATUS_READ: begin
                    if (psel && penable && !pwrite && sel_rd_status) begin
                         rdf_data_req_next             = 1'b1;
                         rdf_data_req_tag_next         = tag_to_consume_rd_val;
                         next_state                    = S_ARMED;
                    end
               end
               S_ARMED: begin
                    if (rdf_data_valid) begin
                         next_state                    = S_DATA_READ;
                         pready_next                   = 1'b1;
                         rdf_data_req_next             = 1'b0;                         
                    end
                    else begin
                         pready_next                   = 1'b0;     // keep stalling
                    end
               end
               S_DATA_READ: begin                                // Waiting for handler to supply rdf_data_valid
                    if (psel && penable && !pwrite && sel_rd_data) begin
                         if (rdf_data_valid) begin                    // This cycle completes the stalled APB transfer
                              pready_next = 1'b0;                     // Master will sample PRDATA in this cycle
                              if (rdf_data_last) begin
                                   next_state = S_IDLE; 
                                   dir_consumed_valid_next  = 1'b1;
                              end
                              else begin 
                                   next_state = S_ARMED;
                                   rdf_data_req_next             = 1'b1;
                              end
                         end
                         // else begin
                              
                         // end
                    end
               end

               default: begin
                    next_state  = S_IDLE;
               end
          endcase
     end

     // ----------------------------------------------------------------
     // Actual register writes (ADDR_LO / ADDR_HI / CMD)
     // ----------------------------------------------------------------
     always_ff @(posedge pclk) begin
          if (!presetn) begin
               addr_lo_rd_val                                         <= '0;
               addr_hi_rd_val                                         <= '0;
               cmd_rd_val                                             <= '0;
               tag_to_consume_rd_val                                  <= '0;
          end 
          else begin
               if (addr_lo_we)               addr_lo_rd_val           <= pwdata;
               if (addr_hi_we)               addr_hi_rd_val           <= pwdata;
               if (cmd_we)                   cmd_rd_val               <= pwdata;
               if (tag_to_consume_we)        tag_to_consume_rd_val    <= pwdata;
          end
     end

     // ----------------------------------------------------------------
     // Single-cycle commit_pulse on ADDR_LO write
     // ----------------------------------------------------------------
     always_ff @(posedge pclk) begin               
          if (!presetn) begin
               addr_lo_we_d <= 1'b0;
               commit_pulse <= 1'b0;
          end 
          else begin
               addr_lo_we_d <= addr_lo_we;
               commit_pulse <= addr_lo_we & ~addr_lo_we_d;
          end
     end

     // ----------------------------------------------------------------
     // Debug
     // ----------------------------------------------------------------
     always_ff @(posedge pclk) begin
          if (addr_lo_we)
               $display("%t [REG_DBG] AddrLo Write Enable asserted at paddr=%h pwdata=%h",
                        $time, paddr, pwdata);

          // if (commit_pulse)
          //      $display("%t [REG] COMMIT addr=%h len=%0d size=%0d is_write=%0b",
          //               $time, addr, len, size, is_write);

          if (addr_lo_we || addr_hi_we || cmd_we)
               $display("%t [REGFILE] WRITE at addr=%h data=%h",
                        $time, paddr, pwdata);

          if (psel && penable && !pwrite && sel_rd_status) begin
               $display("%t [REG] RD_STATUS read: valid=%0b err=%0b resp=%0d tag=%0d beats=%0d",
                        $time, rd_status_valid, rd_status_error,
                        rd_status_resp, rd_status_tag, rd_status_num_beats);

               if ($test$plusargs("APB2AXI_REG_DEBUG")) begin
                    $display("%t [REG_DIRSTAT] tag_sel=%0d dir_state=%0d entry.state=%0d resp=%0d beats=%0d tag=%0d",
                             $time,
                             status_tag_sel,
                             status_dir_state,
                             status_dir_entry.state,
                             status_dir_entry.resp,
                             status_dir_entry.num_beats,
                             status_dir_entry.tag);
               end
          end
     end

endmodule