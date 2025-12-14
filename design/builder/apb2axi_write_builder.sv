/*------------------------------------------------------------------------------
 * File          : apb2axi_write_builder.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Description   : Consumes Write FIFO entries and issues AXI AW+W
 *------------------------------------------------------------------------------*/

import apb2axi_pkg::*;

module apb2axi_write_builder #(
    parameter int FIFO_ENTRY_W = CMD_ENTRY_W
)(
    input  logic                        aclk,
    input  logic                        aresetn,
    // Connection to WRITE FIFO
    input  logic                        wr_pop_vld,
    output logic                        wr_pop_rdy,
    input  logic [FIFO_ENTRY_W-1:0]     wr_pop_data,
    // AXI AW
    output logic [AXI_ID_W-1:0]         awid,
    output logic [AXI_ADDR_W-1:0]       awaddr,
    output logic [3:0]                  awlen,
    output logic [2:0]                  awsize,
    output logic [1:0]                  awburst,
    output logic                        awlock,
    output logic [3:0]                  awcache,
    output logic [2:0]                  awprot,
    output logic                        awvalid,
    input  logic                        awready,
    // AXI W
    output logic [AXI_DATA_W-1:0]       wdata,
    output logic [(AXI_DATA_W/8)-1:0]   wstrb,
    output logic                        wlast,
    output logic                        wvalid,
    input  logic                        wready
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

        wr_pop_rdy = 1'b0;

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
                if (wr_pop_vld && entry.is_write) begin
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
                    wr_pop_rdy = 1'b1;   // consume FIFO entry
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

    always_ff @(posedge aclk) begin
        if (awvalid && awready)
            $display("%t [WR_BUILDER] AW handshake addr=%h len=%0d id=%0d", $time, awaddr, awlen, awid);
        if (wvalid && wready)
            $display("%t [WR_BUILDER] WDATA=%h WLAST=%0b", $time, wdata, wlast);
    end

endmodule
