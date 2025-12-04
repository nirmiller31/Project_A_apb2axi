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
     output logic [AXI_ADDR_W-1:0] addr,
     output logic [7:0]            len,
     output logic [2:0]            size,
     output logic                  is_write, 

     // Inputs from response_handler (PCLK domain)
     input  logic                  rd_status_valid,
     input  logic                  rd_status_error,
     input  logic [1:0]            rd_status_resp,
     input  logic [TAG_W-1:0]      rd_status_tag,
     input  logic [7:0]            rd_status_num_beats,
     input  logic                  rd_status_is_write,

     // From/To RDF (data beats)
     input  logic                  rdf_data_valid,
     input  logic [APB_DATA_W-1:0] rdf_data_out,
     input  logic                  rdf_data_last,
     output logic                  rdf_data_req,
     output logic [TAG_W-1:0]      rdf_data_req_tag,

     // Ack back to Directory (SW consumed completion)
     output logic                  dir_consumed_valid,
     output logic [TAG_W-1:0]      dir_consumed_tag
);

     // ----------------------------------------------------------------
     // Local address decode (word-based, 32-bit aligned)
     //  0x00 : ADDR_LO
     //  0x04 : ADDR_HI
     //  0x08 : CMD
     //  0x0C : RD_STATUS (RO)
     //  0x10 : RD_DATA   (RO, streaming)
     // ----------------------------------------------------------------
     localparam REG_ADDR_ADDR_LO   = 'h00;
     localparam REG_ADDR_ADDR_HI   = 'h04;
     localparam REG_ADDR_CMD       = 'h08;
     localparam REG_ADDR_RD_STATUS = 'h0C;
     localparam REG_ADDR_RD_DATA   = 'h10;

     logic sel_addr_lo, sel_addr_hi, sel_cmd, sel_rd_status, sel_rd_data;

     logic          addr_lo_we, addr_lo_we_d;
     logic [31:0]   addr_lo_rd_val;
     logic          addr_hi_we;
     logic [31:0]   addr_hi_rd_val;
     logic          cmd_we;
     logic [31:0]   cmd_rd_val;

     logic          rd_status_re;
     logic          rd_data_pending;

     assign pslverr = 1'b0;

     // Outputs for Directory
     assign addr     = {addr_hi_rd_val, addr_lo_rd_val};
     assign len      = cmd_rd_val[7:0];
     assign size     = cmd_rd_val[10:8];
     assign is_write = cmd_rd_val[31];

     assign sel_addr_lo   = ({paddr[4:2], 2'b00} == REG_ADDR_ADDR_LO);
     assign sel_addr_hi   = ({paddr[4:2], 2'b00} == REG_ADDR_ADDR_HI);
     assign sel_cmd       = ({paddr[4:2], 2'b00} == REG_ADDR_CMD);
     assign sel_rd_status = ({paddr[4:2], 2'b00} == REG_ADDR_RD_STATUS);
     assign sel_rd_data   = ({paddr[4:2], 2'b00} == REG_ADDR_RD_DATA);  

     // Write enables for RW regs
     assign addr_lo_we = psel & penable & pwrite & sel_addr_lo;
     assign addr_hi_we = psel & penable & pwrite & sel_addr_hi;
     assign cmd_we     = psel & penable & pwrite & sel_cmd;

     // READ enable for RD_STATUS (used for consume)
     assign rd_status_re = psel && penable && !pwrite && sel_rd_status;

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
                         rd_status_valid,        // bit 15
                         rd_status_error,        // bit 14
                         rd_status_resp,         // [13:12]
                         rd_status_num_beats,    // [11:4]
                         rd_status_tag           // [3:0]
                    };

                    sel_rd_data:   prdata = rdf_data_out[APB_DATA_W-1:0];

                    default:       prdata = '0;
               endcase
          end
     end

     // ----------------------------------------------------------------
     // APB pready + RDF handshake + SW consume pulse
     // ----------------------------------------------------------------
     always_ff @(posedge pclk) begin
          if (!presetn) begin
               rdf_data_req       <= 1'b0;
               rdf_data_req_tag   <= '0;
               pready             <= 1'b1;
               rd_data_pending    <= 1'b0;

               dir_consumed_valid <= 1'b0;
               dir_consumed_tag   <= '0;
          end else begin
               // default: no consume pulse
               dir_consumed_valid <= 1'b0;

               // *** SW CONSUME: read RD_STATUS when VALID=1 ***
               if (rd_status_re && rd_status_valid) begin
                    dir_consumed_valid <= 1'b1;
                    dir_consumed_tag   <= rd_status_tag;
                    $display("[%0t][REG] RD_STATUS consumed: tag=%0d beats=%0d",
                             $time, rd_status_tag, rd_status_num_beats);
               end

               // RD_DATA read handling (may stall)
               if (psel && penable && !pwrite && sel_rd_data) begin
                    // launch a request (one pulse per APB read)
                    rdf_data_req     <= 1'b1;
                    rdf_data_req_tag <= rd_status_tag; // use current completion TAG

                    if (!rdf_data_valid) begin
                         // no data yet → stall bus, remember we're waiting
                         pready          <= 1'b0;
                         rd_data_pending <= 1'b1;
                    end else begin
                         // data already valid this cycle → zero-wait read
                         pready          <= 1'b1;
                         rd_data_pending <= 1'b0;
                    end
               end
               else if (rd_data_pending) begin
                    // continue stalling until data comes
                    rdf_data_req <= 1'b0;
                    if (rdf_data_valid) begin
                         pready          <= 1'b1;
                         rd_data_pending <= 1'b0;
                    end else begin
                         pready          <= 1'b0;
                    end
               end
               else begin
                    // no RD_DATA access: APB always ready
                    rdf_data_req  <= 1'b0;
                    pready        <= 1'b1;
               end
          end
     end

     // ----------------------------------------------------------------
     // Actual register writes (ADDR_LO / ADDR_HI / CMD)
     // ----------------------------------------------------------------
     always_ff @(posedge pclk) begin
          if (!presetn) begin
               addr_lo_rd_val <= '0;
               addr_hi_rd_val <= '0;
               cmd_rd_val     <= '0;
          end 
          else begin
               if (addr_lo_we) addr_lo_rd_val <= pwdata;
               if (addr_hi_we) addr_hi_rd_val <= pwdata;
               if (cmd_we)     cmd_rd_val     <= pwdata;
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

          if (commit_pulse)
               $display("%t [REG] COMMIT addr=%h len=%0d size=%0d is_write=%0b",
                        $time, addr, len, size, is_write);

          if (addr_lo_we || addr_hi_we || cmd_we)
               $display("%t [REGFILE] WRITE at addr=%h data=%h",
                        $time, paddr, pwdata);

          if (psel && penable && !pwrite && sel_rd_status)
               $display("%t [REG] RD_STATUS read: valid=%0b err=%0b resp=%0d tag=%0d beats=%0d",
                        $time, rd_status_valid, rd_status_error,
                        rd_status_resp, rd_status_tag, rd_status_num_beats);
     end

     initial begin
          $display("  TIME    psel penable pwrite sel_rd_status rd_status_we  paddr");
          $monitor("%0t [REG_MON] psel=%0b penable=%0b pwrite=%0b sel_rd_status=%0b rd_status_we=%0b paddr=%h",
                   $time, psel, penable, pwrite, sel_rd_status,
                   1'b0, // rd_status_we removed from functionality
                   paddr);
     end

endmodule