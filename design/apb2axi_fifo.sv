
/*------------------------------------------------------------------------------
 * File          : apb2axi_fifo.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Description   : Valid/ready FIFO
 *------------------------------------------------------------------------------*/

module apb2axi_fifo #(
    parameter int ENTRY_WIDTH = 64
)(
    input  logic                   clk,
    input  logic                   resetn,

    // Push side (producer)
    input  logic                   push_valid,
    output logic                   push_ready,
    input  logic [ENTRY_WIDTH-1:0] push_data,

    // Pop side (consumer)
    output logic                   pop_valid,
    input  logic                   pop_ready,
    output logic [ENTRY_WIDTH-1:0] pop_data
);

    logic                          full;
    logic [ENTRY_WIDTH-1:0]        data_q;

    // Push is allowed when not full
    assign push_ready = !full;

    // Pop is allowed when full
    assign pop_valid  = full;
    assign pop_data   = data_q;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            full   <= 1'b0;
            data_q <= '0;
        end
        else begin
            // default: no change
            // handle push
            if (push_valid && push_ready) begin
                data_q <= push_data;
                full   <= 1'b1;
            end

            // handle pop
            if (pop_valid && pop_ready) begin
                full <= 1'b0;
            end
        end
    end

endmodule
