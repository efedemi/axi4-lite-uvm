# Simulator choice

**Decision:** Vivado Simulator (XSim) 2025.2, already installed at `C:\AMDDesignTools\2025.2\Vivado`.
EDA Playground as a scratchpad for quick experiments.

## Options compared

| Option | Cost | UVM | Randomize / constraints | Covergroups | Concurrent SVA | Notes |
|---|---|---|---|---|---|---|
| **Vivado XSim** | Free, installed | UVM 1.2 bundled | Yes | Yes (`xcrg` for reports) | Yes | Slower than commercial tools; some advanced SV corners missing |
| Questa-Intel FPGA Starter Edition | Free, needs Intel account + node-locked license | Yes | Yes | Check before relying on it | Yes | Industry-standard tool, but the free edition is performance-limited |
| Verilator | Free, open source | Partial, still maturing | Partial | Limited | Partial | Very fast for RTL, but a poor fit for learning UVM today |
| EDA Playground | Free, browser | Yes (Questa, Riviera, others) | Yes | Yes | Yes | Great for snippets; not a local Git workflow |

## Why XSim

- Free and already installed with Vivado; no license setup.
- Supports everything Project 1 needs: UVM, constrained-random, functional coverage, SVA.

## Known gotcha

OneDrive locks XSim's temporary build files and elaboration fails with `Access is denied`.
Build output goes to `%LOCALAPPDATA%\uvm_build\` instead of the repo.

## The three XSim steps

1. `xvlog` — **compile**: parse each SystemVerilog file into a library (`-L uvm` links UVM)
2. `xelab` — **elaborate**: connect the module hierarchy from the top module into a runnable "snapshot"
3. `xsim` — **simulate**: run the snapshot

Questa uses the same three steps under different names: `vlog`, `vopt`, `vsim`.

## XSim limitations found while building this testbench

| Limitation | Effect | Workaround used |
|---|---|---|
| `dist` weights ignored when the variable has any other constraint, or on wide (32-bit) ranges | Weighted stimulus silently becomes uniform (measured 19% valid addresses instead of 70%) | Pick the category in `pre_randomize()` with `randcase`, constrain the value inside it (`axil_seq_item.sv`) |
| `default disable iff` unsupported | Elaboration error | `disable iff (!rst_n)` in every property |
| Untyped property arguments | Property silently ignored (warning only) | Typed arguments |
| `$stable()` on a typed property argument | `xelab` hangs | Payload-stability assertions written inline |
| `cover property` unsupported in simulation | Ignored | Timing scenarios measured by covergroups instead |
| `xsim.bat` splits `+UVM_TESTNAME=x` at `=` | Option parse error | Options passed with `-f <file>` |

The first one is the important lesson: a constraint that "looks right" can produce the wrong
distribution without any error. The scoreboard's summary exposed it (1330 of 1927 responses
were errors, when the weights called for about a quarter), and coverage confirmed it (random
data never hit all-zeros or all-ones). That is why stimulus needs to be measured, not assumed.
