import apb2axi_pkg::*;

module apb2axi_fifo #(
    parameter int ENTRY_WIDTH = 64,
    parameter int FIFO_DEPTH  = 16          // must be >= 1
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

    localparam int PTR_W = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH);

    logic [ENTRY_WIDTH-1:0] mem [FIFO_DEPTH];
    logic [PTR_W-1:0]       wptr, rptr;
    logic [PTR_W:0]         count;    // can count up to FIFO_DEPTH

    // status
    wire full  = (count == FIFO_DEPTH);
    wire empty = (count == 0);

    assign push_ready = !full;
    assign pop_valid  = !empty;
    assign pop_data   = mem[rptr];

    wire do_push = push_valid && push_ready;
    wire do_pop  = pop_valid  && pop_ready;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            wptr  <= '0;
            rptr  <= '0;
            count <= '0;
        end
        else begin
            // write
            if (do_push) begin
                mem[wptr] <= push_data;
                wptr      <= (wptr + 1'b1);
            end

            // read
            if (do_pop) begin
                rptr <= (rptr + 1'b1);
            end

            // update count
            case ({do_push, do_pop})
                2'b10: count <= count + 1'b1; // push only
                2'b01: count <= count - 1'b1; // pop only
                default: ;                    // same or both (no net change)
            endcase
        end
    end

endmodule