/*------------------------------------------------------------------------------
 * Fully CDC-safe asynchronous FIFO
 *  - Gray-coded pointers
 *  - VALID/READY handshake on both sides
 *  - Drop-in replacement for Nir's original async FIFO
 *----------------------------------------------------------------------------*/

module apb2axi_fifo_async #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 16      // MUST BE POWER OF 2
)(
    // Write clock domain
    input  logic               wr_clk,
    input  logic               wr_resetn,
    input  logic               wr_vld,
    input  logic [WIDTH-1:0]   wr_data,
    output logic               wr_rdy,

    // Read clock domain
    input  logic               rd_clk,
    input  logic               rd_resetn,
    output logic               rd_vld,
    output logic [WIDTH-1:0]   rd_data,
    input  logic               rd_rdy
);

    // ------------------------------------------------------------
    // Local parameters / storage
    // ------------------------------------------------------------
    localparam int PTR_W = $clog2(DEPTH);

    logic [WIDTH-1:0] mem [0:DEPTH-1];

    // ------------------------------------------------------------
    // Pointers (binary + Gray)
    // ------------------------------------------------------------
    logic [PTR_W:0] wptr_bin,  wptr_bin_next;
    logic [PTR_W:0] rptr_bin,  rptr_bin_next;

    logic [PTR_W:0] wptr_gray, wptr_gray_next;
    logic [PTR_W:0] rptr_gray, rptr_gray_next;

    // Synced pointers
    logic [PTR_W:0] wptr_gray_rdclk_1, wptr_gray_rdclk_2;
    logic [PTR_W:0] rptr_gray_wrclk_1, rptr_gray_wrclk_2;

    // Status
    logic           full;
    logic           empty;
    logic [PTR_W:0] wbin_sync;   // write pointer in read domain (binary)

    // ------------------------------------------------------------
    // Gray encode/decode
    // ------------------------------------------------------------
    function automatic logic [PTR_W:0] bin2gray(input logic [PTR_W:0] b);
        return (b >> 1) ^ b;
    endfunction

    function automatic logic [PTR_W:0] gray2bin(input logic [PTR_W:0] g);
        logic [PTR_W:0] b;
        b[PTR_W] = g[PTR_W];
        for (int i = PTR_W-1; i >= 0; i--) begin
            b[i] = b[i+1] ^ g[i];
        end
        return b;
    endfunction

    // ------------------------------------------------------------
    // FULL + EMPTY detection (pure combinational)
    // ------------------------------------------------------------
    always_comb begin
        // Next write pointer
        wptr_bin_next  = wptr_bin + 1;
        wptr_gray_next = bin2gray(wptr_bin_next);

        // FULL: classic async FIFO condition with extra MSB
        full = (wptr_gray_next ==
                {~rptr_gray_wrclk_2[PTR_W:PTR_W-1],
                  rptr_gray_wrclk_2[PTR_W-2:0]});

        // EMPTY: compare synced write pointer with local read pointer
        wbin_sync = gray2bin(wptr_gray_rdclk_2);
        empty     = (wbin_sync == rptr_bin);
    end

    // ------------------------------------------------------------
    // WRITE CLOCK DOMAIN
    // ------------------------------------------------------------
    always_ff @(posedge wr_clk or negedge wr_resetn) begin
        if (!wr_resetn) begin
            wptr_bin          <= '0;
            wptr_gray         <= '0;
            rptr_gray_wrclk_1 <= '0;
            rptr_gray_wrclk_2 <= '0;
            wr_rdy            <= 1'b1;
        end
        else begin
            // sync read pointer into write domain
            rptr_gray_wrclk_1 <= rptr_gray;
            rptr_gray_wrclk_2 <= rptr_gray_wrclk_1;

            // ready when not full
            wr_rdy <= !full;

            // PUSH
            if (wr_vld && wr_rdy) begin
                mem[wptr_bin[PTR_W-1:0]] <= wr_data;
                wptr_bin  <= wptr_bin_next;
                wptr_gray <= wptr_gray_next;
            end
        end
    end

    // ------------------------------------------------------------
    // READ CLOCK DOMAIN
    // ------------------------------------------------------------
    always_ff @(posedge rd_clk or negedge rd_resetn) begin
        if (!rd_resetn) begin
            rptr_bin          <= '0;
            rptr_gray         <= '0;
            wptr_gray_rdclk_1 <= '0;
            wptr_gray_rdclk_2 <= '0;
            rd_vld            <= 1'b0;
            rd_data           <= '0;
        end
        else begin
            // sync write pointer into read domain
            wptr_gray_rdclk_1 <= wptr_gray;
            wptr_gray_rdclk_2 <= wptr_gray_rdclk_1;

            // valid whenever FIFO is non-empty
            rd_vld <= !empty;

            // POP only on valid & ready
            if (!empty && rd_rdy) begin
                rd_data <= mem[rptr_bin[PTR_W-1:0]];
                rd_vld  <= '1;
                rptr_bin  <= rptr_bin + 1'b1;
                rptr_gray <= bin2gray(rptr_bin + 1'b1);
            end
        end
    end

endmodule