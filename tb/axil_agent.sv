// -----------------------------------------------------------------------------
// axil_agent : bundles sequencer + driver + monitor for one AXI4-Lite port.
// Active mode builds all three; passive mode builds only the monitor
// (for watching a bus that something else drives).
// -----------------------------------------------------------------------------
class axil_agent extends uvm_agent;
  `uvm_component_utils(axil_agent)

  axil_sequencer                     sqr;
  axil_driver                        drv;
  axil_monitor                       mon;
  uvm_analysis_port #(axil_seq_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = axil_monitor::type_id::create("mon", this);
    if (get_is_active() == UVM_ACTIVE) begin
      sqr = axil_sequencer::type_id::create("sqr", this);
      drv = axil_driver::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    ap = mon.ap;
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass
