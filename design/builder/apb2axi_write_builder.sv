/*------------------------------------------------------------------------------
 * File          : apb2axi_write_builder.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Description   : Consumes Write FIFO entries and issues AXI AW+W
 *------------------------------------------------------------------------------*/

import apb2axi_pkg::*;

module apb2axi_write_builder #(
    parameter int AXI_ADDR_W = AXI_ADDR_W,
    parameter int AXI_DATA_W = AXI_DATA_W,
    parameter int FIFO_ENTRY_W = 1 + 3 + 4 + AXI_ADDR_W  // is_write + size + len + addr
)(
    input  logic                     aclk,
    input  logic                     aresetn,

    // Connection to WRITE FIFO
    input  logic                     wr_pop_valid,
    output logic                     wr_pop_ready,
    input  logic [FIFO_ENTRY_W-1:0]  wr_pop_data,

    // AXI interface drive
    output logic [AXI_ID_W-1:0]      awid,
    output logic [AXI_ADDR_W-1:0]    awaddr,
    output logic [3:0]               awlen,
    output logic [2:0]               awsize,
    output logic [1:0]               awburst,
    output logic                     awlock,
    output logic [3:0]               awcache,
    output logic [2:0]               awprot,
    output logic                     awvalid,
    input  logic                     awready,

    output logic [AXI_DATA_W-1:0]    wdata,
    output logic [(AXI_DATA_W/8)-1:0] wstrb,
    output logic                      wlast,
    output logic                      wvalid,
    input  logic                      wready
);

    // ----------------------------------------------------------
    // Extract fields from FIFO entry
    // ----------------------------------------------------------
    directory_entry_t entry;
    assign entry = wr_pop_data;

    // ----------------------------------------------------------
    // State machine for AW/W handshake
    // ----------------------------------------------------------
    typedef enum logic [1:0] {IDLE, SEND_AW, SEND_W} wb_state_e;

    wb_state_e state, next_state;

    // ----------------------------------------------------------
    // Default AXI outputs
    // ----------------------------------------------------------
    always_comb begin
        awvalid = 1'b0;
        wvalid  = 1'b0;

        wr_pop_ready = 1'b0;

        awid    = '0;
        awaddr  = entry.addr;
        awlen   = 4'd0;       // single beat
        awsize  = entry.size;
        awburst = 2'b01;      // INCR
        awlock  = 1'b0;
        awcache = 4'b0011;    // Normal, non-bufferable, modifiable
        awprot  = 3'b000;

        wdata   = '0;         // TODO: later: connect a write-data provider
        wstrb   = { (AXI_DATA_W/8){1'b1} };
        wlast   = 1'b1;

        next_state = state;

        case(state)

            IDLE: begin
                if (wr_pop_valid && entry.is_write) begin
                    next_state = SEND_AW;
                end
            end

            SEND_AW: begin
                awvalid = 1'b1;
                if (awvalid && awready)
                    next_state = SEND_W;
            end

            SEND_W: begin
                wvalid = 1'b1;
                if (wvalid && wready) begin
                    wr_pop_ready = 1'b1;   // consume FIFO entry
                    next_state   = IDLE;
                end
            end

        endcase
    end

    // State register
    always_ff @(posedge aclk) begin
        if (!aresetn)
            state <= IDLE;
        else
            state <= next_state;
    end

endmodule
