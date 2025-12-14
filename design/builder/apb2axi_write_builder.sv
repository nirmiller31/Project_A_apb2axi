/*------------------------------------------------------------------------------
 * File          : apb2axi_write_builder.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Description   : Consumes Write FIFO entries and issues AXI AW+W
 *------------------------------------------------------------------------------*/

import apb2axi_pkg::*;

module apb2axi_write_builder #(
    parameter int CMD_ENTRY_W = CMD_ENTRY_W,
    parameter int DATA_ENTRY_W = CMD_ENTRY_W //DATA_ENTRY_W
)(
    input  logic                        aclk,
    input  logic                        aresetn,
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
    input  logic                        wready,
    // Connection to WRITE FIFO
    input  logic                        wr_pop_vld,
    output logic                        wr_pop_rdy,
    input  logic [CMD_ENTRY_W-1:0]      wr_pop_data,
    // Connection to WRITE FIFO
    input  logic                        wd_pop_vld,
    output logic                        wd_pop_rdy,
    input  logic [DATA_ENTRY_W-1:0]     wd_pop_data
);

    // ----------------------------------------------------------
    // Extract fields from FIFO entry
    // ----------------------------------------------------------
    directory_entry_t entry;
    assign entry = wr_pop_data;

    assign awlock  = 1'b0;
    assign awcache = 4'b0011;
    assign awprot  = 3'b000;
    assign awburst = 2'b01; // INCR

    // ------------------------------------------------------------------
    // Per-tag write tracking
    // ------------------------------------------------------------------
    typedef enum logic [1:0] {ST_IDLE, ST_AW, ST_W} st_e;
    st_e st;

    logic [AXI_ID_W-1:0]            cur_id;
    logic [AXI_ADDR_W-1:0]          cur_addr;
    logic [3:0]                     cur_len;
    logic [2:0]                     cur_size;
    logic [7:0]                     beats_left; // = cur_len+1 (fits AXI3 max 16 beats)

    // -----------------------------
    // Minimal debug (optional)
    // -----------------------------
    bit wb_dbg;
    initial begin
        wb_dbg = $test$plusargs("APB2AXI_WB_DEBUG");
        if (wb_dbg) $display("%t [WB_DBG] WriteBuilder debug ENABLED (+APB2AXI_WB_DEBUG)", $time);
    end

    // -----------------------------
    // Main control
    // -----------------------------
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            st         <= ST_IDLE;

            awvalid    <= 1'b0;
            wvalid     <= 1'b0;
            wlast      <= 1'b0;

            wr_pop_rdy <= 1'b0;
            wd_pop_rdy <= 1'b0;

            cur_id     <= '0;
            cur_addr   <= '0;
            cur_len    <= '0;
            cur_size   <= '0;
            beats_left <= '0;
        end else begin
            // defaults
            wr_pop_rdy <= 1'b0;
            wd_pop_rdy <= 1'b0;

            // hold valids if stalled
            if (awvalid && !awready) awvalid <= 1'b1;
            if (wvalid  && !wready ) wvalid  <= 1'b1;

            // if handshake happened, we'll typically drop valids unless re-raised below
            if (awvalid && awready) awvalid <= 1'b0;
            if (wvalid  && wready ) begin
                wvalid <= 1'b0;
                wlast  <= 1'b0;
            end

            unique case (st)
                // -------------------------------------------------
                // IDLE: wait for a command, latch it atomically
                // -------------------------------------------------
                ST_IDLE: begin
                    if (wr_pop_vld) begin
                        // pop cmd exactly once
                        wr_pop_rdy <= 1'b1;

                        cur_id   <= entry.tag;
                        cur_addr <= entry.addr;
                        cur_len  <= entry.len;
                        cur_size <= entry.size;

                        // beats_left = len+1
                        beats_left <= {4'b0, entry.len} + 8'd1;

                        // drive AW next
                        st <= ST_AW;

                        if (wb_dbg)
                            $display("%t [WB] CMD  tag=%0d addr=%h len=%0d size=%0d",
                                     $time, entry.tag, entry.addr, entry.len, entry.size);
                    end
                end

                // -------------------------------------------------
                // AW: issue address, wait for handshake
                // -------------------------------------------------
                ST_AW: begin
                    if (!awvalid) begin
                        awid    <= cur_id;
                        awaddr  <= cur_addr;
                        awlen   <= cur_len;
                        awsize  <= cur_size;
                        awvalid <= 1'b1;
                    end

                    if (awvalid && awready) begin
                        st <= ST_W;
                        if (wb_dbg)
                            $display("%t [WB] AW   tag=%0d addr=%h len=%0d", $time, awid, awaddr, awlen);
                    end
                end

                // -------------------------------------------------
                // W: consume exactly beats_left beats from data FIFO
                // -------------------------------------------------
                ST_W: begin
                    // Only launch a beat when we're not currently holding WVALID
                    if (!wvalid) begin
                        // Require data available
                        if (wd_pop_vld) begin
                            wd_pop_rdy <= 1'b1;     // pop exactly with issuing W
                            wdata      <= wd_pop_data;
                            wvalid     <= 1'b1;

                            // last beat?
                            if (beats_left == 8'd1)
                                wlast <= 1'b1;

                            if (wb_dbg)
                                $display("%t [WB] W    tag=%0d last=%0b beats_left=%0d",
                                         $time, cur_id, (beats_left==8'd1), beats_left);
                        end
                    end

                    // On W handshake, decrement beats_left and finish when done
                    if (wvalid && wready) begin
                        beats_left <= beats_left - 8'd1;

                        if (beats_left == 8'd1) begin
                            // just sent the last beat
                            st <= ST_IDLE;
                            if (wb_dbg)
                                $display("%t [WB] DONE tag=%0d", $time, cur_id);
                        end
                    end
                end

                default: st <= ST_IDLE;
            endcase
        end
    end

endmodule