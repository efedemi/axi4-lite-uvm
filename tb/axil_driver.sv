// -----------------------------------------------------------------------------
// axil_driver : AXI4-Lite master. Turns each transaction into pin activity.
// -----------------------------------------------------------------------------
class axil_driver extends uvm_driver #(axil_seq_item);
  `uvm_component_utils(axil_driver)

  virtual axil_if vif;
  int unsigned    timeout_cycles = 1000;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual axil_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "virtual interface 'vif' not set in config_db")
  endfunction

  task run_phase(uvm_phase phase);
    idle_bus();
    wait (vif.rst_n === 1'b1);
    @(vif.drv_cb);
    forever begin
      seq_item_port.get_next_item(req);
      repeat (req.idle_cycles) @(vif.drv_cb);
      if (req.op == AXIL_WRITE) drive_write(req);
      else                      drive_read(req);
      `uvm_info("DRV", req.convert2string(), UVM_HIGH)
      seq_item_port.item_done();
    end
  endtask

  // All master outputs low.
  function void idle_bus();
    vif.awvalid <= 0; vif.wvalid <= 0; vif.arvalid <= 0;
    vif.bready  <= 0; vif.rready <= 0;
    vif.awaddr  <= 0; vif.awprot <= 0; vif.wdata  <= 0; vif.wstrb <= 0;
    vif.araddr  <= 0; vif.arprot <= 0;
  endfunction

  // Fail loudly instead of hanging forever if the slave never answers.
  function void check_timeout(int unsigned n, string what);
    if (n > timeout_cycles)
      `uvm_fatal("TIMEOUT", $sformatf("%s not seen within %0d cycles", what, timeout_cycles))
  endfunction

  task drive_write(axil_seq_item t);
    int unsigned n;
    // AW and W are independent channels, so drive them in parallel.
    fork
      begin : aw_channel
        int unsigned k = 0;
        repeat (t.aw_delay) @(vif.drv_cb);
        vif.drv_cb.awaddr  <= t.addr;
        vif.drv_cb.awprot  <= 3'b000;
        vif.drv_cb.awvalid <= 1'b1;
        do begin @(vif.drv_cb); check_timeout(++k, "AWREADY"); end
        while (!vif.drv_cb.awready);
        vif.drv_cb.awvalid <= 1'b0;
      end
      begin : w_channel
        int unsigned k = 0;
        repeat (t.w_delay) @(vif.drv_cb);
        vif.drv_cb.wdata  <= t.data;
        vif.drv_cb.wstrb  <= t.strb;
        vif.drv_cb.wvalid <= 1'b1;
        do begin @(vif.drv_cb); check_timeout(++k, "WREADY"); end
        while (!vif.drv_cb.wready);
        vif.drv_cb.wvalid <= 1'b0;
      end
    join

    repeat (t.ready_delay) @(vif.drv_cb);
    vif.drv_cb.bready <= 1'b1;
    n = 0;
    do begin @(vif.drv_cb); check_timeout(++n, "BVALID"); end
    while (!vif.drv_cb.bvalid);
    t.resp = vif.drv_cb.bresp;
    vif.drv_cb.bready <= 1'b0;
  endtask

  task drive_read(axil_seq_item t);
    int unsigned n = 0;
    vif.drv_cb.araddr  <= t.addr;
    vif.drv_cb.arprot  <= 3'b000;
    vif.drv_cb.arvalid <= 1'b1;
    do begin @(vif.drv_cb); check_timeout(++n, "ARREADY"); end
    while (!vif.drv_cb.arready);
    vif.drv_cb.arvalid <= 1'b0;

    repeat (t.ready_delay) @(vif.drv_cb);
    vif.drv_cb.rready <= 1'b1;
    n = 0;
    do begin @(vif.drv_cb); check_timeout(++n, "RVALID"); end
    while (!vif.drv_cb.rvalid);
    t.rdata = vif.drv_cb.rdata;
    t.resp  = vif.drv_cb.rresp;
    vif.drv_cb.rready <= 1'b0;
  endtask
endclass
