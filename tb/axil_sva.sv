`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// axil_sva : AXI4-Lite protocol assertions, bound onto the DUT in tb_top.
//
// Each assertion is checked on every clock edge for the whole simulation,
// independent of which test is running. Failures are reported as UVM errors
// so they fail the test like any scoreboard mismatch.
//
// XSim notes (Vivado 2025.2):
//   - 'default disable iff' is not supported, so each property names its own reset.
//   - property arguments must be typed, and $stable on a typed property argument
//     hangs elaboration, so the payload-stability checks are written inline.
//   - 'cover property' is not supported in simulation; the timing scenarios a
//     cover would prove are measured by the functional coverage model instead
//     (cp_req_wait, cp_resp_wait, cp_gap in axil_coverage.sv).
// -----------------------------------------------------------------------------
module axil_sva
  import uvm_pkg::*;
(
  input logic        clk,
  input logic        rst_n,
  input logic [7:0]  s_awaddr,  input logic [2:0] s_awprot, input logic s_awvalid, input logic s_awready,
  input logic [31:0] s_wdata,   input logic [3:0] s_wstrb,  input logic s_wvalid,  input logic s_wready,
  input logic [1:0]  s_bresp,                               input logic s_bvalid,  input logic s_bready,
  input logic [7:0]  s_araddr,  input logic [2:0] s_arprot, input logic s_arvalid, input logic s_arready,
  input logic [31:0] s_rdata,   input logic [1:0] s_rresp,  input logic s_rvalid,  input logic s_rready
);
  `include "uvm_macros.svh"

  // Rule 1: once VALID is high it must stay high until READY.
  property p_valid_held(logic valid, logic ready);
    @(posedge clk) disable iff (!rst_n)
      valid && !ready |=> valid;
  endproperty

  // Rule 2: while VALID waits for READY, the payload must not change.
  // Written inline per channel: XSim 2025.2 hangs elaborating $stable on a typed property argument.

  // ---- master -> slave channels (checks the testbench driver) ----
  a_aw_held:   assert property (p_valid_held(s_awvalid, s_awready))
                 else `uvm_error("SVA", "AWVALID dropped before AWREADY")
  a_aw_stable: assert property (@(posedge clk) disable iff (!rst_n)
                               s_awvalid && !s_awready |=> $stable({s_awaddr, s_awprot}))
                 else `uvm_error("SVA", "AWADDR/AWPROT changed while waiting for AWREADY")
  a_w_held:    assert property (p_valid_held(s_wvalid, s_wready))
                 else `uvm_error("SVA", "WVALID dropped before WREADY")
  a_w_stable:  assert property (@(posedge clk) disable iff (!rst_n)
                               s_wvalid && !s_wready |=> $stable({s_wdata, s_wstrb}))
                 else `uvm_error("SVA", "WDATA/WSTRB changed while waiting for WREADY")
  a_ar_held:   assert property (p_valid_held(s_arvalid, s_arready))
                 else `uvm_error("SVA", "ARVALID dropped before ARREADY")
  a_ar_stable: assert property (@(posedge clk) disable iff (!rst_n)
                               s_arvalid && !s_arready |=> $stable({s_araddr, s_arprot}))
                 else `uvm_error("SVA", "ARADDR/ARPROT changed while waiting for ARREADY")

  // ---- slave -> master channels (checks the DUT) ----
  a_b_held:    assert property (p_valid_held(s_bvalid, s_bready))
                 else `uvm_error("SVA", "BVALID dropped before BREADY")
  a_b_stable:  assert property (@(posedge clk) disable iff (!rst_n)
                               s_bvalid && !s_bready |=> $stable(s_bresp))
                 else `uvm_error("SVA", "BRESP changed while waiting for BREADY")
  a_r_held:    assert property (p_valid_held(s_rvalid, s_rready))
                 else `uvm_error("SVA", "RVALID dropped before RREADY")
  a_r_stable:  assert property (@(posedge clk) disable iff (!rst_n)
                               s_rvalid && !s_rready |=> $stable({s_rdata, s_rresp}))
                 else `uvm_error("SVA", "RDATA/RRESP changed while waiting for RREADY")

  // ---- no X on control signals out of reset ----
  a_no_x: assert property (@(posedge clk) disable iff (!rst_n)
                           !$isunknown({s_awvalid, s_awready, s_wvalid, s_wready, s_bvalid, s_bready,
                                        s_arvalid, s_arready, s_rvalid, s_rready}))
            else `uvm_error("SVA", "X/Z on an AXI valid/ready signal")

  // ---- response ordering: no response without a request ----
  // Count completed handshakes on each channel.
  int unsigned aw_cnt, w_cnt, b_cnt, ar_cnt, r_cnt;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_cnt <= 0; w_cnt <= 0; b_cnt <= 0; ar_cnt <= 0; r_cnt <= 0;
    end else begin
      if (s_awvalid && s_awready) aw_cnt <= aw_cnt + 1;
      if (s_wvalid  && s_wready)  w_cnt  <= w_cnt  + 1;
      if (s_bvalid  && s_bready)  b_cnt  <= b_cnt  + 1;
      if (s_arvalid && s_arready) ar_cnt <= ar_cnt + 1;
      if (s_rvalid  && s_rready)  r_cnt  <= r_cnt  + 1;
    end
  end

  // A write response may only appear after both the address and the data of
  // that write have been accepted.
  a_b_after_write: assert property (@(posedge clk) disable iff (!rst_n)
                                    s_bvalid |-> (aw_cnt > b_cnt) && (w_cnt > b_cnt))
                     else `uvm_error("SVA", "BVALID without a completed AW+W write")
  // Read data may only appear for an accepted read address.
  a_r_after_read:  assert property (@(posedge clk) disable iff (!rst_n)
                                    s_rvalid |-> (ar_cnt > r_cnt))
                     else `uvm_error("SVA", "RVALID without an accepted read address")

endmodule
