/*------------------------------------------------------------------------------
 * File          : apb2axi_read_builder.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Description   : Consumes Read FIFO entries and issues AXI AR + RREADY
 *------------------------------------------------------------------------------*/

import apb2axi_pkg::*;

module apb2axi_read_builder #(
    parameter int AXI_ADDR_W   = AXI_ADDR_W,
    parameter int AXI_DATA_W   = AXI_DATA_W,
    parameter int FIFO_ENTRY_W = 1 + 3 + 4 + AXI_ADDR_W  // is_write + size + len + addr
)(
    input  logic                     aclk,
    input  logic                     aresetn,

    // Connection to READ FIFO
    input  logic                     rd_pop_valid,
    output logic                     rd_pop_ready,
    input  logic [FIFO_ENTRY_W-1:0]  rd_pop_data,

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

    // ----------------------------------------------------------
    // Extract fields from FIFO entry
    // ----------------------------------------------------------
    logic                            is_write;
    logic [2:0]                      size;
    logic [3:0]                      len;
    logic [AXI_ADDR_W-1:0]           addr;

    assign {is_write, size, len, addr} = rd_pop_data;

    // ----------------------------------------------------------
    // Simple FSM: one AR, wait for RLAST
    // ----------------------------------------------------------
    typedef enum logic [1:0] {RB_IDLE, RB_SEND_AR, RB_WAIT_R} rb_state_e;

    rb_state_e state, next_state;

    // ----------------------------------------------------------
    // Combinational logic
    // ----------------------------------------------------------
    always_comb begin
        // Defaults
        arvalid      = 1'b0;
        rready       = 1'b0;
        rd_pop_ready = 1'b0;

        // AR signals
        arid    = '0;
        araddr  = addr;
        arlen   = len;          // For now gateway gives 0 => single-beat
        arsize  = size;
        arburst = 2'b01;        // INCR
        arlock  = 1'b0;
        arcache = 4'b0011;      // Normal, non-bufferable, modifiable
        arprot  = 3'b000;

        next_state = state;

        case (state)

            RB_IDLE: begin
                // Only start on non-write entries
                if (rd_pop_valid && !is_write) begin
                    next_state = RB_SEND_AR;
                end
            end

            RB_SEND_AR: begin
                arvalid = 1'b1;
                if (arvalid && arready) begin
                    next_state = RB_WAIT_R;
                end
            end

            RB_WAIT_R: begin
                // Always ready to accept data
                rready = 1'b1;
                // We consider the transaction done on RLAST
                if (rvalid && rready && rlast) begin
                    rd_pop_ready = 1'b1;   // consume FIFO entry
                    next_state   = RB_IDLE;
                end
            end

        endcase
    end

    // State register
    always_ff @(posedge aclk) begin
        if (!aresetn)
            state <= RB_IDLE;
        else
            state <= next_state;
    end

    // Optional debug
    // synthesis translate_off
    always_ff @(posedge aclk) begin
        if (arvalid && arready)
            $display("%t [READ_BUILDER] AR addr=%h len=%0d size=%0d",
                     $time, araddr, arlen, arsize);
        if (rvalid && rready && rlast)
            $display("%t [READ_BUILDER] R last beat, rid=%0d rresp=%0d",
                     $time, rid, rresp);
    end
    // synthesis translate_on

endmodule
