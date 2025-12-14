import apb2axi_pkg::*;

module apb2axi_response_handler #()(
    input  logic                    pclk,
    input  logic                    presetn,

    // RDF
    input  logic                    rsp_rdf_pop_vld,
    input  rdf_entry_t              rsp_rdf_pop_payload,
    output logic                    rsp_rdf_pop_rdy,

    // Completion FIFO (consume completetions)
    input  logic                    rsp_cq_pop_vld,
    input  completion_entry_t       rsp_cq_pop_data,
    output logic                    rsp_cq_pop_rdy,

    // APB Data drain
    input  logic                    rdf_reg_data_req,
    input  logic [TAG_W-1:0]        rdf_reg_data_req_tag,
    input  logic                    rdf_reg_data_rdy,
    output logic                    rdf_reg_data_vld,
    output logic [APB_DATA_W-1:0]   rdf_reg_data_out,
    output logic                    rdf_reg_data_last,

    // Directory completion
    output logic                    cq_dir_cpl_vld,
    output completion_entry_t       cq_dir_cpl_entry,
    input  logic                    cq_dir_cpl_rdy

);

    // ======================================================================
    // Completion Indicator (for the Directory)
    // ======================================================================
    always_ff @(posedge pclk) begin
        if (!presetn) begin
            rsp_cq_pop_rdy                  <= 1'b0;
            cq_dir_cpl_vld                  <= 1'b0;
        end else begin
            completion_entry_t cq_cpl;
            cq_cpl                          = rsp_cq_pop_data;      // FIXME check if possible without delay
            rsp_cq_pop_rdy                  <= cq_dir_cpl_rdy;
            cq_dir_cpl_vld                  <= 1'b0;
            if (rsp_cq_pop_vld && rsp_cq_pop_rdy) begin
                cq_dir_cpl_vld              <= 1'b1;
                cq_dir_cpl_entry            <= cq_cpl;
            end      
        end
    end

    // ======================================================================
    // APB Storing & Slicing: read 32-bit words
    // ======================================================================
    rd_beat_t                               tag_mem[TAG_NUM][MAX_BEATS_NUM];

    logic [$clog2(MAX_BEATS_NUM)-1:0]       head[TAG_NUM];
    logic [$clog2(MAX_BEATS_NUM)-1:0]       tail[TAG_NUM];
    logic [$clog2(MAX_BEATS_NUM+1)-1:0]     count[TAG_NUM];

    logic [AXI_DATA_W-1:0]                  cur_data[TAG_NUM];
    logic                                   cur_last[TAG_NUM];
    logic                                   cur_valid[TAG_NUM];
    logic [$clog2(AXI_DATA_W):0]            cur_idx[TAG_NUM];

    int                                     tag_idx;
    logic [$clog2(AXI_DATA_W):0]            next_idx;

    assign rsp_rdf_pop_rdy = (count[rsp_rdf_pop_payload.tag] < MAX_BEATS_NUM);        // STALL AXI if tag handler's FIFO is FULL FIXME

    always_ff @(posedge pclk) begin
        if (!presetn) begin
            for (int t=0; t < TAG_NUM; t++) begin
                cur_valid[t]        <= 1'b0;
                cur_idx[t]          <= '0;
                cur_last[t]         <= 1'b0;
                cur_data[t]         <= '0;
            end
            for (int t=0; t < TAG_NUM; t++) begin
                head[t]             <= '0;
                tail[t]             <= '0;
                count[t]            <= '0;
            end            
            rdf_reg_data_vld        <= 1'b0;
            rdf_reg_data_last       <= 1'b0;
        end 
        else begin

            tag_idx                 = rdf_reg_data_req_tag;

            if (rsp_rdf_pop_vld && rsp_rdf_pop_rdy) begin                   // Enqueue in Handler FIFO
                int tg;
                tg                  = rsp_rdf_pop_payload.tag;

                tag_mem[tg][tail[tg]].data = rsp_rdf_pop_payload.data;      // Actual enqueueing
                tag_mem[tg][tail[tg]].resp = rsp_rdf_pop_payload.resp;
                tag_mem[tg][tail[tg]].last = rsp_rdf_pop_payload.last;

                tail[tg]            <= tail[tg] + 1'b1;                 // Move pointers
                count[tg]           <= count[tg] + 1'b1;
            end

            if(rdf_reg_data_rdy && rdf_reg_data_vld) rdf_reg_data_vld <= 1'b0;
            if(rdf_reg_data_rdy && rdf_reg_data_vld) rdf_reg_data_last  <= 1'b0;
            // FIXME consider adding error incidation when MEM saturates
            if (rdf_reg_data_req) begin

                if (!cur_valid[tag_idx]) begin
                    if (count[tag_idx] > 0) begin
                        rd_beat_t beat;
                        beat = tag_mem[tag_idx][head[tag_idx]];         // Read beat from FIFO head

                        head[tag_idx]  <= head[tag_idx] + 1'b1;         // Consume FIFO entry
                        count[tag_idx] <= count[tag_idx] - 1'b1;
                        
                        rdf_reg_data_out            <= beat.data[0 +: APB_DATA_W];   // Output the first APB word
                        rdf_reg_data_vld            <= 1'b1;

                        if (APB_DATA_W == AXI_DATA_W) begin             // Whole AXI beat fits in one APB word
                            cur_valid[tag_idx]      <= 1'b0;
                            cur_idx[tag_idx]        <= '0;
                            cur_last[tag_idx]       <= 1'b0;
                            if (beat.last && count[tag_idx] == 1) begin // This was the last beat for this tag
                                rdf_reg_data_last   <= 1'b1;
                            end
                        end else begin                                  // Additoinal words remain in this beat -> keep it in cur_*
                            cur_valid[tag_idx]      <= 1'b1;
                            cur_idx[tag_idx]        <= APB_DATA_W;
                            cur_data[tag_idx]       <= beat.data;
                            cur_last[tag_idx]       <= beat.last;
                        end
                    end
                end else begin                                          // Normal slicing for subsequent words of this beat                    
                    rdf_reg_data_out                <= cur_data[tag_idx][cur_idx[tag_idx] +: APB_DATA_W];
                    rdf_reg_data_vld                <= 1'b1;

                    next_idx                        = cur_idx[tag_idx] + APB_DATA_W;

                    if (next_idx == AXI_DATA_W) begin
                        cur_valid[tag_idx]          <= 1'b0;
                    if (cur_last[tag_idx] && count[tag_idx] == 0)
                        rdf_reg_data_last           <= 1'b1;
                    end

                    cur_idx[tag_idx]                <= next_idx;
                end

            end
        end
    end

// ==========================================================================================================================
// =================================================== DEBUG infra (per-tag) ================================================
// ==========================================================================================================================

    bit rh_debug_en;
    int rh_debug_tag;

    initial begin
        rh_debug_en  = $test$plusargs("APB2AXI_RH_DEBUG");
        rh_debug_tag = -1;

        // Read +APB2AXI_RH_DEBUG_TAG=<N>
        if (!$value$plusargs("APB2AXI_RH_DEBUG_TAG=%d", rh_debug_tag))
            rh_debug_tag = -1;

        if (rh_debug_en) begin
            if (rh_debug_tag < 0 || rh_debug_tag >= TAG_NUM) begin
                $display("%t [RH_DBG] ENABLED (+APB2AXI_RH_DEBUG) but missing/invalid +APB2AXI_RH_DEBUG_TAG=<0..%0d> (tag=%0d) -> dumps DISABLED",
                        $time, TAG_NUM-1, rh_debug_tag);
                rh_debug_en = 1'b0; // avoid accidental spam
            end else begin
                $display("%t [RH_DBG] ResponseHandler debug ENABLED (+APB2AXI_RH_DEBUG +APB2AXI_RH_DEBUG_TAG=%0d)", $time, rh_debug_tag);
            end
        end
    end

    function automatic string resp2str(logic [1:0] r);
        case (r)
            2'b00: return "OKAY  ";
            2'b01: return "EXOKAY";
            2'b10: return "SLVERR";
            2'b11: return "DECERR";
            default: return "UNKN  ";
        endcase
    endfunction

    task automatic rh_dump_tag(int t, string reason="");
        int idx;
        if (!rh_debug_en) return;

        $display("%t [RH_DUMP] ---- TAG=%0d (%s) ---- head=%0d tail=%0d count=%0d cur_valid=%0b cur_idx=%0d cur_last=%0b",
                $time, t, reason, head[t], tail[t], count[t], cur_valid[t], cur_idx[t], cur_last[t]);

        // ACTIVE window dump only: print "count" entries starting from head (wrap safe)
        idx = head[t];
        for (int k = 0; k < MAX_BEATS_NUM; k++) begin
            rd_beat_t b;
            b = tag_mem[t][idx];
            $display("  act[%0d] mem[%0d]= data=%h resp=%s last=%0b", k, idx, b.data, resp2str(b.resp), b.last);
            idx = (idx + 1) % MAX_BEATS_NUM;
        end

        $display("%t [RH_DUMP] ----------------------------", $time);
    endtask

    task automatic rh_dump_one(string reason="");
        if (!rh_debug_en) return;

        // Helpful one-line summaries to correlate with waveforms
        $display("%t [RH_DUMP] ===== RH dump (%s) tag=%0d =====", $time, reason, rh_debug_tag);
        $display("  APB_REQ: req=%0b tag=%0d ready=%0b  out_vld=%0b out_last=%0b out_data=%h",
                rdf_reg_data_req, rdf_reg_data_req_tag, rdf_reg_data_rdy,
                rdf_reg_data_vld, rdf_reg_data_last, rdf_reg_data_out);
        $display("  RDF_IN : pop_vld=%0b pop_rdy=%0b tag=%0d last=%0b resp=%s data=%h",
                rsp_rdf_pop_vld, rsp_rdf_pop_rdy,
                rsp_rdf_pop_payload.tag, rsp_rdf_pop_payload.last, resp2str(rsp_rdf_pop_payload.resp),
                rsp_rdf_pop_payload.data);
        $display("  CQ_IN  : pop_vld=%0b pop_rdy=%0b  dir_cpl_vld=%0b dir_cpl_rdy=%0b",
                rsp_cq_pop_vld, rsp_cq_pop_rdy, cq_dir_cpl_vld, cq_dir_cpl_rdy);

        rh_dump_tag(rh_debug_tag, reason);
        $display("%t [RH_DUMP] ================================", $time);
    endtask

    always_ff @(posedge pclk) begin
        if (rh_debug_en) begin
            if (!presetn)
                rh_dump_one("RESET");
            else
                rh_dump_one("CYCLE");
        end
    end

// ==========================================================================================================================
// ==========================================================================================================================
// ==========================================================================================================================

endmodule