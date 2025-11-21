/*------------------------------------------------------------------------------
 * File          : apb2axi_gateway.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Creation date : Nov 2, 2025
 * Description   : Apb Gateway - applications registers 
 *------------------------------------------------------------------------------*/

import apb2axi_pkg::*;

// -----------------------------------------------------------------------------
// apb2axi_gateway.sv
// Current Gateway stage:
//   * Interfaces directly with APB (via apb2axi_reg)
//   * Each APB write sequence builds a descriptor
//   * When commit_pulse fires, descriptor is pushed into the Directory
//   * Directory currently just enqueues entries with incrementing TAGs
//
// Future extensions (later):
//   - Add commit_ctrl / AXI builders to dispatch to AXI bus
//   - Add completion path to clear Directory entries
// -----------------------------------------------------------------------------
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

     output logic                  commit_pulse,
     output directory_entry_t      dir_entry
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
          .is_write     (is_write)
          // FIXME add completion inputs yet
     );

     // -------------------------------------------------
     // Pack to generic directory_entry_t
     // -------------------------------------------------
     always_comb begin
        dir_entry.is_write = is_write;
        dir_entry.addr     = addr;
        dir_entry.len      = len;
        dir_entry.size     = size;
        dir_entry.burst    = 2'b01;  // INCR for now
        dir_entry.tag      = '0;     // FIXME: real tag manager later
    end

endmodule

