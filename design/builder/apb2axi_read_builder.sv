module apb2axi_read_builder #(
    parameter int AXI_ADDR_W   = AXI_ADDR_W,
    parameter int AXI_DATA_W   = AXI_DATA_W,
    parameter int FIFO_ENTRY_W = REQ_WIDTH
)(
    input  logic                     aclk,
    input  logic                     aresetn,

    // READ FIFO
    input  logic                     rd_pop_valid,
    input  logic [FIFO_ENTRY_W-1:0]  rd_pop_data,
    output logic                     rd_pop_ready,

    // AXI AR
    output logic [AXI_ID_W-1:0]      arid,
    output logic [AXI_ADDR_W-1:0]    araddr,
    output logic [3:0]               arlen,
    output logic [2:0]               arsize,
    output logic [1:0]               arburst,
    output logic                     arlock,
    output logic [3:0]               arcache,
    output logic [2:0]               arprot,
    output logic                     arvalid,
    input  logic                     arready,

    // AXI R
    input  logic [AXI_ID_W-1:0]      rid,
    input  logic [AXI_DATA_W-1:0]    rdata,
    input  logic [1:0]               rresp,
    input  logic                     rlast,
    input  logic                     rvalid,
    output logic                     rready
);

    directory_entry_t entry;
    assign entry = rd_pop_data;

    assign arlock  = 1'b0;
    assign arcache = 4'b0011;
    assign arprot  = 3'b000;
    assign rready  = 1'b1;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            arvalid      <= 1'b0;
            rd_pop_ready <= 1'b0;
        end else begin
            rd_pop_ready <= 1'b0;   // default

            // Hold ARVALID until handshake
            if (arvalid && !arready) begin
                arvalid <= 1'b1;
            end
            // Launch NEW request only when ARVALID is 0
            else if (!arvalid && rd_pop_valid) begin
                arid    <= entry.tag;
                araddr  <= entry.addr;
                arlen   <= entry.len[3:0];
                arsize  <= entry.size;
                arburst <= 2'b01;

                arvalid      <= 1'b1;
                rd_pop_ready <= 1'b1;   // pop exactly once
            end
            // Otherwise: drop ARVALID after handshake
            else begin
                arvalid <= 1'b0;
            end
        end
    end

    // Debug prints
    always_ff @(posedge aclk) begin
        if (rd_pop_valid)
            $display("%t [RD_BUILDER_DBG] FIFO entry: tag=%0d addr=%h len=%0d",
                     $time, entry.tag, entry.addr, entry.len);

        if (arvalid && arready)
            $display("%t [RD_BUILDER_DBG] AR ISSUED: tag=%0d addr=%h len=%0d",
                     $time, arid, araddr, arlen);

        if (rvalid && rready)
            $display("%t [RD_BUILDER_DBG] RBEAT: ID=%0d last=%0b", 
                     $time, rid, rlast);
    end

endmodule