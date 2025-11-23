/*------------------------------------------------------------------------------
 * File          : apb2axi_gateway.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Creation date : Nov 2, 2025
 * Description   : Apb Gateway - applications registers 
 *------------------------------------------------------------------------------*/

import apb2axi_pkg::*;

module apb2axi_gateway #(
     parameter int AXI_ADDR_W = AXI_ADDR_W,
     parameter int APB_ADDR_W = APB_ADDR_W
)(
     // ---------------- APB Interface ----------------
     input  logic                  PCLK,
     input  logic                  PRESETn,
     input  logic                  PSEL,
     input  logic                  PENABLE,
     input  logic                  PWRITE,
     input  logic [APB_ADDR_W-1:0] PADDR,
     input  logic [APB_DATA_W-1:0] PWDATA,
     output logic                  PREADY,
     output logic                  PSLVERR,

     // ---------------- Directory → TxnMgr interface ----------------
     output logic                  dir_pending_valid,
     output directory_entry_t      dir_pending_entry,
     output logic [TAG_W-1:0]      dir_pending_tag,
     input  logic                  dir_pending_pop
);

     // ---------------- Internal wiring ----------------
     logic                  commit_pulse;
     logic [AXI_ADDR_W-1:0] addr;
     logic [7:0]            len;
     logic [2:0]            size;
     logic                  is_write;

     // -------------------------------------------------
     // Register File: captures APB writes and emits commit_pulse + descriptor
     // -------------------------------------------------
     apb2axi_reg #(
          .AXI_ADDR_W (AXI_ADDR_W),
          .APB_ADDR_W (APB_ADDR_W)
     ) u_apb2axi_reg (
          .pclk         (PCLK),
          .presetn      (PRESETn),
          .psel         (PSEL),
          .penable      (PENABLE),
          .pwrite       (PWRITE),
          .paddr        (PADDR),
          .pwdata       (PWDATA),
          .pready       (PREADY),
          .pslverr      (PSLVERR),

          .commit_pulse (commit_pulse),
          .addr         (addr),
          .len          (len),
          .size         (size),
          .is_write     (is_write)
     );

     // -------------------------------------------------
     // Directory: enqueue each committed descriptor
     // -------------------------------------------------
     apb2axi_directory u_apb2axi_directory (
          .pclk         (PCLK),
          .presetn      (PRESETn),
          .commit_pulse (commit_pulse),
          .addr         (addr),
          .len          (len),
          .size         (size),
          .is_write     (is_write),
          .pending_valid(dir_pending_valid),
          .pending_entry(dir_pending_entry),
          .pending_tag  (dir_pending_tag),
          .pending_pop  (dir_pending_pop)
     );

endmodule

