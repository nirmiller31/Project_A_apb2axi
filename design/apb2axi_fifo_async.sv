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
    input  logic               wr_valid,
    input  logic [WIDTH-1:0]   wr_data,
    output logic               wr_ready,

    // Read clock domain
    input  logic               rd_clk,
    input  logic               rd_resetn,
    output logic               rd_valid,
    output logic [WIDTH-1:0]   rd_data,
    input  logic               rd_ready
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
            wr_ready          <= 1'b1;

            `ifndef SYNTHESIS
            $display("[%0t][FIFO_WR] RESET", $time);
            `endif
        end
        else begin
            // sync read pointer into write domain
            rptr_gray_wrclk_1 <= rptr_gray;
            rptr_gray_wrclk_2 <= rptr_gray_wrclk_1;

            // ready when not full
            wr_ready <= !full;

            // PUSH
            if (wr_valid && wr_ready) begin
                mem[wptr_bin[PTR_W-1:0]] <= wr_data;
                wptr_bin  <= wptr_bin_next;
                wptr_gray <= wptr_gray_next;

                `ifndef SYNTHESIS
                $display("[%0t][FIFO_WR] PUSH data=%h idx=%0d",
                         $time, wr_data, wptr_bin[PTR_W-1:0]);
                if (^wr_data === 1'bx)
                    $display("[%0t][FIFO_WR] *** WARNING: X DATA WRITTEN ***",
                             $time);
                `endif
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
            rd_valid          <= 1'b0;
            rd_data           <= '0;

            `ifndef SYNTHESIS
            $display("[%0t][FIFO_RD] RESET", $time);
            `endif
        end
        else begin
            // sync write pointer into read domain
            wptr_gray_rdclk_1 <= wptr_gray;
            wptr_gray_rdclk_2 <= wptr_gray_rdclk_1;

            // valid whenever FIFO is non-empty
            rd_valid <= !empty;

            // POP only on valid & ready
            if (!empty && rd_ready) begin
                rd_data <= mem[rptr_bin[PTR_W-1:0]];
                rd_valid <= '1;

                `ifndef SYNTHESIS
                $display("[%0t][FIFO_RD] POP  data=%h idx=%0d",
                         $time, mem[rptr_bin[PTR_W-1:0]],
                         rptr_bin[PTR_W-1:0]);
                if (^mem[rptr_bin[PTR_W-1:0]] === 1'bx)
                    $display("[%0t][FIFO_RD] *** WARNING: X DATA READ ***",
                             $time);
                `endif

                rptr_bin  <= rptr_bin + 1'b1;
                rptr_gray <= bin2gray(rptr_bin + 1'b1);
            end
        end
    end

endmodule