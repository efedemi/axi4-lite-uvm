// -----------------------------------------------------------------------------
// axil_seq_item : one AXI4-Lite read or write transaction
//
// "rand" fields describe the stimulus (what to send and with what timing).
// The plain fields are filled in by the driver/monitor with what actually happened.
// -----------------------------------------------------------------------------
class axil_seq_item extends uvm_sequence_item;
  `uvm_object_utils(axil_seq_item)

  // ---- stimulus ----
  rand axil_op_e    op;
  rand bit [7:0]    addr;
  rand bit [31:0]   data;          // write data (ignored for reads)
  rand bit [3:0]    strb;          // write byte enables
  rand int unsigned idle_cycles;   // idle cycles before the transaction starts
  rand int unsigned aw_delay;      // write: cycles before AWVALID is raised
  rand int unsigned w_delay;       // write: cycles before WVALID is raised
  rand int unsigned ready_delay;   // cycles before BREADY / RREADY is raised

  // ---- observed ----
  bit [31:0]   rdata;
  bit [1:0]    resp;
  int unsigned req_wait;    // cycles AWVALID/ARVALID waited for READY (slave wait states)
  int unsigned resp_wait;   // cycles BVALID/RVALID waited for BREADY/RREADY
  int unsigned gap;         // idle cycles between the previous response and this request

  // ---- weighted choices for address region, data and strobe ----
  // The natural way to weight these is a `dist` constraint, e.g.
  //     addr dist { [8'h00:8'h2F] :/ 70, [8'h30:8'h3F] :/ 15, [8'h40:8'hFF] :/ 15 };
  // XSim 2025.2 honours a dist on its own, but ignores the weights as soon as the
  // variable has any other constraint (alignment, or an inline `with` from a sequence),
  // and on 32-bit ranges. The mix then silently becomes uniform (measured: ~19% valid
  // addresses instead of 70%, and all-zeros/all-ones data never generated).
  //
  // Workaround: pick the *category* first in pre_randomize() with randcase (the
  // weights are guaranteed), store it in a non-rand field, and let the solver pick a
  // value inside that category. Directed sequences that pin values turn this off.
  bit           use_weights = 1;
  int unsigned  w_rw = 70, w_ro = 15, w_rsv = 15;   // address region weights
  axil_region_e target_region;
  data_pat_e    target_data;
  strb_kind_e   target_strb;

  function void pre_randomize();
    if (!use_weights) return;
    randcase
      w_rw:  target_region = REGION_RW;
      w_ro:  target_region = REGION_RO;
      w_rsv: target_region = REGION_RSV;
    endcase
    randcase
      5:  target_data = PAT_ZEROS;
      5:  target_data = PAT_ONES;
      90: target_data = PAT_OTHER;     // anything else
    endcase
    randcase
      60: target_strb = STRB_FULL;
      15: target_strb = STRB_SINGLE;
      20: target_strb = STRB_PARTIAL;
      5:  target_strb = STRB_NONE;
    endcase
  endfunction

  constraint c_align  { addr[1:0] == 2'b00; }

  constraint c_region {
    (use_weights && target_region == REGION_RW)  -> (addr <  8'h30);
    (use_weights && target_region == REGION_RO)  -> (addr >= 8'h30 && addr < 8'h40);
    (use_weights && target_region == REGION_RSV) -> (addr >= 8'h40);
  }

  constraint c_data {
    (use_weights && target_data == PAT_ZEROS) -> (data == 32'h0);
    (use_weights && target_data == PAT_ONES)  -> (data == 32'hFFFF_FFFF);
    (use_weights && target_data == PAT_OTHER) -> (data != 32'h0 && data != 32'hFFFF_FFFF);
  }

  constraint c_strb {
    (use_weights && target_strb == STRB_FULL)    -> (strb == 4'hF);
    (use_weights && target_strb == STRB_NONE)    -> (strb == 4'h0);
    (use_weights && target_strb == STRB_SINGLE)  -> (strb inside {4'h1, 4'h2, 4'h4, 4'h8});
    (use_weights && target_strb == STRB_PARTIAL) -> (strb inside {4'h3, 4'h5, 4'h6, 4'h7, 4'h9,
                                                                  4'hA, 4'hB, 4'hC, 4'hD, 4'hE});
  }

  constraint c_timing {
    idle_cycles dist { 0 := 50, [1:3] :/ 35, [4:8] :/ 15 };
    aw_delay    dist { 0 := 70, [1:3] :/ 30 };
    w_delay     dist { 0 := 70, [1:3] :/ 30 };
    ready_delay dist { 0 := 60, [1:2] :/ 30, [3:5] :/ 10 };
  }

  function new(string name = "axil_seq_item");
    super.new(name);
  endfunction

  function string convert2string();
    if (op == AXIL_WRITE)
      return $sformatf("WRITE addr=0x%02h data=0x%08h strb=0x%h resp=%s",
                       addr, data, strb, resp_name(resp));
    return $sformatf("READ  addr=0x%02h rdata=0x%08h resp=%s",
                     addr, rdata, resp_name(resp));
  endfunction
endclass

// A variant used to show off factory overrides: same item, but error-heavy.
class axil_err_item extends axil_seq_item;
  `uvm_object_utils(axil_err_item)

  function new(string name = "axil_err_item");
    super.new(name);
    w_rw = 20; w_ro = 40; w_rsv = 40;
  endfunction
endclass
