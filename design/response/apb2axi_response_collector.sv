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

    logic              reads_inflight   [N_TAG];
    logic [TAG_W-1:0]  cur_rid          [N_TAG];
    logic [7:0]        beat_cnt         [N_TAG];
    logic              r_error          [N_TAG];
    logic [1:0]        last_rresp       [N_TAG];

    int                read_idx;

    // Sequential logic
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            rdf_push_valid          <= 1'b0;
            rdf_push_payload        <= '0;

            cpl_push_valid          <= 1'b0;
            cpl_push_data           <= '0;

            for(int i = 0 ; i < N_TAG ; i++) begin
                reads_inflight[i]  <= 1'b0;
                beat_cnt[i]        <= '0;
                r_error[i]         <= 1'b0;
                last_rresp[i]      <= 2'b00;
            end
        end
        else begin
            // default: no pushes unless we see activity
            rdf_push_valid          <= 1'b0;
            if(cpl_push_valid & cpl_push_ready) begin
                cpl_push_valid      <= 1'b0;
            end

            // -----------------------------
            // READ DATA beat arrives
            // -----------------------------
            if (rvalid && rready) begin
                read_idx            = rid;

                if(rdf_push_ready) begin
                    rdf_entry_t     beat;
                    // Prepare RDF entry
                    beat.tag   = rid;
                    beat.data  = rdata;
                    beat.last  = rlast;
                    beat.resp  = rresp;

                    rdf_push_payload <= beat;
                    rdf_push_valid   <= 1'b1;
                end

                if (!reads_inflight[read_idx]) begin  // Start of burst for this TAG
                    reads_inflight[read_idx]    <= 1'b1;
                    beat_cnt[read_idx]          <= 8'd0;
                    r_error[read_idx]           <= 1'b0;
                end
                else begin
                    beat_cnt[read_idx]          <= beat_cnt[read_idx] + 1;
                end

                last_rresp[read_idx]            <= rresp;
                if (rresp[read_idx] != 2'b00)   r_error[read_idx] <= 1'b1;

                // Debug
                // synthesis translate_off
                $display("%t [RESP_COLLECT] RBEAT: RID=%0d RRESP=%0d RLAST=%0b", $time, rid, rresp, rlast);
                // synthesis translate_on

                // End of burst: emit completion
                if (rlast) begin
                    cpl_reg.is_write  = 1'b0;
                    cpl_reg.tag       = rid;
                    cpl_reg.resp      = last_rresp[read_idx];
                    cpl_reg.error     = r_error[read_idx];
                    cpl_reg.num_beats = beat_cnt[read_idx] + 1; // include this beat

                    reads_inflight[read_idx]    <= 1'b0;

                    if(!cpl_push_valid)begin
                        cpl_push_data  <= cpl_reg;
                        cpl_push_valid <= 1'b1;
                        // Debug
                        // synthesis translate_off
                        $display("%t [RESP_COLLECT] READ done: RID=%0d RRESP=%0d beats=%0d", $time, read_idx, last_rresp[read_idx], beat_cnt[read_idx]+1);
                        // synthesis translate_on
                    end
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