`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_top : the only static (module) part of the testbench.
// Makes the clock and reset, instantiates the interface and the DUT, binds the
// assertions, publishes the virtual interface, and starts UVM.
// -----------------------------------------------------------------------------
module tb_top;
  import uvm_pkg::*;
  import axil_pkg::*;

  logic clk   = 1'b0;
  logic rst_n = 1'b0;

  always #5 clk = ~clk;                   // 100 MHz

  initial begin
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n <= 1'b1;
  end

  axil_if vif (.clk(clk), .rst_n(rst_n));

  axil_regfile dut (
    .clk       (clk),         .rst_n     (rst_n),
    .s_awaddr  (vif.awaddr),  .s_awprot  (vif.awprot), .s_awvalid (vif.awvalid), .s_awready (vif.awready),
    .s_wdata   (vif.wdata),   .s_wstrb   (vif.wstrb),  .s_wvalid  (vif.wvalid),  .s_wready  (vif.wready),
    .s_bresp   (vif.bresp),   .s_bvalid  (vif.bvalid), .s_bready  (vif.bready),
    .s_araddr  (vif.araddr),  .s_arprot  (vif.arprot), .s_arvalid (vif.arvalid), .s_arready (vif.arready),
    .s_rdata   (vif.rdata),   .s_rresp   (vif.rresp),  .s_rvalid  (vif.rvalid),  .s_rready  (vif.rready)
  );

  // Attach the protocol checker to every instance of the DUT without editing the RTL.
  bind axil_regfile axil_sva u_sva (.*);

  initial begin
    uvm_config_db #(virtual axil_if)::set(null, "uvm_test_top.env.agt.*", "vif", vif);
    run_test("axil_smoke_test");
  end

`ifdef DUMP_WAVES
  initial begin
    $dumpfile("waves.vcd");
    $dumpvars(0, tb_top);
  end
`endif
endmodule
