/*------------------------------------------------------------------------------
 * File          : apb2axi_read_builder.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Description   : Consumes Read FIFO entries and issues AXI AR + RREADY.
 *                 Future-safe: supports bursts, outstanding, and clean handshakes.
 *------------------------------------------------------------------------------*/

import apb2axi_pkg::*;

module apb2axi_read_builder #(
    parameter int AXI_ADDR_W   = AXI_ADDR_W,
    parameter int AXI_DATA_W   = AXI_DATA_W,
    parameter int FIFO_ENTRY_W = REQ_WIDTH
)(
    input  logic                     aclk,
    input  logic                     aresetn,

    // Connection to READ FIFO
    input  logic                     rd_pop_valid,
    input  logic [FIFO_ENTRY_W-1:0]  rd_pop_data,
    output logic                     rd_pop_ready,

    // AXI Read Address Channel (AR)
    output logic [AXI_ID_W-1:0]      arid,
    output logic [AXI_ADDR_W-1:0]    araddr,
    output logic [3:0]               arlen,
    output logic [2:0]               arsize,
    output logic [1:0]               arburst,
    output logic                     arlock,
    output logic [3:0]               arcache,
    output logic [2:0]               arprot,
    output logic                     arvalid,
    input  logic                     arready,

    // AXI Read Data Channel (R)
    input  logic [AXI_ID_W-1:0]      rid,
    input  logic [AXI_DATA_W-1:0]    rdata,
    input  logic [1:0]               rresp,
    input  logic                     rlast,
    input  logic                     rvalid,
    output logic                     rready
);

    // ---------------------------
    // Decode Directory Entry
    // ---------------------------
    directory_entry_t entry;
    assign entry = rd_pop_data;

    // ---------------------------
    // State Machine
    // ---------------------------
    typedef enum logic [1:0] {RB_IDLE, RB_SEND_AR, RB_WAIT_R} rb_state_e;
    rb_state_e state, next_state;

    // ---------------------------
    // Combinational Logic
    // ---------------------------
    always_comb begin
        // defaults
        arvalid      = 1'b0;
        rready       = 1'b0;
        rd_pop_ready = 1'b0;

        // AR defaults
        arid    = entry.tag;     // proper ID mapping
        araddr  = entry.addr;
        arlen   = entry.len;
        arsize  = entry.size;
        arburst = entry.burst;
        arlock  = 1'b0;
        arcache = 4'b0011;
        arprot  = 3'b000;

        next_state = state;

        case (state)

            RB_IDLE: begin
                if (rd_pop_valid && !entry.is_write)
                    next_state = RB_SEND_AR;
            end

            RB_SEND_AR: begin
                arvalid = 1'b1;

                if (arvalid && arready) begin
                    // we consumed the entry here
                    rd_pop_ready = 1'b1;
                    next_state   = RB_WAIT_R;
                end
            end

            RB_WAIT_R: begin
                rready = 1'b1;

                if (rvalid && rready && rlast)
                    next_state = RB_IDLE;
            end
        endcase
    end

    // ---------------------------
    // Sequential State Register
    // ---------------------------
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            state <= RB_IDLE;
        else
            state <= next_state;
    end

    // ---------------------------
    // Debug (for bring-up)
    // ---------------------------
    // synthesis translate_off
    always_ff @(posedge aclk) begin
        if (rd_pop_valid)
            $display("%t [RD_BUILDER_DBG] FIFO valid entry: tag=%0d is_write=%0b addr=%h len=%0d",
                      $time, entry.tag, entry.is_write, entry.addr, entry.len);

        if (arvalid && arready)
            $display("%t [RD_BUILDER_DBG] AR FIRED: TAG=%0d ADDR=%h LEN=%0d",
                     $time, arid, araddr, arlen);

        if (rvalid && rready)
            $display("%t [RD_BUILDER_DBG] RBEAT: rid=%0d rlast=%0b rresp=%0d",
                     $time, rid, rlast, rresp);

        if (rvalid && rready && rlast)
            $display("%t [RD_BUILDER_DBG] READ COMPLETE (TAG=%0d)", $time, rid);
    end
    // synthesis translate_on

endmodule