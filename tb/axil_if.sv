`timescale 1ns/1ps
// AXI4-Lite interface: the bundle of wires between the testbench and the DUT.
// The testbench reaches it through a *virtual interface* handle passed down with uvm_config_db.
interface axil_if (input logic clk, input logic rst_n);

  logic [7:0]  awaddr;  logic [2:0] awprot;  logic awvalid, awready;
  logic [31:0] wdata;   logic [3:0] wstrb;   logic wvalid,  wready;
  logic [1:0]  bresp;                        logic bvalid,  bready;
  logic [7:0]  araddr;  logic [2:0] arprot;  logic arvalid, arready;
  logic [31:0] rdata;   logic [1:0] rresp;   logic rvalid,  rready;

  // Driver view: inputs sampled just before the clock edge (#1step),
  // outputs driven 1ns after the edge, so the testbench never races the DUT.
  clocking drv_cb @(posedge clk);
    default input #1step output #1;
    output awaddr, awprot, awvalid, wdata, wstrb, wvalid, bready,
           araddr, arprot, arvalid, rready;
    input  awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid;
  endclocking

  // Monitor view: everything is an input.
  clocking mon_cb @(posedge clk);
    default input #1step;
    input awaddr, awprot, awvalid, awready, wdata, wstrb, wvalid, wready,
          bresp, bvalid, bready, araddr, arprot, arvalid, arready,
          rdata, rresp, rvalid, rready;
  endclocking

endinterface
