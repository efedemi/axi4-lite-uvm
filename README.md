# AXI4-Lite Slave — UVM Verification Environment

A layered UVM testbench in SystemVerilog that verifies an AXI4-Lite register-file slave:
constrained-random and directed stimulus, a scoreboard with a reference model, functional
coverage with cross coverage, and SystemVerilog Assertions for the AXI handshake rules.
Runs on the free Vivado Simulator (XSim 2025.2).

**Results (10 seeds × 4 tests):** 40/40 runs pass, 51,540 transactions checked against the
reference model, 0 mismatches, **100% merged functional coverage**, and **6/6 injected
bugs caught**.

---

## The design under test

`rtl/axil_regfile.sv`: an AXI4-Lite slave with a 16-register map.

| Address | Register | Access | Response |
|---|---|---|---|
| `0x00`–`0x2C` | REG0–REG11 | read/write, byte-enabled by `WSTRB` | OKAY |
| `0x30` | ID (`0xA11E_0001`) | read-only | OKAY on read, **SLVERR** on write |
| `0x34` | VERSION (`0x0001_0000`) | read-only | " |
| `0x38` | WR_COUNT, counts successful writes | read-only | " |
| `0x3C` | MAGIC (`0xCAFE_F00D`) | read-only | " |
| `0x40`–`0xFF` | reserved | — | **DECERR**, read data 0 |

- The slave accepts a write only when the address (AW) and data (W) are both valid. AXI
  allows a slave to wait for both, and the master must not depend on either order.
- An 8-bit LFSR pulls `AWREADY`/`WREADY`/`ARREADY` low on some cycles. That adds
  pseudo-random **slave wait states**, so the testbench has to handle variable latency.
- `+define+BUG_<NAME>` plants one of six known bugs (see [Bug injection](#bug-injection)).

## Testbench architecture

```
 ┌──────────────────────────── axil_*_test ───────────────────────────────┐
 │  picks sequences; factory overrides (axil_error_test)                  │
 │ ┌──────────────────────────── axil_env ──────────────────────────────┐ │
 │ │  ┌──────────────── axil_agent ────────────────┐                    │ │
 │ │  │ sequencer ──► driver ───────────┐          │   ┌────────────┐   │ │
 │ │  │   ▲ sequences                   │          │ ┌►│ scoreboard │   │ │
 │ │  │                    monitor ◄────┼──┐  ap ──┼─┤ │ + ref model│   │ │
 │ │  └─────────────────────────────────┼──┼───────┘ │ └────────────┘   │ │
 │ │                                    │  │         │ ┌────────────┐   │ │
 │ │                                    │  │         └►│  coverage  │   │ │
 │ │                                    │  │           └────────────┘   │ │
 │ └────────────────────────────────────┼──┼────────────────────────────┘ │
 └──────────────────────────────────────┼──┼──────────────────────────────┘
                     virtual interface  ▼  │  (axil_if, clocking blocks)
                                 ┌──────────────┐     ┌──────────┐
                                 │ axil_regfile │◄────│ axil_sva │  bound with `bind`
                                 │    (DUT)     │     │ (SVA)    │
                                 └──────────────┘     └──────────┘
```

| File | Role |
|---|---|
| `tb/axil_if.sv` | Interface with driver/monitor clocking blocks (inputs sampled `#1step` before the edge, outputs driven 1 ns after, so there are no races) |
| `tb/axil_seq_item.sv` | Transaction: op, addr, data, strobe, plus per-transaction timing (idle cycles, AW/W skew, ready delay). Observed fields: response, wait states, gap |
| `tb/axil_driver.sv` | AXI4-Lite master. Drives AW and W **in parallel** (`fork`/`join`) with independent delays, applies BREADY/RREADY back-pressure, has a watchdog |
| `tb/axil_monitor.sv` | Passive. Samples all five channels every clock, pairs AW+W+B and AR+R into transactions, measures wait states and gaps |
| `tb/axil_scoreboard.sv` | Reference model (associative-array mirror of the register map + WR_COUNT). Predicts response and read data, and errors if it checked nothing |
| `tb/axil_coverage.sv` | Covergroup: op, region, response, write and read data patterns, strobe kind, slave wait states, master back-pressure, back-to-back vs spaced, plus crosses |
| `tb/axil_sva.sv` | 13 concurrent assertions, bound to the DUT |
| `tb/axil_sequences.sv` | Smoke, write/read-back, error responses, data patterns, all 16 strobes, random, back-to-back, slow master |
| `tb/axil_tests.sv` | `smoke`, `directed`, `random`, `error` (factory override), `full` (regression) |

### Checks

**Scoreboard** checks every transaction: write responses against the expected
OKAY/SLVERR/DECERR, and read data and responses against the reference model.
`WSTRB` byte-merging and the WR_COUNT register are modelled too. The model is updated
from the *expected* behaviour, never from what the DUT returned.

**Assertions** (`tb/axil_sva.sv`), checked every cycle in every test:

| Rule | Channels |
|---|---|
| VALID must stay high until READY | AW, W, AR (master), B, R (slave) |
| Payload must stay stable while VALID waits for READY | AW, W, AR, B, R |
| No X/Z on any VALID/READY after reset | all |
| A write response only after both AW and W were accepted | B |
| Read data only for an accepted read address | R |

### Functional coverage

| Coverpoint | Bins |
|---|---|
| operation | read, write |
| address region | read/write registers, read-only registers, reserved |
| response | OKAY, SLVERR, DECERR (EXOKAY is illegal in AXI4-Lite) |
| write data / read-back data | all-zeros, all-ones, walking-1, walking-0, alternating, other |
| strobe | none, single byte, partial, full |
| slave wait states (VALID→READY) | 0, 1, 2–3, 4+ |
| master back-pressure (xVALID→xREADY) | 0, 1–2, 3+ |
| gap since previous response | back-to-back, 1–3, 4+ |
| **op × region × response** | the 6 legal combinations (12 impossible ones excluded with `ignore_bins`) |
| op × gap, op × wait states | all |

## Results

```
powershell -ExecutionPolicy Bypass -File sim\regress.ps1 -Seeds 10
```

| Test | What it runs | Coverage per run | Result (10 seeds) |
|---|---|---|---|
| `axil_full_test` | all directed sequences + back-to-back + slow master + 1500 random | **100%** | 10/10 pass, 1927 txns each |
| `axil_random_test` | 2000 constrained-random only | 93.1% | 10/10 pass |
| `axil_error_test` | 1000 random, error-heavy item via factory override | 91.7–93.1% | 10/10 pass |
| `axil_directed_test` | directed sequences only | 98.6–100% | 10/10 pass |
| **Merged (xcrg)** | | **100%** | **40/40 pass, 51,540 txns, 0 mismatches** |

### Coverage closure

Constrained-random stimulus alone stalls at **93.1%**. The holes are in the data-pattern
coverpoints: random 32-bit data essentially never produces walking-ones, walking-zeros or
`0x5555_5555`/`0xAAAA_AAAA`, and so those patterns are also never read back. Running
more random seeds doesn't help, because the probability is effectively zero.
`axil_data_pattern_seq` targets exactly those bins (68 directed write/read-back pairs) and
closes coverage to 100%. `axil_strobe_seq` makes sure all 16 `WSTRB` values are hit
instead of relying on chance.

## Bug injection

`sim/bugs.ps1` rebuilds the DUT once per planted bug and confirms the testbench fails:

```
powershell -ExecutionPolicy Bypass -File sim\bugs.ps1
```

| Bug (`+define+`) | What's wrong | Caught by |
|---|---|---|
| `BUG_WSTRB_IGNORED` | byte enables ignored, the whole word is always written | scoreboard: read-back mismatch |
| `BUG_REG_ALIAS` | writes to REG11 land in REG10 (address decode) | scoreboard: read-back mismatch |
| `BUG_RO_RESP` | write to a read-only register returns OKAY instead of SLVERR | scoreboard: wrong response |
| `BUG_WRCOUNT_ON_ERR` | failed writes also increment WR_COUNT | scoreboard: WR_COUNT mismatch |
| `BUG_RVALID_DROP` | RVALID drops after one cycle even if RREADY is low | assertion `a_r_held` |
| `BUG_RDATA_UNSTABLE` | RDATA changes while waiting for RREADY | scoreboard (data mismatch) and `a_r_stable` |

**6 / 6 caught.**

## How to run

Requires Vivado 2025.2 (XSim includes UVM 1.2). On Windows PowerShell:

```powershell
# one test
powershell -ExecutionPolicy Bypass -File sim\run.ps1 -Test axil_full_test -Seed 7

# with a planted bug
powershell -ExecutionPolicy Bypass -File sim\run.ps1 -Test axil_full_test -Define BUG_REG_ALIAS

# dump waves (VCD)
powershell -ExecutionPolicy Bypass -File sim\run.ps1 -Test axil_smoke_test -Waves

# regression and bug injection
powershell -ExecutionPolicy Bypass -File sim\regress.ps1 -Seeds 10
powershell -ExecutionPolicy Bypass -File sim\bugs.ps1
```

Build output goes to `%LOCALAPPDATA%\uvm_build\axi4_lite\`. Set `XILINX_BIN` if Vivado is
installed elsewhere.

## Simulator notes

XSim has several gaps that shaped this code. They're documented in
[`docs/simulator_choice.md`](docs/simulator_choice.md). The most important one: **XSim
ignores the weights of a `dist` constraint once the variable has any other constraint**.
The first version weighted addresses 70/15/15 with `dist`, but the scoreboard summary
showed about 70% error responses instead of about 25%. The fix was to choose the
category in `pre_randomize()` with `randcase` and constrain the value inside it.

## Possible next steps

- A reactive slave agent, so the same environment could verify an AXI4-Lite master
- A register model (`uvm_reg`) instead of the hand-written mirror
- Full AXI4: bursts, IDs, out-of-order responses
