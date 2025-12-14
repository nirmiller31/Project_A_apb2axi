/*------------------------------------------------------------------------------
 * File          : response_collector.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Description   : Collects AXI3 responses (R/B), pushes data into RDF and
 *                 bundles completions into a completion FIFO (ACLK domain).
 *------------------------------------------------------------------------------*/
import apb2axi_pkg::*;

module apb2axi_response_collector #()(
    input  logic                    aclk,
    input  logic                    aresetn,
    // AXI Read Data Channel (R)
    input  logic [TAG_W-1:0]        rid,
    input  logic [AXI_DATA_W-1:0]   rdata,
    input  logic [1:0]              rresp,
    input  logic                    rlast,
    input  logic                    rvalid,
    output logic                    rready,
    // AXI Write Response Channel (B)
    input  logic [TAG_W-1:0]        bid,
    input  logic [1:0]              bresp,
    input  logic                    bvalid,
    output logic                    bready,

    // RDF interface (AXI side)
    output logic                    rsp_rdf_push_vld,
    output rdf_entry_t              rsp_rdf_push_payload,
    input  logic                    rsp_rdf_push_rdy,
    // Completion FIFO IF (AXI side)
    output logic                    rsp_cq_push_vld,
    output logic [CPL_W-1:0]        rsp_cq_push_data,
    input  logic                    rsp_cq_push_rdy
);

    completion_entry_t cpl_reg;

    logic                           reads_inflight [TAG_NUM];
    logic [TAG_W-1:0]               cur_rid        [TAG_NUM];
    logic [7:0]                     beat_cnt       [TAG_NUM];
    logic                           r_error        [TAG_NUM];
    logic [1:0]                     last_rresp     [TAG_NUM];

    int read_idx;

    assign rready = rsp_rdf_push_rdy;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            rsp_rdf_push_vld        <= 1'b0;
            rsp_rdf_push_payload    <= '0;

            rsp_cq_push_vld         <= 1'b0;
            rsp_cq_push_data        <= '0;

            for (int i = 0; i < TAG_NUM; i++) begin
                reads_inflight[i]   <= 1'b0;
                beat_cnt[i]         <= '0;
                r_error[i]          <= 1'b0;
                last_rresp[i]       <= 2'b00;
            end
        end
        else begin
            rsp_rdf_push_vld        <= 1'b0;            // Default Values
            rsp_cq_push_vld        <= 1'b0;
            // ====================================================
            // READ DATA & COMPLETION HANDLING
            // ====================================================
            if (rvalid && rready) begin
                read_idx                        = rid;
                if (rsp_rdf_push_rdy) begin             // RDF push
                    rdf_entry_t                 beat;
                    beat.tag                    = rid;
                    beat.data                   = rdata;
                    beat.last                   = rlast;
                    beat.resp                   = rresp;

                    rsp_rdf_push_payload        <= beat;
                    rsp_rdf_push_vld            <= 1'b1;
                end
                if (!reads_inflight[read_idx]) begin    // Reset read in flight
                    reads_inflight[read_idx]    <= 1'b1;
                    beat_cnt[read_idx]          <= 8'd0;
                    r_error[read_idx]           <= 1'b0;
                end
                else begin
                    beat_cnt[read_idx]          <= beat_cnt[read_idx] + 1;
                end

                last_rresp[read_idx]            <= rresp;
                if (rresp != 2'b00)             // Error detector FIXME handle errors
                    r_error[read_idx]           <= 1'b1;

                if (rlast) begin                        // Handle last beat (end of read)
                    cpl_reg.is_write            = 1'b0;
                    cpl_reg.tag                 = rid;
                    cpl_reg.resp                = last_rresp[read_idx];
                    cpl_reg.error               = r_error[read_idx];
                    cpl_reg.num_beats           = beat_cnt[read_idx] + 1;

                    reads_inflight[read_idx]    <= 1'b0;

                    if (rsp_cq_push_rdy) begin
                        rsp_cq_push_data       <= cpl_reg;
                        rsp_cq_push_vld        <= 1'b1;       
                    end
                end
            end

            // ====================================================
            // WRITE COMPLETION HANDLING
            // ====================================================
            if (bvalid && bready) begin
                completion_entry_t              bw_cpl;
                bw_cpl.is_write                 = 1'b1;
                bw_cpl.tag                      = bid;
                bw_cpl.resp                     = bresp;
                bw_cpl.error                    = (bresp != 2'b00);
                bw_cpl.num_beats                = 8'd0;

                if (rsp_cq_push_rdy) begin
                    rsp_cq_push_data           <= bw_cpl;
                    rsp_cq_push_vld            <= 1'b1;
                end
            end
        end
    end

// ==========================================================================================================================
// =================================================== DEBUG infra (per-tag) =================================================
// ==========================================================================================================================

    logic rc_dbg;
    initial begin
        rc_dbg = $test$plusargs("APB2AXI_RC_DEBUG");
        if (rc_dbg) $display("%t [RC_DBG] ENABLED (+APB2AXI_RC_DEBUG)", $time);
    end

    function automatic string resp2s(logic [1:0] r);
        case (r) 
            2'b00:      return "OKAY"; 
            2'b01:      return "EXOKAY"; 
            2'b10:      return "SLVERR"; 
            2'b11:      return "DECERR"; 
            default:    return "UNKN"; 
        endcase
    endfunction

    always_ff @(posedge aclk) if (rc_dbg && aresetn) begin
        if (rvalid && rready)
            $display("%t [RESPONSE COLLECTOR] R  tag=%0d resp=%s last=%0b rdf_rdy=%0b", $time, rid, resp2s(rresp), rlast, rsp_rdf_push_rdy);

        if (bvalid && bready)
            $display("%t [RESPONSE COLLECTOR] B  tag=%0d resp=%s cpl_rdy=%0b", $time, bid, resp2s(bresp), rsp_cq_push_rdy);

        if (rsp_rdf_push_vld)
            $display("%t [RESPONSE COLLECTOR] RDF push tag=%0d last=%0b resp=%s", $time, rsp_rdf_push_payload.tag, rsp_rdf_push_payload.last, resp2s(rsp_rdf_push_payload.resp));

        if (rsp_cq_push_vld) begin
            completion_entry_t c; c = rsp_cq_push_data;
            $display("%t [RESPONSE COLLECTOR] CPL push is_wr=%0b tag=%0d resp=%s err=%0b beats=%0d", $time, c.is_write, c.tag, resp2s(c.resp), c.error, c.num_beats);
        end
    end
// ==========================================================================================================================
// ==========================================================================================================================
// ==========================================================================================================================

endmodule