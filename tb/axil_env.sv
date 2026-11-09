// -----------------------------------------------------------------------------
// axil_env : the agent plus the checkers that listen to it.
//
//   agent.mon.ap ──► scoreboard.item_imp   (correctness)
//               └──► coverage.analysis_export (completeness)
// -----------------------------------------------------------------------------
class axil_env extends uvm_env;
  `uvm_component_utils(axil_env)

  axil_agent      agt;
  axil_scoreboard scb;
  axil_coverage   cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agt = axil_agent::type_id::create("agt", this);
    scb = axil_scoreboard::type_id::create("scb", this);
    cov = axil_coverage::type_id::create("cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    agt.ap.connect(scb.item_imp);
    agt.ap.connect(cov.analysis_export);
  endfunction
endclass
