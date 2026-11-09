// -----------------------------------------------------------------------------
// axil_monitor : passive observer. Watches all five channels every clock,
// rebuilds complete transactions and broadcasts them on an analysis port.
// It never drives anything, so it works the same with or without a driver.
// -----------------------------------------------------------------------------
class axil_monitor extends uvm_monitor;
  `uvm_component_utils(axil_monitor)

  virtual axil_if                     vif;
  uvm_analysis_port #(axil_seq_item)  ap;

  typedef struct {
    bit [7:0]    addr;
    int unsigned req_wait;
    int unsigned gap;
  } req_info_t;

  typedef struct {
    bit [31:0] data;
    bit [3:0]  strb;
  } wdata_info_t;

  req_info_t   aw_q[$];
  req_info_t   ar_q[$];
  wdata_info_t w_q[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual axil_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "virtual interface 'vif' not set in config_db")
  endfunction

  task run_phase(uvm_phase phase);
    longint      cycle = 0, last_resp_cycle = 0;
    int unsigned aw_wait = 0, ar_wait = 0, b_wait = 0, r_wait = 0;
    int unsigned aw_gap = 0, ar_gap = 0;
    bit          aw_pending = 0, ar_pending = 0;

    forever begin
      @(vif.mon_cb);
      if (vif.rst_n !== 1'b1) begin
        aw_q.delete(); ar_q.delete(); w_q.delete();
        aw_wait = 0; ar_wait = 0; b_wait = 0; r_wait = 0;
        aw_pending = 0; ar_pending = 0;
        cycle = 0; last_resp_cycle = 0;
        continue;
      end
      cycle++;

      // ---- AW ----
      if (vif.mon_cb.awvalid) begin
        if (!aw_pending) begin
          aw_gap = (cycle - last_resp_cycle - 1);
          aw_pending = 1;
        end
        if (vif.mon_cb.awready) begin
          req_info_t r;
          r.addr = vif.mon_cb.awaddr; r.req_wait = aw_wait; r.gap = aw_gap;
          aw_q.push_back(r);
          aw_wait = 0; aw_pending = 0;
        end else aw_wait++;
      end

      // ---- W ----
      if (vif.mon_cb.wvalid && vif.mon_cb.wready) begin
        wdata_info_t w;
        w.data = vif.mon_cb.wdata; w.strb = vif.mon_cb.wstrb;
        w_q.push_back(w);
      end

      // ---- AR ----
      if (vif.mon_cb.arvalid) begin
        if (!ar_pending) begin
          ar_gap = (cycle - last_resp_cycle - 1);
          ar_pending = 1;
        end
        if (vif.mon_cb.arready) begin
          req_info_t r;
          r.addr = vif.mon_cb.araddr; r.req_wait = ar_wait; r.gap = ar_gap;
          ar_q.push_back(r);
          ar_wait = 0; ar_pending = 0;
        end else ar_wait++;
      end

      // ---- B : a write is complete ----
      if (vif.mon_cb.bvalid) begin
        if (vif.mon_cb.bready) begin
          if (aw_q.size() == 0 || w_q.size() == 0)
            `uvm_error("MON", "write response seen with no matching AW/W transfer")
          else begin
            req_info_t     r = aw_q.pop_front();
            wdata_info_t   w = w_q.pop_front();
            axil_seq_item  t = axil_seq_item::type_id::create("wr_txn");
            t.op = AXIL_WRITE; t.addr = r.addr; t.data = w.data; t.strb = w.strb;
            t.resp = vif.mon_cb.bresp;
            t.req_wait = r.req_wait; t.resp_wait = b_wait; t.gap = r.gap;
            `uvm_info("MON", t.convert2string(), UVM_HIGH)
            ap.write(t);
          end
          b_wait = 0;
          last_resp_cycle = cycle;
        end else b_wait++;
      end

      // ---- R : a read is complete ----
      if (vif.mon_cb.rvalid) begin
        if (vif.mon_cb.rready) begin
          if (ar_q.size() == 0)
            `uvm_error("MON", "read data seen with no matching AR transfer")
          else begin
            req_info_t     r = ar_q.pop_front();
            axil_seq_item  t = axil_seq_item::type_id::create("rd_txn");
            t.op = AXIL_READ; t.addr = r.addr;
            t.rdata = vif.mon_cb.rdata; t.resp = vif.mon_cb.rresp;
            t.req_wait = r.req_wait; t.resp_wait = r_wait; t.gap = r.gap;
            `uvm_info("MON", t.convert2string(), UVM_HIGH)
            ap.write(t);
          end
          r_wait = 0;
          last_resp_cycle = cycle;
        end else r_wait++;
      end
    end
  endtask
endclass
