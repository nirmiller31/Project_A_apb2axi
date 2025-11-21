# ==========================================================
#  APB2AXI UVM Testbench Filelist
# ==========================================================

# === Global timescale ===
// $PROJECT_HOME/tb/global_timescale.svh    # attemt
-timescale=1ns/1ps

# === Include Directories ===
+incdir+$UVM_HOME
+incdir+$PROJECT_HOME/design
+incdir+$PROJECT_HOME/tb
+incdir+$PROJECT_HOME/tb/pkg
+incdir+$PROJECT_HOME/tb/if
+incdir+$PROJECT_HOME/tb/env
+incdir+$PROJECT_HOME/tb/agent
+incdir+$PROJECT_HOME/tb/seq
+incdir+$PROJECT_HOME/tb/seq_item
+incdir+$PROJECT_HOME/tb/tests

# ============================================================
# RTL / Design files
# ============================================================
$PROJECT_HOME/design/apb2axi_pkg.sv
$PROJECT_HOME/design/apb_if.sv
$PROJECT_HOME/design/axi_if.sv
$PROJECT_HOME/design/gateway/apb2axi_reg.sv
$PROJECT_HOME/design/gateway/apb2axi_directory.sv
$PROJECT_HOME/design/gateway/apb2axi_gateway.sv
$PROJECT_HOME/design/gateway/apb2axi_fifo.sv
$PROJECT_HOME/design/builder/apb2axi_read_builder.sv
$PROJECT_HOME/design/builder/apb2axi_write_builder.sv
$PROJECT_HOME/design/apb2axi.sv

# === Interfaces ===
// $PROJECT_HOME/tb/if/apb_if.sv      # bringup used
// $PROJECT_HOME/tb/if/axi_if.sv      # bringup used

# === Test-Bench Package ===
$PROJECT_HOME/tb/pkg/apb2axi_tb_pkg.sv

# === Bringup DUT ===         to be later commented
// $PROJECT_HOME/bringup_design/apb2axi.sv

# === Top ===
$PROJECT_HOME/tb/tb_top.sv


