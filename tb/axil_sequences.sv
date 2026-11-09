// -----------------------------------------------------------------------------
// Sequences: each one is a reusable recipe of transactions.
// -----------------------------------------------------------------------------

// Base sequence with helpers for one write and one read.
class axil_base_seq extends uvm_sequence #(axil_seq_item);
  `uvm_object_utils(axil_base_seq)

  function new(string name = "axil_base_seq");
    super.new(name);
  endfunction

  task write_reg(bit [7:0] waddr, bit [31:0] wval, bit [3:0] wbe = 4'hF);
    axil_seq_item t = axil_seq_item::type_id::create("t");
    t.use_weights = 0;   // values are pinned, so skip the weighted choices
    start_item(t);
    if (!t.randomize() with { op == AXIL_WRITE; addr == waddr; data == wval; strb == wbe; })
      `uvm_fatal("RAND", "write randomize failed")
    finish_item(t);
  endtask

  task read_reg(bit [7:0] raddr, output bit [31:0] rval);
    axil_seq_item t = axil_seq_item::type_id::create("t");
    t.use_weights = 0;
    start_item(t);
    if (!t.randomize() with { op == AXIL_READ; addr == raddr; })
      `uvm_fatal("RAND", "read randomize failed")
    finish_item(t);
    rval = t.rdata;
  endtask
endclass

// One write, then read it back. (Stage 3 checkpoint.)
class axil_smoke_seq extends axil_base_seq;
  `uvm_object_utils(axil_smoke_seq)
  function new(string name = "axil_smoke_seq"); super.new(name); endfunction
  task body();
    bit [31:0] v;
    write_reg(8'h04, 32'hDEAD_BEEF);
    read_reg(8'h04, v);
  endtask
endclass

// Write every RW register with a random value and read it back; read every RO register.
class axil_write_read_seq extends axil_base_seq;
  `uvm_object_utils(axil_write_read_seq)
  function new(string name = "axil_write_read_seq"); super.new(name); endfunction
  task body();
    bit [31:0] v;
    for (int i = 0; i < 12; i++) begin
      write_reg(i*4, $urandom());
      read_reg(i*4, v);
    end
    for (int a = 8'h30; a <= 8'h3C; a += 4) read_reg(a, v);
  endtask
endclass

// Error responses: writes to read-only registers (SLVERR) and
// reads/writes to reserved space (DECERR), including both edges of each region.
class axil_error_seq extends axil_base_seq;
  `uvm_object_utils(axil_error_seq)
  function new(string name = "axil_error_seq"); super.new(name); endfunction
  task body();
    bit [31:0] v;
    bit [7:0]  edges[] = '{8'h2C, 8'h30, 8'h3C, 8'h40, 8'h44, 8'h80, 8'hFC};
    foreach (edges[i]) begin
      write_reg(edges[i], $urandom());
      read_reg(edges[i], v);
    end
    read_reg(8'h38, v);   // WR_COUNT must not have counted the failed writes
  endtask
endclass

// Data patterns that random data almost never produces: all-zeros, all-ones,
// walking ones, walking zeros, alternating bits. Written and read back.
class axil_data_pattern_seq extends axil_base_seq;
  `uvm_object_utils(axil_data_pattern_seq)
  function new(string name = "axil_data_pattern_seq"); super.new(name); endfunction
  task body();
    bit [31:0] v;
    bit [31:0] pats[$];
    pats.push_back(32'h0000_0000);
    pats.push_back(32'hFFFF_FFFF);
    pats.push_back(32'h5555_5555);
    pats.push_back(32'hAAAA_AAAA);
    for (int b = 0; b < 32; b++) begin
      pats.push_back(32'h1 << b);
      pats.push_back(~(32'h1 << b));
    end
    foreach (pats[i]) begin
      bit [7:0] a = (i % 12) * 4;
      write_reg(a, pats[i]);
      read_reg(a, v);
    end
  endtask
endclass

// Every WSTRB value 0x0..0xF on top of a known background, then read back.
class axil_strobe_seq extends axil_base_seq;
  `uvm_object_utils(axil_strobe_seq)
  function new(string name = "axil_strobe_seq"); super.new(name); endfunction
  task body();
    bit [31:0] v;
    for (int s = 0; s < 16; s++) begin
      bit [7:0] a = (s % 12) * 4;
      write_reg(a, 32'hA5A5_A5A5);
      write_reg(a, 32'h1234_5678, s[3:0]);
      read_reg(a, v);
    end
  endtask
endclass

// Fully constrained-random traffic.
class axil_random_seq extends axil_base_seq;
  `uvm_object_utils(axil_random_seq)
  int unsigned num_items = 500;
  function new(string name = "axil_random_seq"); super.new(name); endfunction
  task body();
    repeat (num_items) begin
      axil_seq_item t = axil_seq_item::type_id::create("t");
      start_item(t);
      if (!t.randomize()) `uvm_fatal("RAND", "randomize failed")
      finish_item(t);
    end
  endtask
endclass

// Random traffic with no idle cycles and no ready delays: transactions back to back.
class axil_back_to_back_seq extends axil_base_seq;
  `uvm_object_utils(axil_back_to_back_seq)
  int unsigned num_items = 100;
  function new(string name = "axil_back_to_back_seq"); super.new(name); endfunction
  task body();
    repeat (num_items) begin
      axil_seq_item t = axil_seq_item::type_id::create("t");
      start_item(t);
      if (!t.randomize() with { idle_cycles == 0; aw_delay == 0; w_delay == 0; ready_delay == 0; })
        `uvm_fatal("RAND", "randomize failed")
      finish_item(t);
    end
  endtask
endclass

// Random traffic with long gaps and long ready delays.
class axil_slow_master_seq extends axil_base_seq;
  `uvm_object_utils(axil_slow_master_seq)
  int unsigned num_items = 100;
  function new(string name = "axil_slow_master_seq"); super.new(name); endfunction
  task body();
    repeat (num_items) begin
      axil_seq_item t = axil_seq_item::type_id::create("t");
      start_item(t);
      if (!t.randomize() with { idle_cycles inside {[4:8]}; ready_delay inside {[3:5]}; })
        `uvm_fatal("RAND", "randomize failed")
      finish_item(t);
    end
  endtask
endclass
