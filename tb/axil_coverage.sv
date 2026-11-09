// -----------------------------------------------------------------------------
// axil_coverage : functional coverage. Records *which* scenarios the tests
// actually produced, so we can see what is still untested (the "holes").
// -----------------------------------------------------------------------------
class axil_coverage extends uvm_subscriber #(axil_seq_item);
  `uvm_component_utils(axil_coverage)

  // Values sampled by the covergroup (set in write() before sample()).
  axil_op_e     op;
  axil_region_e region;
  bit [1:0]     resp;
  data_pat_e    wpat, rpat;
  strb_kind_e   strb_kind;
  int unsigned  req_wait, resp_wait, gap;

  covergroup axil_cg;
    option.per_instance = 1;

    cp_op: coverpoint op {
      bins read  = {AXIL_READ};
      bins write = {AXIL_WRITE};
    }

    cp_region: coverpoint region {
      bins rw  = {REGION_RW};
      bins ro  = {REGION_RO};
      bins rsv = {REGION_RSV};
    }

    cp_resp: coverpoint resp {
      bins okay   = {RESP_OKAY};
      bins slverr = {RESP_SLVERR};
      bins decerr = {RESP_DECERR};
      illegal_bins exokay = {RESP_EXOKAY};    // AXI4-Lite has no exclusive access
    }

    cp_wdata: coverpoint wpat iff (op == AXIL_WRITE) {
      bins zeros = {PAT_ZEROS};  bins ones  = {PAT_ONES};
      bins walk1 = {PAT_WALK1};  bins walk0 = {PAT_WALK0};
      bins alt   = {PAT_ALT};    bins other = {PAT_OTHER};
    }

    // Read-back patterns prove the data actually made the round trip.
    cp_rdata: coverpoint rpat iff (op == AXIL_READ && resp == RESP_OKAY) {
      bins zeros = {PAT_ZEROS};  bins ones  = {PAT_ONES};
      bins walk1 = {PAT_WALK1};  bins walk0 = {PAT_WALK0};
      bins alt   = {PAT_ALT};    bins other = {PAT_OTHER};
    }

    cp_strb: coverpoint strb_kind iff (op == AXIL_WRITE) {
      bins none    = {STRB_NONE};
      bins single  = {STRB_SINGLE};
      bins partial = {STRB_PARTIAL};
      bins full    = {STRB_FULL};
    }

    // Slave wait states: cycles VALID waited for READY on AW/AR.
    cp_req_wait: coverpoint req_wait {
      bins none = {0};
      bins one  = {1};
      bins few  = {[2:3]};
      bins many = {[4:$]};
    }

    // Master back-pressure: cycles BVALID/RVALID waited for BREADY/RREADY.
    cp_resp_wait: coverpoint resp_wait {
      bins none  = {0};
      bins short = {[1:2]};
      bins long  = {[3:$]};
    }

    // Back-to-back vs spaced transactions.
    cp_gap: coverpoint gap {
      bins back_to_back = {0};
      bins short        = {[1:3]};
      bins spaced       = {[4:$]};
    }

    // Every legal (operation, region, response) combination.
    // The other 12 combinations can't happen in a correct DUT, so they are
    // excluded rather than counted as holes.
    cx_op_region_resp: cross cp_op, cp_region, cp_resp {
      ignore_bins rw_slverr    = binsof(cp_region.rw)  && binsof(cp_resp.slverr);
      ignore_bins rw_decerr    = binsof(cp_region.rw)  && binsof(cp_resp.decerr);
      ignore_bins ro_decerr    = binsof(cp_region.ro)  && binsof(cp_resp.decerr);
      ignore_bins ro_rd_slverr = binsof(cp_region.ro)  && binsof(cp_op.read)  && binsof(cp_resp.slverr);
      ignore_bins ro_wr_okay   = binsof(cp_region.ro)  && binsof(cp_op.write) && binsof(cp_resp.okay);
      ignore_bins rsv_okay     = binsof(cp_region.rsv) && binsof(cp_resp.okay);
      ignore_bins rsv_slverr   = binsof(cp_region.rsv) && binsof(cp_resp.slverr);
    }

    cx_op_gap:  cross cp_op, cp_gap;
    cx_op_wait: cross cp_op, cp_req_wait;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    axil_cg = new();
  endfunction

  function void write(axil_seq_item t);
    op        = t.op;
    region    = addr_region(t.addr);
    resp      = t.resp;
    wpat      = classify_data(t.data);
    rpat      = classify_data(t.rdata);
    strb_kind = classify_strb(t.strb);
    req_wait  = t.req_wait;
    resp_wait = t.resp_wait;
    gap       = t.gap;
    axil_cg.sample();
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("COV", $sformatf({"\n  op %5.1f%%  region %5.1f%%  resp %5.1f%%",
                                "\n  wdata %5.1f%%  rdata %5.1f%%  strb %5.1f%%",
                                "\n  req_wait %5.1f%%  resp_wait %5.1f%%  gap %5.1f%%",
                                "\n  op x region x resp %5.1f%%  op x gap %5.1f%%  op x wait %5.1f%%",
                                "\n  TOTAL FUNCTIONAL COVERAGE %5.1f%%"},
      axil_cg.cp_op.get_inst_coverage(),   axil_cg.cp_region.get_inst_coverage(),
      axil_cg.cp_resp.get_inst_coverage(), axil_cg.cp_wdata.get_inst_coverage(),
      axil_cg.cp_rdata.get_inst_coverage(), axil_cg.cp_strb.get_inst_coverage(),
      axil_cg.cp_req_wait.get_inst_coverage(), axil_cg.cp_resp_wait.get_inst_coverage(),
      axil_cg.cp_gap.get_inst_coverage(), axil_cg.cx_op_region_resp.get_inst_coverage(),
      axil_cg.cx_op_gap.get_inst_coverage(), axil_cg.cx_op_wait.get_inst_coverage(),
      axil_cg.get_inst_coverage()), UVM_NONE)
  endfunction
endclass
