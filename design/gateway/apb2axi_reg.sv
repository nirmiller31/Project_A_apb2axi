
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

     // Outputs to Directory
     output logic                  commit_pulse,
     output logic [AXI_ADDR_W-1:0] addr,
     output logic [7:0]            len,
     output logic [2:0]            size,
     output logic                  is_write
);
     // Simple state-holding registers
     logic          addr_lo_we, addr_lo_we_d;          // _d for pulse purposes, for commiting
     logic [31:0]   addr_lo_rd_val;
     logic          addr_hi_we;
     logic [31:0]   addr_hi_rd_val;
     logic          cmd_we;
     logic [31:0]   cmd_rd_val;

     // Assertiong APB protocol
     assign pready                 = 1'b1;
     assign pslverr                = 1'b0;

     // Outputs for Directory
     assign addr                   = {addr_hi_rd_val, addr_lo_rd_val};
     assign len                    = cmd_rd_val[7:0];
     assign size                   = cmd_rd_val[10:8];
     assign is_write               = cmd_rd_val[31];

     // Registers' Write Enable
     assign addr_lo_we             =  (psel && penable && pwrite && (paddr[3:2] == 2'b00));
     assign addr_hi_we             =  (psel && penable && pwrite && (paddr[3:2] == 2'b01));
     assign cmd_we                 =  (psel && penable && pwrite && (paddr[3:2] == 2'b10));

     // Actual writing process
     always_ff @(posedge pclk) begin
          if (!presetn) begin
               addr_lo_rd_val     <= '0;
               addr_hi_rd_val     <= '0;
               cmd_rd_val         <= '0;
          end 
          else begin
               if(addr_lo_we) addr_lo_rd_val          <= pwdata;
               if(addr_hi_we) addr_hi_rd_val          <= pwdata;
               if(cmd_we)     cmd_rd_val              <= pwdata;
          end
     end

     // Single pulse after writing to addr_lo is commit signal
     always_ff @(posedge pclk) begin                   
          if (!presetn) begin
               addr_lo_we_d        <= '0;
               commit_pulse        <= '0;
          end 
          else begin
               addr_lo_we_d                          <= addr_lo_we;
               commit_pulse                          <= addr_lo_we & ~addr_lo_we_d;
          end
     end

endmodule
