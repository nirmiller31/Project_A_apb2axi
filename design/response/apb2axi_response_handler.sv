//------------------------------------------------------------------------------
// response_handler.sv
// PCLK-domain handler for completed AXI transactions:
//  - Pops completion entries from CQ (aka completion FIFO)
//  - Updates Directory (via a simple completion interface)
//  - Keeps last completion for APB status
//------------------------------------------------------------------------------

import apb2axi_pkg::*;

module apb2axi_response_handler #(
    parameter int TAG_W_P  = TAG_W,
    parameter int CPL_W_P  = COMPLETION_W
)(
    input  logic                pclk,
    input  logic                presetn,

    // CQ pop interface (PCLK domain, after CDC)
    input  logic                cq_pop_valid,
    input  logic [CPL_W_P-1:0]  cq_pop_data,
    output logic                cq_pop_ready,

    // Directory completion interface (PCLK)
    output logic                dir_cpl_valid,
    output logic [TAG_W_P-1:0]  dir_cpl_tag,
    output logic                dir_cpl_is_write,
    output logic                dir_cpl_error,
    output logic [1:0]          dir_cpl_resp,
    output logic [7:0]          dir_cpl_num_beats,
    input  logic                dir_cpl_ready
);

    completion_entry_t cpl;

    always_comb begin
        cpl = completion_entry_t'(cq_pop_data);
    end

    always_ff @(posedge pclk) begin
        if (!presetn) begin
            cq_pop_ready   <= 1'b0;
            dir_cpl_valid  <= 1'b0;
            dir_cpl_tag    <= '0;
            dir_cpl_is_write <= 1'b0;
            dir_cpl_error  <= 1'b0;
            dir_cpl_resp   <= 2'b00;
            dir_cpl_num_beats <= '0;
        end
        else begin
            cq_pop_ready  <= 1'b0;
            dir_cpl_valid <= 1'b0;

            // Simple handshake: when both CQ and Directory are ready,
            // move one completion through.
            if (cq_pop_valid && dir_cpl_ready) begin
                cq_pop_ready      <= 1'b1;

                dir_cpl_valid     <= 1'b1;
                dir_cpl_tag       <= cpl.tag;
                dir_cpl_is_write  <= cpl.is_write;
                dir_cpl_error     <= cpl.error;
                dir_cpl_resp      <= cpl.resp;
                dir_cpl_num_beats <= cpl.num_beats;

                $display("%t [RESP_HANDLER] TAG=%0d is_write=%0d error=%0d beats=%0d",
                        $time, cpl.tag, cpl.is_write, cpl.error, cpl.num_beats);
            end        
        end
    end

endmodule