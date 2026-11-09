// -----------------------------------------------------------------------------
// axil_scoreboard : predicts what the DUT should have done and compares.
//
// The reference model is a mirror of the register map: an associative array
// indexed by register number, plus the WR_COUNT counter. Entries that were
// never written don't exist in the array and read back as the reset value 0.
// -----------------------------------------------------------------------------
class axil_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(axil_scoreboard)

  uvm_analysis_imp #(axil_seq_item, axil_scoreboard) item_imp;

  bit [31:0]   mirror [int];
  bit [31:0]   wr_count;
  int unsigned n_writes, n_reads, n_errors_expected, n_mismatch;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    item_imp = new("item_imp", this);
  endfunction

  // Called by the monitor's analysis port for every completed transaction.
  function void write(axil_seq_item t);
    if (t.op == AXIL_WRITE) check_write(t);
    else                    check_read(t);
  endfunction

  function bit [31:0] read_mirror(int idx);
    return mirror.exists(idx) ? mirror[idx] : 32'h0;
  endfunction

  function void check_write(axil_seq_item t);
    axil_region_e rgn = addr_region(t.addr);
    bit [1:0]     exp_resp;
    n_writes++;

    case (rgn)
      REGION_RW:  exp_resp = RESP_OKAY;
      REGION_RO:  exp_resp = RESP_SLVERR;
      default:    exp_resp = RESP_DECERR;
    endcase
    if (exp_resp != RESP_OKAY) n_errors_expected++;

    if (t.resp !== exp_resp)
      mismatch(t, $sformatf("expected resp %s", resp_name(exp_resp)));

    // Update the model from the *expected* behaviour, never from the DUT's answer.
    if (rgn == REGION_RW) begin
      int        idx = t.addr[5:2];
      bit [31:0] cur = read_mirror(idx);
      for (int b = 0; b < 4; b++)
        if (t.strb[b]) cur[8*b +: 8] = t.data[8*b +: 8];
      mirror[idx] = cur;
      wr_count++;
    end
  endfunction

  function void check_read(axil_seq_item t);
    axil_region_e rgn = addr_region(t.addr);
    bit [1:0]     exp_resp;
    bit [31:0]    exp_data;
    n_reads++;

    case (rgn)
      REGION_RW: begin
        exp_resp = RESP_OKAY;
        exp_data = read_mirror(t.addr[5:2]);
      end
      REGION_RO: begin
        exp_resp = RESP_OKAY;
        case (t.addr[3:2])
          2'd0: exp_data = ID_VALUE;
          2'd1: exp_data = VERSION_VALUE;
          2'd2: exp_data = wr_count;
          2'd3: exp_data = MAGIC_VALUE;
        endcase
      end
      default: begin
        exp_resp = RESP_DECERR;
        exp_data = 32'h0;
        n_errors_expected++;
      end
    endcase

    if (t.resp !== exp_resp)
      mismatch(t, $sformatf("expected resp %s", resp_name(exp_resp)));
    else if (t.rdata !== exp_data)
      mismatch(t, $sformatf("expected rdata 0x%08h", exp_data));
  endfunction

  function void mismatch(axil_seq_item t, string why);
    n_mismatch++;
    `uvm_error("SCB", $sformatf("MISMATCH %s -- %s", t.convert2string(), why))
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SCB", $sformatf("checked %0d writes, %0d reads (%0d expected error responses), %0d mismatches",
                               n_writes, n_reads, n_errors_expected, n_mismatch), UVM_NONE)
    // A scoreboard that checked nothing must not look like a pass.
    if (n_writes + n_reads == 0)
      `uvm_error("SCB", "no transactions were checked")
  endfunction
endclass
