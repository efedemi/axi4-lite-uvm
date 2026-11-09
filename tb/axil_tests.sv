// -----------------------------------------------------------------------------
// Tests: each test builds the same environment and picks which sequences run.
// Select one at run time with +UVM_TESTNAME=<test>.
// -----------------------------------------------------------------------------
class axil_base_test extends uvm_test;
  `uvm_component_utils(axil_base_test)

  axil_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = axil_env::type_id::create("env", this);
    uvm_top.set_timeout(10ms, 0);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    if (uvm_report_enabled(UVM_HIGH)) uvm_top.print_topology();
  endfunction

  // Subclasses put their stimulus here.
  virtual task run_stimulus();
  endtask

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    run_stimulus();
    #100ns;   // let the last response drain through the monitor
    phase.drop_objection(this);
  endtask

  function void report_phase(uvm_phase phase);
    uvm_report_server svr = uvm_report_server::get_server();
    int errs = svr.get_severity_count(UVM_ERROR) + svr.get_severity_count(UVM_FATAL);
    if (errs == 0) `uvm_info("RESULT", "** TEST PASSED **", UVM_NONE)
    else           `uvm_info("RESULT", $sformatf("** TEST FAILED ** (%0d errors)", errs), UVM_NONE)
  endfunction
endclass

// Stage 3 checkpoint: one directed write, read back.
class axil_smoke_test extends axil_base_test;
  `uvm_component_utils(axil_smoke_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_stimulus();
    axil_smoke_seq seq = axil_smoke_seq::type_id::create("seq");
    seq.start(env.agt.sqr);
  endtask
endclass

// All directed sequences.
class axil_directed_test extends axil_base_test;
  `uvm_component_utils(axil_directed_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_stimulus();
    axil_write_read_seq   s1 = axil_write_read_seq::type_id::create("s1");
    axil_error_seq        s2 = axil_error_seq::type_id::create("s2");
    axil_data_pattern_seq s3 = axil_data_pattern_seq::type_id::create("s3");
    axil_strobe_seq       s4 = axil_strobe_seq::type_id::create("s4");
    s1.start(env.agt.sqr);
    s2.start(env.agt.sqr);
    s3.start(env.agt.sqr);
    s4.start(env.agt.sqr);
  endtask
endclass

// Constrained-random only. Used to show which holes random stimulus leaves.
class axil_random_test extends axil_base_test;
  `uvm_component_utils(axil_random_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_stimulus();
    axil_random_seq seq = axil_random_seq::type_id::create("seq");
    seq.num_items = 2000;
    seq.start(env.agt.sqr);
  endtask
endclass

// Factory override demo: every axil_seq_item created through the factory
// becomes an axil_err_item, so the *unchanged* random sequence now hammers
// the error regions.
class axil_error_test extends axil_base_test;
  `uvm_component_utils(axil_error_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    axil_seq_item::type_id::set_type_override(axil_err_item::get_type());
    super.build_phase(phase);
  endfunction
  task run_stimulus();
    axil_random_seq seq = axil_random_seq::type_id::create("seq");
    seq.num_items = 1000;
    seq.start(env.agt.sqr);
  endtask
endclass

// Regression test: directed + random + timing-stress. This is the one that
// closes coverage.
class axil_full_test extends axil_base_test;
  `uvm_component_utils(axil_full_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_stimulus();
    axil_write_read_seq   s1 = axil_write_read_seq::type_id::create("s1");
    axil_error_seq        s2 = axil_error_seq::type_id::create("s2");
    axil_data_pattern_seq s3 = axil_data_pattern_seq::type_id::create("s3");
    axil_strobe_seq       s4 = axil_strobe_seq::type_id::create("s4");
    axil_back_to_back_seq s5 = axil_back_to_back_seq::type_id::create("s5");
    axil_slow_master_seq  s6 = axil_slow_master_seq::type_id::create("s6");
    axil_random_seq       s7 = axil_random_seq::type_id::create("s7");
    s7.num_items = 1500;
    s1.start(env.agt.sqr);
    s2.start(env.agt.sqr);
    s3.start(env.agt.sqr);
    s4.start(env.agt.sqr);
    s5.start(env.agt.sqr);
    s6.start(env.agt.sqr);
    s7.start(env.agt.sqr);
  endtask
endclass
