import apb2axi_pkg::*;

module apb2axi_reg #()(
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

     output logic                  reg_dir_alloc_vld,
     output directory_entry_t      reg_dir_alloc_entry,

     output logic                  reg_dir_entry_consumed,

     output logic [TAG_W-1:0]      reg_dir_tag_sel,
     input directory_entry_t       reg_dir_entry,
     input entry_state_e           reg_dir_entry_state,

     input  logic                  rdf_reg_data_vld,
     output logic                  rdf_reg_data_rdy,     
     input  logic [APB_DATA_W-1:0] rdf_reg_data_out,
     input  logic                  rdf_reg_data_last,
     output logic                  rdf_reg_data_req,
     output logic [TAG_W-1:0]      rdf_reg_data_req_tag
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
     logic [APB_REG_W-1:0]         addr_lo_rd_val;
     logic [APB_REG_W-1:0]         addr_hi_rd_val;
     logic [APB_REG_W-1:0]         cmd_rd_val;
     logic [APB_REG_W-1:0]         tag_to_consume_rd_val;
     logic [APB_REG_W-1:0]         sts_rd_val;
     logic [APB_REG_W-1:0]         data_rd_val;

     logic                         sel_addr_lo, sel_addr_hi, sel_cmd, sel_rd_status, sel_rd_data, sel_tag_to_consume;
     logic                         addr_lo_we, addr_lo_we_d, addr_hi_we, cmd_we, tag_to_consume_we;
     logic                         rd_status_re, rd_data_re;

     logic                         new_tag_set;

     assign pslverr                = 1'b0;   // FIXME error handling
     
     assign sel_addr_lo            = ({paddr[4:2], 2'b00} == REG_ADDR_ADDR_LO);
     assign sel_addr_hi            = ({paddr[4:2], 2'b00} == REG_ADDR_ADDR_HI);
     assign sel_cmd                = ({paddr[4:2], 2'b00} == REG_ADDR_CMD);
     assign sel_rd_status          = ({paddr[4:2], 2'b00} == REG_ADDR_RD_STATUS);
     assign sel_rd_data            = ({paddr[4:2], 2'b00} == REG_ADDR_RD_DATA);
     assign sel_tag_to_consume     = ({paddr[4:2], 2'b00} == REG_ADDR_RD_TAG_SEL);  

     // Write enables for RW regs
     assign addr_lo_we             = psel & penable & pwrite & sel_addr_lo;
     assign addr_hi_we             = psel & penable & pwrite & sel_addr_hi;
     assign cmd_we                 = psel & penable & pwrite & sel_cmd;
     assign tag_to_consume_we      = psel & penable & pwrite & sel_tag_to_consume;

     // READ enable for RD_STATUS (used for consume)
     assign rd_status_re           = psel && penable && !pwrite && sel_rd_status;
     assign rd_data_re             = psel && penable && !pwrite && sel_rd_data;

     // ----------------------------------------------------------------
     // APB read mux
     // ----------------------------------------------------------------
     always_comb begin
          prdata = '0;
          if (!pwrite && psel) begin
               unique case (1'b1)
                    sel_addr_lo:   prdata = addr_lo_rd_val;
                    sel_addr_hi:   prdata = addr_hi_rd_val;
                    sel_cmd:       prdata = cmd_rd_val;
                    sel_rd_status: prdata = sts_rd_val;
                    sel_rd_data:   prdata = data_rd_val;
                    default:       prdata = '0;
               endcase
          end
     end

     // ----------------------------------------------------------------
     // APB write mux
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

     assign rdf_reg_data_rdy                 = psel && penable && !pwrite && sel_rd_data;
     assign new_tag_set                      = psel && penable && pwrite && sel_tag_to_consume;
     assign reg_dir_tag_sel                  = tag_to_consume_rd_val;
     assign data_rd_val                      = rdf_reg_data_out[APB_DATA_W-1:0];
     assign sts_rd_val                       = {
                                                  16'b0,
                                                  reg_dir_entry.state == DIR_ST_DONE,       // bit 15
                                                  reg_dir_entry.state == DIR_ST_ERROR,      // bit 14
                                                  reg_dir_entry.resp,                       // [13:12]
                                                  reg_dir_entry.num_beats,                  // [11:4]
                                                  reg_dir_entry.tag                         // [3:0]
                                             };
     // Outputs for Directory fields
     assign reg_dir_alloc_entry.is_write     = cmd_rd_val[DIR_ENTRY_ISWRITE_HI : DIR_ENTRY_ISWRITE_LO];     
     assign reg_dir_alloc_entry.addr         = {addr_hi_rd_val, addr_lo_rd_val};
     assign reg_dir_alloc_entry.len          = cmd_rd_val[DIR_ENTRY_LEN_HI : DIR_ENTRY_LEN_LO];
     assign reg_dir_alloc_entry.size         = cmd_rd_val[DIR_ENTRY_SIZE_HI : DIR_ENTRY_SIZE_LO];
     assign reg_dir_alloc_entry.burst        = '0;
     assign reg_dir_alloc_entry.tag          = '0;
     assign reg_dir_alloc_entry.resp         = '0;
     assign reg_dir_alloc_entry.num_beats    = '0;
     assign reg_dir_alloc_entry.state        = DIR_ST_EMPTY;

     typedef enum logic [1:0] {
          S_IDLE,
          S_ARMED,
          S_STATUS_READ,
          S_DATA_READ
     } apb_state_e;

     apb_state_e state;

     // ----------------------------------------------------------------
     // APB pready + RDF handshake + SW consume pulse  (FSM)
     // ----------------------------------------------------------------
     always_ff @(posedge pclk) begin
          if (!presetn) begin
               state                    <= S_IDLE;

               pready                   <= 1'b1;
               rdf_reg_data_req         <= 1'b0;
               rdf_reg_data_req_tag     <= '0;

               reg_dir_entry_consumed   <= 1'b0;
          end else begin
               pready                   <= 1'b1;           // pready_next = 1
               rdf_reg_data_req         <= 1'b0;           // rdf_data_req_next = 0

               reg_dir_entry_consumed   <= 1'b0;

               unique case (state)

                    // -------------------------
                    // S_IDLE
                    // -------------------------
                    S_IDLE: begin
                         if (psel && penable && pwrite && sel_tag_to_consume) begin       // Consumption starts with TAG set
                              state <= S_STATUS_READ;
                         end
                    end

                    // -------------------------
                    // S_STATUS_READ
                    // -------------------------
                    S_STATUS_READ: begin
                         if (psel && penable && pwrite && sel_tag_to_consume) begin       // Case we reset TAG
                              state <= S_STATUS_READ;
                         end
                         else if (psel && penable && !pwrite && sel_rd_status) begin
                              rdf_reg_data_req         <= 1'b1;
                              rdf_reg_data_req_tag     <= tag_to_consume_rd_val;
                              state                    <= S_ARMED;
                         end
                    end

                    // -------------------------
                    // S_ARMED
                    // -------------------------
                    S_ARMED: begin
                         if (psel && penable && pwrite && sel_tag_to_consume) begin       // Case we reset TAG
                              state <= S_STATUS_READ;
                         end
                         else if (rdf_reg_data_vld) begin                                 // Expecting data_vld after data_req
                              state                    <= S_DATA_READ;
                              pready                   <= 1'b1;
                              rdf_reg_data_req         <= 1'b0;
                         end
                         else begin
                              pready                   <= 1'b0;                           // Keep stalling if no valid data
                         end
                    end

                    // -------------------------
                    // S_DATA_READ
                    // -------------------------
                    S_DATA_READ: begin
                         if (psel && penable && pwrite && sel_tag_to_consume) begin       // Case we reset TAG
                              state <= S_STATUS_READ;
                         end
                         else if (psel && penable && !pwrite && sel_rd_data) begin        // Actual data read
                              if (rdf_reg_data_vld) begin
                                        pready <= 1'b0;                                   // Just Default
                                   if (rdf_reg_data_last) begin
                                        state                    <= S_IDLE;               // Finished consuming
                                        reg_dir_entry_consumed   <= 1'b1;                 // Notify consumed
                                   end
                                   else begin                                             // Additional data available
                                        state                    <= S_ARMED;              // Return to after data_req stage
                                        rdf_reg_data_req         <= 1'b1;
                                   end
                              end
                              // else: do nothing for now
                         end
                    end

                    default: begin
                         state                                   <= S_IDLE;
                    end
               endcase
          end
     end

     // ----------------------------------------------------------------
     // Single-cycle reg_dir_alloc_vld on ADDR_LO write
     // ----------------------------------------------------------------
     always_ff @(posedge pclk) begin               
          if (!presetn) begin
               addr_lo_we_d <= 1'b0;
               reg_dir_alloc_vld <= 1'b0;
          end 
          else begin
               addr_lo_we_d <= addr_lo_we;
               reg_dir_alloc_vld <= addr_lo_we & ~addr_lo_we_d;
          end
     end

// ==========================================================================================================================
// =================================================== DEBUG infra ==========================================================
// ==========================================================================================================================

     bit reg_debug_en;

     initial begin
          reg_debug_en = $test$plusargs("APB2AXI_REG_DEBUG");
          if (reg_debug_en) begin
               $display("%t [DREG_DBG] Register File debug ENABLED (+APB2AXI_REG_DEBUG)", $time);
          end
     end

     always_ff @(posedge pclk) begin
          if (!presetn) begin
          end else if (reg_debug_en) begin
               if (addr_lo_we) begin
                    $display("REG_DBG %0t AddrLo WE asserted: paddr=0x%0h pwdata=0x%0h", $time, paddr, pwdata);
               end

               if (addr_lo_we || addr_hi_we || cmd_we) begin
                    $display("REGFILE %0t WRITE: addr=0x%0h data=0x%0h", $time, paddr, pwdata);
               end

               $display("REG_DIRSTAT %0t tag_sel=%0d dir_state=%0d entry.state=%0d resp=%0d beats=%0d tag=%0d",
                         $time,
                         reg_dir_tag_sel,
                         reg_dir_entry_state,
                         reg_dir_entry.state,
                         reg_dir_entry.resp,
                         reg_dir_entry.num_beats,
                         reg_dir_entry.tag);
          end
     end

// ==========================================================================================================================
// ==========================================================================================================================
// ==========================================================================================================================

endmodule