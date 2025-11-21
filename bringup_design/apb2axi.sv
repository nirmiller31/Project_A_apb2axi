
module apb2axi (
  // APB Interface
  input  logic         PCLK,
  input  logic         PRESETn,
  input  logic [31:0]  PADDR,
  input  logic [31:0]  PWDATA,
  input  logic         PWRITE,
  input  logic         PSEL,
  input  logic         PENABLE,
  output logic [31:0]  PRDATA,
  output logic         PREADY,
  output logic         PSLVERR,

  // AXI Interface
  input  logic         ACLK,
  input  logic         ARESETn,
  output logic [31:0]  AWADDR,
  output logic         AWVALID,
  input  logic         AWREADY,
  output logic [31:0]  WDATA,
  output logic         WVALID,
  input  logic         WREADY,
  input  logic         BVALID,
  output logic         BREADY,
  input  logic [1:0]   BRESP,
  output logic [31:0]  ARADDR,
  output logic         ARVALID,
  input  logic         ARREADY,
  input  logic [31:0]  RDATA,
  input  logic         RVALID,
  output logic         RREADY,
  input  logic [1:0]   RRESP
);

  // ----------------------------------------------------
  // Dummy logic (placeholder)
  // ----------------------------------------------------
  initial begin
    PRDATA  = 32'hDEAD_BEEF;
    PREADY  = 1'b1;
    PSLVERR = 1'b0;
  end

  always_ff @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      AWADDR  <= 0;
      AWVALID <= 0;
      WDATA   <= 0;
      WVALID  <= 0;
      BREADY  <= 0;
      ARADDR  <= 0;
      ARVALID <= 0;
      RREADY  <= 0;
    end else begin
      // Idle placeholder — drives nothing meaningful yet
      AWADDR  <= PADDR;
      AWVALID <= PSEL & PENABLE & PWRITE;
      WDATA   <= PWDATA;
      WVALID  <= PSEL & PENABLE & PWRITE;
      BREADY  <= 1;
      ARADDR  <= PADDR;
      ARVALID <= PSEL & PENABLE & !PWRITE;
      RREADY  <= 1;
    end
  end

endmodule
