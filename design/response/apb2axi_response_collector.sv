/*------------------------------------------------------------------------------
 * File          : response_collector.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Description   : Collects AXI3 responses (R/B), pushes data into RDF and
 *                 bundles completions into a completion FIFO (ACLK domain).
 *------------------------------------------------------------------------------*/
import apb2axi_pkg::*;

module apb2axi_response_collector #(
    parameter int TAG_W        = TAG_W,
    parameter int DATA_W       = AXI_DATA_W,
    parameter int COMPLETION_W = COMPLETION_W
)(
    input  logic                    aclk,
    input  logic                    aresetn,

    // ------------------------------
    // AXI Read Data Channel (R)
    // ------------------------------
    input  logic [TAG_W-1:0]        rid,
    input  logic [DATA_W-1:0]       rdata,
    input  logic [1:0]              rresp,
    input  logic                    rlast,
    input  logic                    rvalid,
    input  logic                    rready,   // driven by read_builder

    // ------------------------------
    // AXI Write Response Channel (B)
    // (hooked later when write path is ready)
    // ------------------------------
    input  logic [TAG_W-1:0]        bid,
    input  logic [1:0]              bresp,
    input  logic                    bvalid,
    input  logic                    bready,   // driven by write_builder

    // ------------------------------
    // RDF interface (AXI side)
    // ------------------------------
    output logic                    rdf_push_valid,
    output rdf_entry_t              rdf_push_payload,
    input  logic                    rdf_push_ready,

    // ------------------------------
    // Completion FIFO IF (AXI side)
    // ------------------------------
    output logic                    cpl_push_valid,
    output logic [COMPLETION_W-1:0] cpl_push_data,
    input  logic                    cpl_push_ready
);

    // Internal bookkeeping for a single in-flight read burst
    completion_entry_t cpl_reg;

    logic              r_inflight;
    logic [TAG_W-1:0]  cur_rid;
    logic [7:0]        beat_cnt;
    logic              r_error;
    logic [1:0]        last_rresp;

    // Sequential logic
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rdf_push_valid <= 1'b0;
            rdf_push_payload <= '0;

            cpl_push_valid <= 1'b0;
            cpl_push_data  <= '0;

            r_inflight  <= 1'b0;
            cur_rid     <= '0;
            beat_cnt    <= '0;
            r_error     <= 1'b0;
            last_rresp  <= 2'b00;
        end
        else begin
            // default: no pushes unless we see activity
            rdf_push_valid <= 1'b0;
            cpl_push_valid <= 1'b0;

            // -----------------------------
            // READ DATA beat arrives
            // -----------------------------
            if (rvalid && rready) begin
                rdf_entry_t beat;

                // Start of burst
                if (!r_inflight) begin
                    r_inflight <= 1'b1;
                    cur_rid    <= rid;
                    beat_cnt   <= '0;
                    r_error    <= 1'b0;
                end

                beat_cnt   <= beat_cnt + 1;
                last_rresp <= rresp;
                if (rresp != 2'b00)
                    r_error <= 1'b1;

                // Prepare RDF entry
                beat.tag   = rid;
                beat.data  = rdata;
                beat.last  = rlast;
                beat.resp  = rresp;

                // For now we assume rdf_push_ready is always 1 (single-beat FIFO, pop side always ready)
                rdf_push_payload <= beat;
                rdf_push_valid   <= 1'b1;

                // Debug (optional)
                // synthesis translate_off
                $display("%t [RESP_COLLECT] RBEAT: RID=%0d RRESP=%0d RLAST=%0b",
                         $time, rid, rresp, rlast);
                // synthesis translate_on

                // End of burst: emit completion
                if (rlast) begin
                    cpl_reg.is_write  = 1'b0;
                    cpl_reg.tag       = cur_rid;
                    cpl_reg.resp      = last_rresp;
                    cpl_reg.error     = r_error;
                    cpl_reg.num_beats = beat_cnt + 1; // include this beat

                    cpl_push_data  <= cpl_reg;
                    cpl_push_valid <= 1'b1;

                    // Debug (matches your earlier logs)
                    // synthesis translate_off
                    $display("%t [RESP_COLLECT] READ done: RID=%0d RRESP=%0d beats=%0d",
                             $time, cur_rid, last_rresp, beat_cnt+1);
                    // synthesis translate_on

                    r_inflight <= 1'b0;
                end
            end

            // -----------------------------
            // WRITE COMPLETIONS (B channel)
            // -----------------------------
            if (bvalid && bready) begin
                completion_entry_t bw_cpl;

                bw_cpl.is_write  = 1'b1;
                bw_cpl.tag       = bid;
                bw_cpl.resp      = bresp;
                bw_cpl.error     = (bresp != 2'b00);
                bw_cpl.num_beats = 8'd0; // or 1 if you prefer

                // Simple arbitration: if a read completion and write completion
                // happen in the same cycle, READ wins. You can refine later.
                if (!cpl_push_valid) begin
                    cpl_push_data  <= bw_cpl;
                    cpl_push_valid <= 1'b1;

                    // synthesis translate_off
                    $display("%t [RESP_COLLECT] WRITE done: BID=%0d BRESP=%0d", $time, bid, bresp);
                    // synthesis translate_on
                end
            end
        end
    end
endmodule