/*------------------------------------------------------------------------------
 * File          : apb2axi_pkg.sv
 * Project       : APB2AXI
 * Author        : Nir Miller & Ido Oreg
 * Creation date : Nov 2, 2025
 * Description   : A file that holds all the shared constants and types for the whole Apb2Axi Converter Project
 *------------------------------------------------------------------------------*/

package apb2axi_pkg;

     // --------------------------------------------------
     // General bus widths
     // --------------------------------------------------
     parameter int APB_ADDR_W = 16;     // width of APB paddr
     parameter int APB_DATA_W = 32;     // APB data width
     parameter int AXI_ADDR_W = 64;     // full AXI address width
     parameter int AXI_DATA_W = 64;     // AXI data bus width
     parameter int AXI_ID_W   = 4;      // AXI ID width

     parameter int AXI_LEN_W  = 4;      // AXI ID width

     // --------------------------------------------------
     // Gateway / Directory sizing
     // --------------------------------------------------
     parameter int TAG_NUM         = 16;        // number of outstanding transactions
     parameter int TAG_W           = (TAG_NUM <= 1) ? 1 : $clog2(TAG_NUM);
     parameter int N_TAG           = (1 << TAG_W);
     parameter int DIR_ENTRIES     = (1 << TAG_W);

     // --------------------------------------------------
     // Maximum Beats per burst in our arcitecture
     // --------------------------------------------------
     parameter int MAX_BEATS_NUM   = 16;
     parameter int FIFO_DEPTH      = 16;
     
     // --------------------------------------------------
     // APB register map (byte offsets)
     // --------------------------------------------------
     localparam logic [APB_ADDR_W-1:0] GATEWAY_ADDR_LO = 16'h00;
     localparam logic [APB_ADDR_W-1:0] GATEWAY_ADDR_HI = 16'h04;
     localparam logic [APB_ADDR_W-1:0] GATEWAY_CMD     = 16'h08;

     // --------------------------------------------------
     // Directory entry
     // --------------------------------------------------

     typedef enum logic [2:0] {
          DIR_ST_EMPTY,      // slot unused
          DIR_ST_STAGED,     // regs written but no commit yet (optional)
          DIR_ST_PENDING,    // committed, waiting to be issued
          DIR_ST_ISSUED,     // issued to AXI (or builder)
          DIR_ST_DONE,       // completed OK
          DIR_ST_ERROR       // completed with error
     } dir_state_e;

     typedef enum logic [1:0] {
          ST_EMPTY     = 2'd0,
          ST_ALLOCATED = 2'd1,    
          ST_PENDING   = 2'd2,
          ST_COMPLETE  = 2'd3
     } entry_state_e;

     typedef struct packed {
          logic                    is_write;
          logic [AXI_ADDR_W-1:0]   addr;
          logic [7:0]              len;
          logic [2:0]              size;
          logic [1:0]              burst;
          logic [TAG_W-1:0]        tag;
          logic [1:0]              resp;
          logic [7:0]              num_beats;
          dir_state_e              state;
     } directory_entry_t;
     parameter int REQ_WIDTH  = $bits(directory_entry_t);

     // --------------------------------------------------
     // Completion entry
     // --------------------------------------------------
     typedef struct packed {
          logic                    is_write; //1 = write completion (B) , 0 = read completion (R) 
          logic [TAG_W-1:0]        tag;
          logic [1:0]              resp;
          logic                    error;
          logic [7:0]              num_beats;
     } completion_entry_t;
     parameter int COMPLETION_W  = $bits(completion_entry_t);

     // --------------------------------------------------
     // Read Data FIFO entry
     // --------------------------------------------------
     typedef struct packed {
     logic [TAG_W-1:0] tag;
     logic [AXI_DATA_W-1:0] data;
     logic                  last;
     logic [1:0]            resp;
     } rdf_entry_t;
     parameter int RDF_W = $bits(rdf_entry_t);

endpackage