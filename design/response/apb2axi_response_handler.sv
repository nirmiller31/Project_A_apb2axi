import apb2axi_pkg::*;

module apb2axi_response_handler #(
    parameter int TAG_W        = TAG_W,
    parameter int DATA_W       = AXI_DATA_W,
    parameter int COMPLETION_W = COMPLETION_W,
    parameter int N_TAG        = (1 << TAG_W),
    parameter int APB_W        = APB_DATA_W,
    parameter int TAG_DEPTH    = MAX_BEATS_NUM      //////////////////////////////////////////// CHANGE =====================================
)(
    input  logic                pclk,
    input  logic                presetn,

    // RDF FIFO
    input  logic                rdf_pop_valid,
    input  rdf_entry_t          rdf_pop_payload,
    output logic                rdf_pop_ready,

    // Completion FIFO
    input  logic                cq_pop_valid,
    input  logic [COMPLETION_W-1:0] cq_pop_data,
    output logic                cq_pop_ready,

    // APB Data drain
    input  logic                data_req,
    input  logic [TAG_W-1:0]    data_req_tag,
    input  logic                data_ready,
    output logic                data_valid,
    output logic [APB_W-1:0]    data_out,
    output logic                data_last,

    // Directory completion
    output logic                dir_cpl_valid,
    output logic [TAG_W-1:0]    dir_cpl_tag,
    output logic                dir_cpl_is_write,
    output logic [1:0]          dir_cpl_resp,
    output logic                dir_cpl_error,
    output logic [7:0]          dir_cpl_num_beats,
    input  logic                dir_cpl_ready,

    // Regfile status
    output logic                rd_status_valid,
    output logic [TAG_W-1:0]    rd_status_tag,
    output logic [7:0]          rd_status_num_beats,
    output logic [1:0]          rd_status_resp,
    output logic                rd_status_error,
    input  logic                rd_status_ready
);

    // ======================================================================
    // Beat format (synthesizable)
    // ======================================================================
    typedef struct packed {
        logic [DATA_W-1:0] data;
        logic [1:0]        resp;
        logic              last;
    } beat_t;

    // ======================================================================
    // *** Circular FIFOs per TAG  ******************************************
    // ======================================================================
    localparam int BEAT_W = $bits(beat_t); //////////////////////////////////////////// CHANGE =====================================

    // Storage
    beat_t tag_mem [N_TAG][TAG_DEPTH];          //////////////////////////////////////////// CHANGE =====================================

    // FIFO state
    logic [$clog2(TAG_DEPTH)-1:0] head [N_TAG];  //////////////////////////////////////////// CHANGE =====================================
    logic [$clog2(TAG_DEPTH)-1:0] tail [N_TAG];  //////////////////////////////////////////// CHANGE =====================================
    logic [$clog2(TAG_DEPTH+1)-1:0] count [N_TAG]; //////////////////////////////////////////// CHANGE =====================================

    // ======================================================================
    // BLOCK A — Completion (CQ → DIR + REGS)
    // ======================================================================
    always_ff @(posedge pclk) begin
        if (!presetn) begin
            cq_pop_ready    <= 1'b0;
            dir_cpl_valid   <= 1'b0;
            rd_status_valid <= 1'b0;
        end else begin
            cq_pop_ready <= dir_cpl_ready;

            dir_cpl_valid <= 1'b0;

            if (cq_pop_valid && cq_pop_ready) begin
                completion_entry_t cpl;
                cpl = cq_pop_data;

                // → Directory
                dir_cpl_valid     <= 1'b1;
                dir_cpl_tag       <= cpl.tag;
                dir_cpl_is_write  <= cpl.is_write;
                dir_cpl_resp      <= cpl.resp;
                dir_cpl_error     <= cpl.error;
                dir_cpl_num_beats <= cpl.num_beats;

                // → Regfile only for *reads*
                if (!cpl.is_write) begin
                    rd_status_valid     <= 1'b1;
                    rd_status_tag       <= cpl.tag;
                    rd_status_resp      <= cpl.resp;
                    rd_status_error     <= cpl.error;
                    rd_status_num_beats <= cpl.num_beats;
                end
            end
        end
    end


    // ======================================================================
    // BLOCK B — RDF ingest (AXI → handler)
    // ======================================================================

    // STALL AXI if tag FIFO is FULL ////////////////////////////////////////////////////// CHANGE =====================================
    assign rdf_pop_ready = (count[rdf_pop_payload.tag] < TAG_DEPTH); //////////////////////////////////////////// CHANGE =====================================

    // always_ff @(posedge pclk) begin
    //     if (!presetn) begin
    //         for (int t=0; t<N_TAG; t++) begin
    //             head[t]  <= '0;
    //             tail[t]  <= '0;
    //             count[t] <= '0;
    //         end
    //     end else begin
    //         if (rdf_pop_valid && rdf_pop_ready) begin
    //             int tg = rdf_pop_payload.tag;

    //             tag_mem[tg][tail[tg]].data = rdf_pop_payload.data;
    //             tag_mem[tg][tail[tg]].resp = rdf_pop_payload.resp;
    //             tag_mem[tg][tail[tg]].last = rdf_pop_payload.last;

    //             tail[tg]  <= tail[tg] + 1'b1;
    //             count[tg] <= count[tg] + 1'b1;
    //         end
    //     end
    // end


    // ======================================================================
    // BLOCK C — APB slicing: read 32-bit words
    // ======================================================================

    logic [DATA_W-1:0] cur_data     [N_TAG];
    logic               cur_last     [N_TAG];
    logic               cur_valid    [N_TAG];
    logic [$clog2(DATA_W):0] cur_idx[N_TAG];

    integer tag_idx;
    logic [$clog2(DATA_W):0] next_idx;

    always_ff @(posedge pclk) begin
        if (!presetn) begin
            for (int t=0; t<N_TAG; t++) begin
                cur_valid[t] <= 1'b0;
                cur_idx[t]   <= '0;
                cur_last[t]  <= 1'b0;
                cur_data[t]  <= '0;
            end
            for (int t=0; t<N_TAG; t++) begin
                head[t]  <= '0;
                tail[t]  <= '0;
                count[t] <= '0;
            end            
            data_valid <= 1'b0;
            data_last  <= 1'b0;
        end else begin
            // defaults
            // data_valid <= 1'b0;
            // data_last  <= 1'b0;

            tag_idx = data_req_tag;

            if (rdf_pop_valid && rdf_pop_ready) begin
                int tg;
                tg = rdf_pop_payload.tag;

                tag_mem[tg][tail[tg]].data = rdf_pop_payload.data;
                tag_mem[tg][tail[tg]].resp = rdf_pop_payload.resp;
                tag_mem[tg][tail[tg]].last = rdf_pop_payload.last;

                tail[tg]  <= tail[tg] + 1'b1;
                count[tg] <= count[tg] + 1'b1;
            end

            if(data_ready && data_valid) data_valid <= 1'b0;
            if(data_ready && data_valid) data_last  <= 1'b0;

            if (data_req) begin
                if (!cur_valid[tag_idx]) begin
                    if (count[tag_idx] > 0) begin
                        // read beat from FIFO head
                        beat_t beat;
                        beat = tag_mem[tag_idx][head[tag_idx]];

                        // consume FIFO entry
                        head[tag_idx]  <= head[tag_idx] + 1'b1;
                        count[tag_idx] <= count[tag_idx] - 1'b1;

                        // immediately output the *first* APB word
                        data_out   <= beat.data[0 +: APB_W];

                        data_valid <= 1'b1;

                        if (APB_W == DATA_W) begin
                            // whole AXI beat fits in one APB word
                            cur_valid[tag_idx] <= 1'b0;
                            cur_idx[tag_idx]   <= '0;
                            cur_last[tag_idx]  <= 1'b0;
                            if (beat.last && count[tag_idx] == 1) begin
                                // this was the last beat for this tag
                                data_last <= 1'b1;
                            end
                        end else begin
                            // more words remain in this beat → keep it in cur_*
                            cur_valid[tag_idx] <= 1'b1;
                            cur_idx[tag_idx]   <= APB_W;
                            cur_data[tag_idx]  <= beat.data;
                            cur_last[tag_idx]  <= beat.last;
                        end
                    end
            end else begin
                // normal slicing for subsequent words of this beat
                data_out   <= cur_data[tag_idx][cur_idx[tag_idx] +: APB_W];
                data_valid <= 1'b1;

                next_idx = cur_idx[tag_idx] + APB_W;

                if (next_idx == DATA_W) begin
                    cur_valid[tag_idx] <= 1'b0;
                if (cur_last[tag_idx] && count[tag_idx] == 0)
                    data_last <= 1'b1;
                end

                cur_idx[tag_idx] <= next_idx;
            end
            end
        end
    end

`ifndef SYNTHESIS
    // ---------------- DEBUG SIGNALS ----------------
    // focus on the tag currently requested by APB
    logic [TAG_W-1:0]            dbg_tag;
    logic [TAG_W-1:0]            dbg_rdf_tag;

    logic [$clog2(TAG_DEPTH)-1:0] dbg_head_idx;
    logic [$clog2(TAG_DEPTH)-1:0] dbg_tail_idx;
    logic [$clog2(TAG_DEPTH+1)-1:0] dbg_count;

    logic [DATA_W-1:0]           dbg_fifo_head_data;
    logic [1:0]                  dbg_fifo_head_resp;
    logic                        dbg_fifo_head_last;

    logic [DATA_W-1:0]           dbg_cur_data;
    logic [$clog2(DATA_W):0]     dbg_cur_idx;
    logic                        dbg_cur_valid;
    logic                        dbg_cur_last;

    logic [APB_W-1:0]            dbg_cur_word;
    logic                        dbg_cq_fire;
    completion_entry_t           dbg_cpl;

    always_comb begin
        // which tag we’re “looking at”
        dbg_tag     = data_req_tag;
        dbg_rdf_tag = rdf_pop_payload.tag;

        // per-tag FIFO state
        dbg_head_idx = head[dbg_tag];
        dbg_tail_idx = tail[dbg_tag];
        dbg_count    = count[dbg_tag];

        // entry at FIFO head for this tag
        dbg_fifo_head_data = tag_mem[dbg_tag][dbg_head_idx].data;
        dbg_fifo_head_resp = tag_mem[dbg_tag][dbg_head_idx].resp;
        dbg_fifo_head_last = tag_mem[dbg_tag][dbg_head_idx].last;

        // current sliced beat state
        dbg_cur_data  = cur_data[dbg_tag];
        dbg_cur_idx   = cur_idx[dbg_tag];
        dbg_cur_valid = cur_valid[dbg_tag];
        dbg_cur_last  = cur_last[dbg_tag];

        // word that will be output on NEXT data_req for this tag
        dbg_cur_word = cur_data[dbg_tag][cur_idx[dbg_tag] +: APB_W];

        // completion side
        dbg_cq_fire = cq_pop_valid & cq_pop_ready;
        dbg_cpl     = cq_pop_data;
    end
`endif

endmodule