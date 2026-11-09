`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// axil_regfile : AXI4-Lite slave with a 16-register map
//
//   0x00 - 0x2C  REG0..REG11   read/write, byte-enabled by WSTRB    -> OKAY
//   0x30         ID            read-only  (0xA11E_0001)             -> OKAY on read, SLVERR on write
//   0x34         VERSION       read-only  (0x0001_0000)
//   0x38         WR_COUNT      read-only, counts successful (OKAY) writes
//   0x3C         MAGIC         read-only  (0xCAFE_F00D)
//   0x40 - 0xFF  reserved                                           -> DECERR, read data 0
//
// The slave accepts a write only when AWVALID and WVALID are both present (the
// AXI spec allows a slave to wait for both). One write and one read can be in
// flight at a time. With WAIT_STATES = 1, an 8-bit LFSR holds the READY signals
// low on some cycles, so the slave behaves like a peripheral with variable latency.
//
// Bug injection: compile with +define+BUG_<NAME> to plant a known bug. The
// regression script `sim/bugs.ps1` checks that the testbench catches each one.
// -----------------------------------------------------------------------------
module axil_regfile #(
  parameter int ADDR_W      = 8,
  parameter int DATA_W      = 32,
  parameter bit WAIT_STATES = 1'b1
) (
  input  logic                clk,
  input  logic                rst_n,
  // write address channel
  input  logic [ADDR_W-1:0]   s_awaddr,
  input  logic [2:0]          s_awprot,
  input  logic                s_awvalid,
  output logic                s_awready,
  // write data channel
  input  logic [DATA_W-1:0]   s_wdata,
  input  logic [DATA_W/8-1:0] s_wstrb,
  input  logic                s_wvalid,
  output logic                s_wready,
  // write response channel
  output logic [1:0]          s_bresp,
  output logic                s_bvalid,
  input  logic                s_bready,
  // read address channel
  input  logic [ADDR_W-1:0]   s_araddr,
  input  logic [2:0]          s_arprot,
  input  logic                s_arvalid,
  output logic                s_arready,
  // read data channel
  output logic [DATA_W-1:0]   s_rdata,
  output logic [1:0]          s_rresp,
  output logic                s_rvalid,
  input  logic                s_rready
);

  localparam int          NUM_RW      = 12;
  localparam logic [1:0]  RESP_OKAY   = 2'b00;
  localparam logic [1:0]  RESP_SLVERR = 2'b10;
  localparam logic [1:0]  RESP_DECERR = 2'b11;
  localparam logic [31:0] ID_VALUE      = 32'hA11E_0001;
  localparam logic [31:0] VERSION_VALUE = 32'h0001_0000;
  localparam logic [31:0] MAGIC_VALUE   = 32'hCAFE_F00D;

  typedef enum logic [1:0] {RGN_RW, RGN_RO, RGN_RSV} region_t;

  function automatic region_t decode(input logic [ADDR_W-1:0] a);
    if (a < 'h30)      return RGN_RW;
    else if (a < 'h40) return RGN_RO;
    else               return RGN_RSV;
  endfunction

  logic [DATA_W-1:0] regs [NUM_RW];
  logic [DATA_W-1:0] wr_count;

  // ---------------------------------------------------------------------------
  // Wait-state generator
  // ---------------------------------------------------------------------------
  logic [7:0] lfsr;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) lfsr <= 8'hA5;
    else        lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
  end
  wire stall_w = WAIT_STATES && (lfsr[1:0] == 2'b00);
  wire stall_r = WAIT_STATES && (lfsr[3:2] == 2'b00);

  // ---------------------------------------------------------------------------
  // Write path
  // ---------------------------------------------------------------------------
  assign s_awready = s_awvalid && s_wvalid && !s_bvalid && !stall_w;
  assign s_wready  = s_awready;
  wire   wr_hs     = s_awvalid && s_awready;     // AW and W handshake together

  logic [3:0] widx;
`ifdef BUG_REG_ALIAS
  // BUG: writes to REG11 (0x2C) land in REG10
  assign widx = (s_awaddr[5:2] == 4'd11) ? 4'd10 : s_awaddr[5:2];
`else
  assign widx = s_awaddr[5:2];
`endif

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < NUM_RW; i++) regs[i] <= '0;
      wr_count <= '0;
      s_bvalid <= 1'b0;
      s_bresp  <= RESP_OKAY;
    end else begin
      if (s_bvalid && s_bready) s_bvalid <= 1'b0;

      if (wr_hs) begin
        s_bvalid <= 1'b1;
        case (decode(s_awaddr))
          RGN_RW: begin
            for (int b = 0; b < DATA_W/8; b++) begin
`ifdef BUG_WSTRB_IGNORED
              // BUG: byte enables ignored, whole word always written
              regs[widx][8*b +: 8] <= s_wdata[8*b +: 8];
`else
              if (s_wstrb[b]) regs[widx][8*b +: 8] <= s_wdata[8*b +: 8];
`endif
            end
            wr_count <= wr_count + 1;
            s_bresp  <= RESP_OKAY;
          end
          RGN_RO: begin
`ifdef BUG_RO_RESP
            s_bresp  <= RESP_OKAY;       // BUG: write to read-only register reports success
`else
            s_bresp  <= RESP_SLVERR;
`endif
`ifdef BUG_WRCOUNT_ON_ERR
            wr_count <= wr_count + 1;    // BUG: failed writes are counted
`endif
          end
          default: begin
            s_bresp  <= RESP_DECERR;
`ifdef BUG_WRCOUNT_ON_ERR
            wr_count <= wr_count + 1;
`endif
          end
        endcase
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Read path
  // ---------------------------------------------------------------------------
  assign s_arready = !s_rvalid && !stall_r;
  wire   rd_hs     = s_arvalid && s_arready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_rvalid <= 1'b0;
      s_rdata  <= '0;
      s_rresp  <= RESP_OKAY;
    end else begin
`ifdef BUG_RVALID_DROP
      if (s_rvalid) s_rvalid <= 1'b0;   // BUG: RVALID dropped after one cycle even without RREADY
`else
      if (s_rvalid && s_rready) s_rvalid <= 1'b0;
`endif
`ifdef BUG_RDATA_UNSTABLE
      if (s_rvalid && !s_rready) s_rdata <= s_rdata ^ 32'h1;  // BUG: data changes while waiting
`endif

      if (rd_hs) begin
        s_rvalid <= 1'b1;
        case (decode(s_araddr))
          RGN_RW: begin
            s_rdata <= regs[s_araddr[5:2]];
            s_rresp <= RESP_OKAY;
          end
          RGN_RO: begin
            case (s_araddr[3:2])
              2'd0: s_rdata <= ID_VALUE;
              2'd1: s_rdata <= VERSION_VALUE;
              2'd2: s_rdata <= wr_count;
              2'd3: s_rdata <= MAGIC_VALUE;
            endcase
            s_rresp <= RESP_OKAY;
          end
          default: begin
            s_rdata <= '0;
            s_rresp <= RESP_DECERR;
          end
        endcase
      end
    end
  end

endmodule
