//------------------------------------------------------------------------------
// apb2axi_gateway.sv
// PCLK-Domain Request/Completion Hub
//
// Responsibilities:
//   - Receive commit_pulse + APB-decoded fields (addr/len/size/is_write)
//   - Allocate new TAG in directory
//   - Forward completions from handler to BOTH:
//         • Directory (dir_cpl_*)
//         • Regfile   (rd_status_*)
//   - Forward APB "consume" signal to directory (dir_cons_*)
//------------------------------------------------------------------------------

import apb2axi_pkg::*;

module apb2axi_gateway #(
     parameter int AXI_ADDR_W   = AXI_ADDR_W,
     parameter int TAG_W        = TAG_W,
     parameter int COMPLETION_W = COMPLETION_W
)(
     input  logic                     pclk,
     input  logic                     presetn,

     // ------------------------------------------------------------------
     // From Regfile (new request)
     // ------------------------------------------------------------------
     input  logic                     commit_pulse,
     input  logic [AXI_ADDR_W-1:0]    addr,
     input  logic [7:0]               len,
     input  logic [2:0]               size,
     input  logic                     is_write,

     // ------------------------------------------------------------------
     // Directory ALLOC interface
     // ------------------------------------------------------------------
     output logic                     dir_alloc_valid,
     output directory_entry_t         dir_alloc_entry,
     input  logic                     dir_alloc_ready,
     input  logic [TAG_W-1:0]         dir_alloc_tag,

     // ------------------------------------------------------------------
     // From response_handler (completion stream)
     // ------------------------------------------------------------------
     input  logic                     gw_cpl_valid,
     input  logic [COMPLETION_W-1:0]  gw_cpl_data,
     output logic                     gw_cpl_ready,

     // ------------------------------------------------------------------
     // To directory (AXI completion)
     // ------------------------------------------------------------------
     output logic                     dir_cpl_valid,
     output logic [TAG_W-1:0]         dir_cpl_tag,
     output logic                     dir_cpl_is_write,
     output logic                     dir_cpl_error,
     output logic [1:0]               dir_cpl_resp,
     output logic [7:0]               dir_cpl_num_beats,
     input  logic                     dir_cpl_ready,

     // ------------------------------------------------------------------
     // To directory (APB says: I'm done consuming this TAG)
     // ------------------------------------------------------------------
     input  logic                     dir_cons_valid,    // from regfile
     input  logic [TAG_W-1:0]         dir_cons_tag,

     // ------------------------------------------------------------------
     // To regfile (completion status)
     // ------------------------------------------------------------------
     output logic                     rd_status_valid,
     output logic                     rd_status_error,
     output logic [1:0]               rd_status_resp,
     output logic [TAG_W-1:0]         rd_status_tag,
     output logic [7:0]               rd_status_num_beats,
     output logic                     rd_status_is_write
);

    // ================================================================
    // 1. Request Alloc Path  (commit_pulse → directory allocation)
    // ================================================================
    always_comb begin
        dir_alloc_valid          = commit_pulse;
        dir_alloc_entry.addr     = addr;
        dir_alloc_entry.len      = len;
        dir_alloc_entry.size     = size;
        dir_alloc_entry.is_write = is_write;
        dir_alloc_entry.tag      = '0;   // Directory overwrites with alloc_tag
    end

    // ================================================================
    // 2. Completion fanout
    //    gw_cpl_valid → directory + regfile
    // ================================================================
    completion_entry_t cpl;
    assign cpl = completion_entry_t'(gw_cpl_data);

    always_comb begin
        // Completion passes to Directory ONLY when ready
        gw_cpl_ready = dir_cpl_ready;

        dir_cpl_valid     = gw_cpl_valid;
        dir_cpl_tag       = cpl.tag;
        dir_cpl_is_write  = cpl.is_write;
        dir_cpl_error     = cpl.error;
        dir_cpl_resp      = cpl.resp;
        dir_cpl_num_beats = cpl.num_beats;

        // And same info goes to regfile
        rd_status_valid     = gw_cpl_valid;
        rd_status_tag       = cpl.tag;
        rd_status_is_write  = cpl.is_write;
        rd_status_error     = cpl.error;
        rd_status_resp      = cpl.resp;
        rd_status_num_beats = cpl.num_beats;
    end

    // ================================================================
    // 3. APB “consume” pulse
    //    The regfile already generates dir_cons_valid/tag.
    //    Gateway simply forwards them directly to Directory.
    //    (Directory free logic lives inside directory module.)
    // ================================================================

    // No logic needed — regfile wires dir_cons_* directly to directory;
    // gateway does NOT modify or gate it.

endmodule