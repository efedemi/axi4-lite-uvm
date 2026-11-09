`timescale 1ns/1ps
package axil_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // ---------------------------------------------------------------------------
  // Shared types and helpers
  // ---------------------------------------------------------------------------
  typedef enum bit       {AXIL_READ, AXIL_WRITE}                         axil_op_e;
  typedef enum bit [1:0] {REGION_RW, REGION_RO, REGION_RSV}              axil_region_e;
  typedef enum bit [2:0] {PAT_ZEROS, PAT_ONES, PAT_WALK1, PAT_WALK0,
                          PAT_ALT, PAT_OTHER}                            data_pat_e;
  typedef enum bit [1:0] {STRB_NONE, STRB_SINGLE, STRB_PARTIAL, STRB_FULL} strb_kind_e;

  localparam bit [1:0] RESP_OKAY   = 2'b00;
  localparam bit [1:0] RESP_EXOKAY = 2'b01;
  localparam bit [1:0] RESP_SLVERR = 2'b10;
  localparam bit [1:0] RESP_DECERR = 2'b11;

  localparam bit [31:0] ID_VALUE      = 32'hA11E_0001;
  localparam bit [31:0] VERSION_VALUE = 32'h0001_0000;
  localparam bit [31:0] MAGIC_VALUE   = 32'hCAFE_F00D;

  function automatic axil_region_e addr_region(bit [7:0] a);
    if (a < 8'h30)      return REGION_RW;
    else if (a < 8'h40) return REGION_RO;
    else                return REGION_RSV;
  endfunction

  function automatic data_pat_e classify_data(bit [31:0] d);
    if (d == 32'h0)                                return PAT_ZEROS;
    if (d == 32'hFFFF_FFFF)                        return PAT_ONES;
    if ($onehot(d))                                return PAT_WALK1;
    if ($onehot(~d))                               return PAT_WALK0;
    if (d == 32'h5555_5555 || d == 32'hAAAA_AAAA) return PAT_ALT;
    return PAT_OTHER;
  endfunction

  function automatic strb_kind_e classify_strb(bit [3:0] s);
    if (s == 4'h0)  return STRB_NONE;
    if (s == 4'hF)  return STRB_FULL;
    if ($onehot(s)) return STRB_SINGLE;
    return STRB_PARTIAL;
  endfunction

  function automatic string resp_name(bit [1:0] r);
    case (r)
      RESP_OKAY:   return "OKAY";
      RESP_EXOKAY: return "EXOKAY";
      RESP_SLVERR: return "SLVERR";
      default:     return "DECERR";
    endcase
  endfunction

  // ---------------------------------------------------------------------------
  // Testbench classes
  // ---------------------------------------------------------------------------
  `include "axil_seq_item.sv"
  `include "axil_sequencer.sv"
  `include "axil_driver.sv"
  `include "axil_monitor.sv"
  `include "axil_agent.sv"
  `include "axil_scoreboard.sv"
  `include "axil_coverage.sv"
  `include "axil_env.sv"
  `include "axil_sequences.sv"
  `include "axil_tests.sv"

endpackage
