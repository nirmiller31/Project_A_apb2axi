
`include "uvm_macros.svh"
import uvm_pkg::*;

class hello_test extends uvm_test;
     `uvm_component_utils(hello_test)
     
     function new(string name="hello test", uvm_component parent=null);
          super.new(name, parent);
     endfunction

     task run_phase(uvm_phase phase);
          `uvm_info("hello_uvm", "HELLO_TEST", UVM_NONE)
     endtask
endclass

module tb_top;
     initial run_test("hello_test");
endmodule