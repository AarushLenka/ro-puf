# RO-PUF on FPGA: ML Modeling Attack, Hardware Defense, and RL Challenge Selection
### A complete, from-zero implementation guide
#### Written for someone with no prior FPGA or ML experience

---

## What You Will Have When You're Done

1. A working Ring Oscillator PUF (RO-PUF) running on real FPGA hardware, producing a hardware fingerprint unique to your board
2. A dataset of challenge-response pairs (CRPs) collected from that hardware
3. A machine learning attack that models a naive PUF and predicts its responses with high accuracy — proving the naive design is insecure
4. A hardened version of the same PUF (XOR-mixed outputs) that defeats that same attack
5. A reinforcement learning agent that automatically discovers which challenges give the most stable, highest-entropy responses, so you don't have to guess

No prior knowledge of Verilog, FPGAs, machine learning, or reinforcement learning is assumed. Every term is explained the first time it appears.

---

## Part 1 — Choosing Your Board

You listed four boards: **Kintex-7**, **Altera DE1**, **Altera DE2**, and **Zynq / PYNQ**. This section walks through what each one actually gives you for this specific project, then tells you which to use.

### What this project actually needs from a board

1. **FPGA fabric** to hold the ring oscillators — every FPGA has this.
2. **A way to send an 8-bit challenge in and read an 8-bit response out**, over and over, thousands of times, for CRP collection, the ML attack, and the RL agent.
3. **Ideally, Python running on or very near the FPGA**, because every later step in this guide (scikit-learn, PyTorch, matplotlib) is Python. If Python has to run on your laptop and talk to the board over a slow link, every experiment gets slower and flakier.

### Board-by-board

**Zynq / PYNQ boards (PYNQ-Z1, PYNQ-Z2, or a bare Zynq eval board like ZC702/ZC706) — recommended**

A Zynq chip is two things fused into one package: a Xilinx 7-series FPGA fabric, and a dual-core ARM Cortex-A9 processor, connected internally by a fast on-chip bus called AXI. That's the whole story of why this is the right board.

If your board specifically ships as a **PYNQ** board (PYNQ-Z1 or PYNQ-Z2), it comes with a microSD card image that boots embedded Linux and a pre-installed Python environment, reachable from a Jupyter notebook in your browser. A Python library called `pynq` lets you write to and read from the FPGA's GPIO registers directly — no serial cable, no separate host computer required. Your CRP collection script, your ML attack, and your RL agent can all live and run on the board itself.

If your board is a bare Zynq evaluation board without the PYNQ image (e.g. ZC702/ZC706), the silicon is identical, but you don't get the pre-built Linux/Python environment — you'd need to build a PetaLinux image yourself, which is a multi-day undertaking for a first-timer. **If you have a choice, get the PYNQ image running on it; if you only have a bare Zynq board and no PYNQ image available, budget significant extra setup time, or fall back to the "no Python on-chip" workflow described under Kintex-7 below.**

Toolchain: **Vivado**, free WebPACK edition, which fully supports the Zynq-7000 family with no license cost or design-size limit.

**Verdict: use this board if at all possible.** Everything in this guide is written assuming you're doing this.

---

**Kintex-7 (e.g. KC705)**

Good news you may not expect: current-generation Vivado WebPACK (the free edition) does support two specific Kintex-7 parts (XC7K70T and XC7K160T) at no cost — this was a licensing restriction in some older Vivado versions, but it isn't a blocker today. So the "free toolchain" problem from older guidance is not actually a problem on current Vivado.

What Kintex-7 boards genuinely lack is an ARM processor on the chip. There's only FPGA fabric. To run Python-side collection scripts, you have two options:

- **Option A: Microblaze.** Xilinx's soft-core processor, built out of FPGA logic instead of being a physical ARM core. You can run a lightweight Linux or bare-metal C on it, but it eats into the same FPGA fabric you want for ring oscillators, and setting it up is a non-trivial Vivado exercise on its own.
- **Option B: host computer over UART/USB.** Run your Python scripts on your laptop, and talk to the FPGA over a serial (UART) link, sending challenge bytes out and reading response bytes back. This is simpler to set up than Microblaze but is slower per-query (every challenge round-trips over a serial cable instead of an internal bus) and doubles your points of failure (driver issues, COM port permissions, baud rate mismatches).

**Verdict: usable, but adds real setup overhead with no PUF-specific benefit.** Use only if a Zynq/PYNQ board genuinely isn't available to you. If you do use it, use Option B (UART) — it's the more debuggable path for a beginner. Every Python script in this guide notes exactly what changes if you're on a UART link instead of PYNQ's AXI GPIO.

---

**Altera DE1 / DE2 (Cyclone II / Cyclone IV)**

These are Intel/Altera FPGAs, not Xilinx. That means a completely different toolchain — **Quartus Prime**, not Vivado. The Verilog itself in this guide is standard, synthesizable Verilog with no Xilinx-specific primitives, so it will compile in Quartus largely unchanged. However, every instruction about IP integration, pin-constraint syntax, and the AXI-based challenge/response interface in Part 5 of this guide is Vivado/Zynq-specific and does not carry over — you would need to redo that section using Quartus's Platform Designer (Qsys) and Avalon-MM interfaces instead of AXI, and use Quartus's `.qsf` pin-assignment syntax instead of `.xdc`.

Neither the DE1 nor DE2 has a processor core on-chip (Cyclone II/IV are pure FPGA fabric, not SoCs), so like Kintex-7 you're limited to a soft-core (Nios II, Altera's equivalent of Microblaze) or a UART link to a host PC.

**Verdict: workable, but you are on your own for Part 5** (block design / IP integration) — the RTL in Part 4, the ML attack in Part 7, the defense in Part 8, and the RL agent in Part 9 all apply unchanged, because they only care about getting a byte in and a byte out. If DE1/DE2 is genuinely your only board, use the UART approach and skip straight from Part 4 (Verilog) to writing your own Quartus pin constraints and a simple UART peripheral — the CRP-collection Python code in Part 6 works as-is once you replace `pynq`'s AXI GPIO calls with `pyserial` calls.

---

### Decision

**Use the Zynq/PYNQ board.** Everything from here on assumes PYNQ. If you only have Kintex-7 or DE1/DE2, every place that talks to hardware is clearly marked "PYNQ (AXI GPIO)" — swap that one function for a UART equivalent and the rest of the guide (RTL, ML attack, defense, RL) is unchanged.

---

## Part 2 — Setting Up Your Environment From Zero

Do this before writing any Verilog.

### 2.1 Install Vivado (free WebPACK edition)

1. Go to `https://www.xilinx.com/support/download.html`
2. Choose the latest **Vivado ML Edition**, download the "Self Extracting Web Installer"
3. Run it. When asked for edition, pick **WebPACK** (free, no license file needed)
4. When asked which device families to install, check **only Zynq-7000** (unchecking everything else saves ~30 GB and a lot of install time)
5. Installation takes roughly 1–2 hours and needs about 50 GB of free disk space

Verify: open a terminal and run `vivado -version`. You should see a version string, e.g. `Vivado v2024.1`.

### 2.2 Install Python and required packages on your computer

- **Windows:** download from `https://www.python.org/downloads/`, and during install check "Add Python to PATH"
- **Mac:** `brew install python3`
- **Linux:** `sudo apt install python3 python3-pip`

Verify with `python3 --version` (need 3.10 or newer).

Then install the packages this guide uses:

```bash
pip install numpy pandas scikit-learn matplotlib torch gymnasium bchlib
```

This covers the ML attack (scikit-learn), the RL agent (numpy, optionally torch for the DQN variant), and plotting (matplotlib).

### 2.3 Set up the PYNQ board

If your board's microSD card already has PYNQ on it (most PYNQ-Z1/Z2 boards ship this way), skip to step 5.

1. Go to `https://www.pynq.io/board.html`, find your board, download the PYNQ SD card image (`.img`, roughly 6–8 GB)
2. Download balenaEtcher (`https://etcher.balena.io/`) and use it to flash the image to a microSD card (16 GB or larger)
3. Insert the card, connect the board to your router by Ethernet, power it on
4. Wait about 2 minutes, then find its IP address (check your router's connected-devices list, or try the default `http://192.168.2.99`)
5. Open that address in a browser. You'll see a Jupyter notebook login. Default password is `xilinx`

Your board is ready once you can open a notebook and run `print("hello")`.

### 2.4 Project folder layout

Create this structure on your computer:

```
ro_puf_project/
├── verilog/          ← hardware design files (Part 4)
├── vivado_project/   ← Vivado creates this (Part 5)
├── python/
│   ├── data/         ← collected CRP CSVs
│   ├── models/       ← saved ML/RL models
│   └── plots/        ← output graphs
└── README.md
```

---

## Part 3 — Understanding the Hardware Before Writing It

### 3.1 What a ring oscillator is

Take an odd number of NOT gates (inverters) and wire them in a loop, output of the last feeding the input of the first. Because each gate flips whatever it receives, the signal can never settle into a stable 0 or 1 — it keeps flipping, forever, as fast as the gates can switch. That's a ring oscillator.

The speed of that flipping (its frequency) depends on the physical switching speed of each transistor in the chain — gate length, oxide thickness, how many dopant atoms happened to land in the channel during fabrication. These are microscopic, uncontrollable variations that differ from chip to chip even when every chip was manufactured from the exact same design file. Two "identical" ring oscillators on two different physical chips will run at measurably different frequencies. This is the entropy source the whole PUF depends on.

### 3.2 Turning frequency differences into bits

We can't read "frequency" directly and usefully compare it — instead we **race two oscillators against each other for a fixed number of clock cycles** and see which one produced more oscillations (counted more edges) in that time. Whichever one is faster wins, and "A won" vs "B won" becomes one response bit. This comparison is:

- **Deterministic per chip** — the same chip, asked the same question, gives the same answer (barring noise, which we handle with error tolerance later)
- **Random across chips** — the winner on your board has no relationship to the winner on someone else's board
- **Unclonable** — not even the original manufacturer can predict or reproduce the exact frequency variation

### 3.3 The circuit, top to bottom

```
8-bit Challenge (C)
        │
        ├── C[3:0] ──→ 16:1 select ──→ one of 16 oscillators in Group 0 ──→ Counter A
        │
        └── C[7:4] ──→ 16:1 select ──→ one of 16 oscillators in Group 1 ──→ Counter B

After 48 clock cycles:  Response bit R = 1 if Counter A > Counter B, else 0

8 of these "cells" run in parallel, each with its own 32 oscillators →
one 8-bit challenge produces one 8-bit response
```

Changing the challenge selects a different pair of oscillators to race, which produces a different response bit. With an 8-bit challenge you get 256 distinct challenge-response pairs (CRPs) out of a single PUF instance.

---

## Part 4 — Writing the Verilog

Create each file below exactly as shown, inside `verilog/`.

### 4.1 `clock_div_2.v` — frequency divider

Ring oscillators on an FPGA can run at hundreds of MHz — too fast for a plain counter to sample reliably. Dividing by 2 brings this into a safely countable range while keeping the *relative* frequency difference between oscillators intact, which is all that actually matters.

```verilog
`timescale 1ns / 1ps

module clock_div_2 (
    input  clk,
    input  rst,
    output reg q
);
    // Flips the output on every rising edge — exactly divides frequency by 2.
    always @(posedge clk or posedge rst) begin
        if (rst)
            q <= 0;
        else
            q <= ~q;
    end
endmodule
```

### 4.2 `ring_osc.v` — a single ring oscillator

Vivado will flag the feedback loop here as a "combinational loop" during synthesis. That warning is expected — it's telling you it found exactly the circuit you intended to build. We tell Vivado to leave it alone with a constraint in Part 5.

```verilog
`timescale 1ns / 1ps

// A single ring oscillator with an enable input.
// en=1: the 7-stage inverter chain oscillates freely.
// en=0: the leading NAND gate holds the loop at logic 1, stopping oscillation.

module ring_osc #(
    parameter INSTANCE_ID = 0  // forces synthesis to keep every instance distinct
)(
    input  en,
    input  rst,
    output op
);
    (* KEEP = "TRUE" *) wire w1, w2, w3, w4, w5, w6, w7, wop;

    // KEEP="TRUE" stops Vivado from merging oscillators that look identical
    // on paper — if it did that, we'd lose the per-chip physical variation
    // this whole project depends on.
    assign w1  = ~(en & w7);
    assign w2  = ~w1;
    assign w3  = ~w2;
    assign w4  = ~w3;
    assign w5  = ~w4;
    assign w6  = ~w5;
    assign w7  = ~w6;
    assign wop = ~w7;

    clock_div_2 div (.clk(wop), .rst(rst), .q(op));

endmodule
```

### 4.3 `puf_cell.v` — one PUF cell (one response bit)

Each cell holds 32 ring oscillators (16 per group), two 16:1 selectors, two counters, and a comparator.

```verilog
`timescale 1ns / 1ps

module puf_cell #(
    parameter CELL_ID = 0   // 0–7, gives every oscillator across all cells a unique ID
)(
    input        clk,
    input        rstc,       // resets the counters
    input        rst_dff,    // resets the output latch
    input  [3:0] sel0,       // which oscillator in group 0 (from C[3:0])
    input  [3:0] sel1,       // which oscillator in group 1 (from C[7:4])
    input        out_trig,   // pulse to latch the comparison result
    output reg   R           // one response bit
);

    // ----- Group 0: 16 ring oscillators, one enabled at a time -----
    wire [15:0] osc0_out;
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : g0
            ring_osc #(.INSTANCE_ID(CELL_ID*32 + i)) ro (
                .en(sel0 == i[3:0]), .rst(rstc), .op(osc0_out[i])
            );
        end
    endgenerate

    // ----- Group 1: 16 ring oscillators -----
    wire [15:0] osc1_out;
    generate
        for (i = 0; i < 16; i = i + 1) begin : g1
            ring_osc #(.INSTANCE_ID(CELL_ID*32 + 16 + i)) ro (
                .en(sel1 == i[3:0]), .rst(rstc), .op(osc1_out[i])
            );
        end
    endgenerate

    // OR-reduce: since only one oscillator per group is enabled at a time,
    // this passes through exactly that oscillator's output.
    wire clk0 = |osc0_out;
    wire clk1 = |osc1_out;

    reg [7:0] cnt0, cnt1;

    always @(posedge clk0 or posedge rstc)
        if (rstc) cnt0 <= 8'd0;
        else if (cnt0 < 8'd255) cnt0 <= cnt0 + 8'd1;

    always @(posedge clk1 or posedge rstc)
        if (rstc) cnt1 <= 8'd0;
        else if (cnt1 < 8'd255) cnt1 <= cnt1 + 8'd1;

    // Latch the comparison result when the driver pulses out_trig.
    always @(posedge clk or posedge rst_dff) begin
        if (rst_dff)
            R <= 1'b0;
        else if (out_trig)
            R <= (cnt0 > cnt1) ? 1'b1 : 1'b0;
    end

endmodule
```

### 4.4 `puf_array.v` — 8 cells in parallel (naive, undefended version)

```verilog
`timescale 1ns / 1ps

// Eight PUF cells share the same challenge and run simultaneously,
// producing an 8-bit response. Each cell owns its own 32 oscillators,
// so the 8 response bits are statistically independent measurements.

module puf_array (
    input        clk,
    input        rstc,
    input        rst_dff,
    input  [7:0] C,
    input        out_trig,
    output [7:0] R
);
    wire [3:0] sel0 = C[3:0];
    wire [3:0] sel1 = C[7:4];

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : cells
            puf_cell #(.CELL_ID(i)) cell (
                .clk(clk), .rstc(rstc), .rst_dff(rst_dff),
                .sel0(sel0), .sel1(sel1),
                .out_trig(out_trig), .R(R[i])
            );
        end
    endgenerate

endmodule
```

### 4.5 `puf_driver.v` — timing controller

Generates the precise measurement window every response depends on.

```verilog
`timescale 1ns / 1ps

// One measurement cycle, timed from a start pulse:
//   t=0     : rstc=1, rst_dff=1  — reset all counters and the output latch
//   t=1..48 : counters free-run, counting oscillator edges
//   t=48    : out_trig=1        — latch whichever counter is ahead
//   t=49    : idle, ready for the next start pulse

module puf_driver (
    input  clk,
    input  reset_n,     // active-low reset
    input  start,       // pulse high for 1 cycle to begin a measurement
    output rstc,
    output rst_dff,
    output out_trig
);
    reg [5:0] cnt;
    reg       running;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cnt     <= 6'd0;
            running <= 1'b0;
        end else if (start && !running) begin
            cnt     <= 6'd0;
            running <= 1'b1;
        end else if (running) begin
            if (cnt == 6'd49) begin
                cnt     <= 6'd0;
                running <= 1'b0;
            end else begin
                cnt <= cnt + 6'd1;
            end
        end
    end

    assign rstc     = running && (cnt == 6'd0);
    assign rst_dff  = running && (cnt == 6'd0);
    assign out_trig = running && (cnt == 6'd48);

endmodule
```

**Why 48 cycles?** Long enough that the two counters' difference is statistically meaningful (a 1–2 cycle head start would be noise; by cycle 48 a genuinely faster oscillator has pulled measurably ahead), short enough that a full sweep of 256 challenges still finishes in well under a second.

### 4.6 `puf_top.v` — top module (connects to PYNQ's AXI GPIO)

```verilog
`timescale 1ns / 1ps

module puf_top (
    input        clk,
    input        reset_n,
    input  [7:0] challenge,   // written by Python via AXI GPIO
    input        start,       // pulsed by Python to trigger one measurement
    output [7:0] response,    // read by Python via AXI GPIO
    output       done         // Python polls this to know the result is ready
);
    wire rstc, rst_dff, out_trig;

    puf_driver driver (
        .clk(clk), .reset_n(reset_n), .start(start),
        .rstc(rstc), .rst_dff(rst_dff), .out_trig(out_trig)
    );

    puf_array array (
        .clk(clk), .rstc(rstc), .rst_dff(rst_dff),
        .C(challenge), .out_trig(out_trig), .R(response)
    );

    reg done_r;
    always @(posedge clk) done_r <= out_trig;
    assign done = done_r;

endmodule
```

---

## Part 5 — Creating the Vivado Project (PYNQ / Zynq path)

*(If you're on Kintex-7 or DE1/DE2 with a UART link instead, skip to Part 6 and connect `puf_top.v`'s `challenge`/`start`/`response`/`done` ports to a simple UART peripheral instead of AXI GPIO — the RTL above doesn't change either way.)*

### 5.1 Create the project

1. Open Vivado → **Create Project**
2. Next → name it `ro_puf`, choose your `vivado_project/` folder → Next
3. Select **RTL Project**, leave "Do not specify sources at this time" **unchecked** → Next
4. **Add Files** → select all six `.v` files from `verilog/` → Next
5. Under **Default Part**, search `xc7z020clg400-1` (the Zynq chip on PYNQ-Z2 — if you're on PYNQ-Z1 or another Zynq board, search your board's exact part number instead) → select it → Next
6. Finish

### 5.2 Add the combinational-loop constraint

1. Left panel → **Add Sources** → "Add or create constraints" → Next
2. **Create File** → name it `puf_constraints.xdc` → OK → Finish
3. Double-click it in the Sources panel, paste:

```tcl
# The ring oscillator feedback loops are intentional — tell Vivado not to
# optimize them away or treat them as a design error.
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical -filter {NAME =~ *w1*}]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical -filter {NAME =~ *w2*}]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical -filter {NAME =~ *w3*}]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical -filter {NAME =~ *w4*}]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical -filter {NAME =~ *w5*}]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical -filter {NAME =~ *w6*}]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical -filter {NAME =~ *w7*}]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical -filter {NAME =~ *wop*}]

# PYNQ-Z2 system clock is 125 MHz = 8 ns period.
create_clock -period 8.000 -name sys_clk_pin -waveform {0.000 4.000} [get_ports clk]
```

4. Save (Ctrl+S)

### 5.3 Build the block design

This wires your `puf_top` module to the Zynq processing system so Python can read and write it.

1. Left panel → **IP Integrator** → **Create Block Design** → name it `puf_bd` → OK
2. Right-click the canvas → **Add IP** → search `Zynq` → double-click **ZYNQ7 Processing System**
3. Click **Run Block Automation** (blue banner) → accept defaults → OK
4. Right-click canvas → **Add IP** → search `AXI GPIO` → add two instances
5. Double-click the first AXI GPIO:
   - GPIO Width: **9** (8 challenge bits + 1 start bit)
   - Direction: **All Outputs**
6. Double-click the second AXI GPIO:
   - GPIO Width: **9** (8 response bits + 1 done bit)
   - Direction: **All Inputs**
7. Click **Run Connection Automation** → check all boxes → OK (auto-wires the AXI buses to the Zynq PS)
8. Right-click canvas → **Add Module** → select `puf_top`
9. Manually wire (click a port, drag to the other):
   - `axi_gpio_0/gpio_io_o[7:0]` → `puf_top/challenge`
   - `axi_gpio_0/gpio_io_o[8]` → `puf_top/start`
   - `puf_top/response` → `axi_gpio_1/gpio_io_i[7:0]`
   - `puf_top/done` → `axi_gpio_1/gpio_io_i[8]`
   - Right-click `puf_top/clk` → **Make External**, name it `clk`
   - Right-click `puf_top/reset_n` → **Make External**, name it `reset_n`
10. Save (Ctrl+S)

### 5.4 Generate the bitstream

1. Sources panel → right-click `puf_bd` → **Generate HDL Wrapper** → OK
2. Left panel → **Generate Bitstream** (under Program and Debug)
3. Wait 5–20 minutes while it synthesizes and implements
4. When done, click OK (or "Open Implemented Design" if you want to look around)

The bitstream lands at:
`vivado_project/ro_puf/ro_puf.runs/impl_1/puf_bd_wrapper.bit`

The matching hardware handoff file is at:
`vivado_project/ro_puf/ro_puf.gen/sources_1/bd/puf_bd/hw_handoff/puf_bd.hwh`

Upload **both files** to the PYNQ board using the Jupyter file browser's upload button.

---

## Part 6 — Collecting Challenge-Response Pairs

Run this **on the PYNQ board**, inside a Jupyter notebook, in the same folder where you uploaded the `.bit` and `.hwh` files.

### `01_collect_crps.py`

```python
# Sweeps all 256 challenges against the PUF, using majority voting to filter
# out measurement noise, and saves the results to a CSV.

from pynq import Overlay
import time
import csv
import os

# ── Load the bitstream ────────────────────────────────────────────────────
overlay = Overlay("puf_bd_wrapper.bit")

gpio_out = overlay.axi_gpio_0.channel1   # 9-bit: challenge[7:0] + start[8]
gpio_in  = overlay.axi_gpio_1.channel1   # 9-bit: response[7:0] + done[8]

NUM_TRIALS  = 7       # odd number → majority vote always has a definite winner
WINDOW_WAIT = 0.001    # 1 ms is far more than the ~0.4 microsecond measurement takes

def query_puf(challenge: int) -> int:
    """Send one challenge, wait for the done flag, return the 8-bit response."""
    gpio_out.write(challenge | (1 << 8), 0x1FF)   # set challenge bits + start bit
    time.sleep(WINDOW_WAIT)

    for _ in range(100):                            # poll for done, with a timeout
        if gpio_in.read() & (1 << 8):
            break
        time.sleep(0.0001)

    gpio_out.write(challenge, 0x1FF)                # clear the start bit
    return gpio_in.read() & 0xFF

def majority_vote(responses: list) -> tuple:
    """
    For each of the 8 bit positions, take whichever value (0 or 1) appeared
    in more than half the trials. Returns (stable_response, stability_score),
    where stability_score is the fraction of trials that exactly matched the
    stable response — a rough measure of how noisy this particular CRP is.
    """
    stable = 0
    for bit in range(8):
        ones = sum(1 for r in responses if (r >> bit) & 1)
        if ones > NUM_TRIALS // 2:
            stable |= (1 << bit)
    stability = sum(1 for r in responses if r == stable) / NUM_TRIALS
    return stable, stability

print("Collecting CRPs...")
crp_data = []

for challenge in range(256):
    raw = [query_puf(challenge) for _ in range(NUM_TRIALS)]
    stable, stability = majority_vote(raw)
    crp_data.append({
        'challenge':  challenge,
        'response':   stable,
        'stability':  round(stability, 3),
        'raw_trials': str(raw)
    })
    if challenge % 32 == 0:
        print(f"  {challenge}/256")

os.makedirs('data', exist_ok=True)
with open('data/crp_dataset.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['challenge', 'response', 'stability', 'raw_trials'])
    writer.writeheader()
    writer.writerows(crp_data)

print(f"Saved {len(crp_data)} CRPs to data/crp_dataset.csv")

# ── Sanity check ─────────────────────────────────────────────────────────
stable_count  = sum(1 for c in crp_data if c['stability'] >= 6/7)
avg_stability = sum(c['stability'] for c in crp_data) / len(crp_data)
avg_ones      = sum(bin(c['response']).count('1') for c in crp_data) / len(crp_data)

print(f"\nStable CRPs (>= 6/7 trials matching): {stable_count}/256")
print(f"Average stability: {avg_stability:.3f}")
print(f"Average ones per response byte: {avg_ones:.2f} (ideal is 4.0)")
print("If stable CRPs < 200, or avg ones is far from 4.0, see Part 12 (Troubleshooting).")
```

Download the resulting `data/crp_dataset.csv` from the PYNQ Jupyter file browser to your computer, into `python/data/`.

*(Kintex-7 / DE1/DE2 UART variant: replace `query_puf()`'s body with `ser.write(bytes([challenge])); time.sleep(...); return ser.read(1)[0]` using `pyserial`. Everything else in this script is identical.)*

---

## Part 7 — The ML Modeling Attack

### 7.1 What this attack demonstrates

An attacker who gets hold of enough challenge-response pairs — say, by eavesdropping on authentication traffic, or by briefly having physical access to a device — can train a classifier to predict responses to challenges it has never actually seen queried. If that classifier is accurate enough, the attacker can impersonate the device in software, with no physical chip required.

This works against a naive RO-PUF because the relationship between "which oscillators were selected" and "which one wins" is close to linear: once a model has seen enough (oscillator pair, winner) examples, it can learn each oscillator's relative speed and predict any future pairing.

### 7.2 Why logistic regression is enough to break it

Logistic regression is about the simplest classifier that exists — it draws a linear decision boundary between two classes. For a naive RO-PUF, that's already sufficient: with challenge bits as input features, the underlying comparison is close enough to linear that logistic regression typically reaches 85–95% per-bit accuracy with only 100–200 CRPs. This is what makes naive RO-PUFs a well-known weak point in PUF literature, and exactly why we build a defense in Part 8.

### `02_ml_attack.py` — run on your computer

```python
# Trains one logistic regression model per response bit and measures how
# accurately it predicts responses it never trained on.

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score
import matplotlib.pyplot as plt
import os

os.makedirs('models', exist_ok=True)
os.makedirs('plots',  exist_ok=True)

# ── Load data ────────────────────────────────────────────────────────────
df = pd.read_csv('data/crp_dataset.csv')
print(f"Loaded {len(df)} CRPs.")

def int_to_bits(value: int, n_bits: int = 8) -> list:
    """8-bit integer -> list of 8 individual bits (MSB first)."""
    return [(value >> (n_bits - 1 - i)) & 1 for i in range(n_bits)]

# X: one row per challenge, 8 columns (the bit-expanded challenge)
X = np.array([int_to_bits(c) for c in df['challenge']])
# y: one row per challenge, 8 columns (the 8 response bits)
y = np.array([[(r >> bit) & 1 for bit in range(8)] for r in df['response']])

print(f"Feature matrix: {X.shape}, label matrix: {y.shape}")

# ── Attack at increasing training-set sizes ─────────────────────────────
training_sizes = [20, 40, 80, 120, 160, 200]
results = []

for n_train in training_sizes:
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, train_size=n_train, random_state=42
    )

    models = []
    for bit in range(8):
        m = LogisticRegression(max_iter=1000)
        m.fit(X_train, y_train[:, bit])
        models.append(m)

    per_bit_acc = [
        accuracy_score(y_test[:, bit], models[bit].predict(X_test))
        for bit in range(8)
    ]

    # Stricter metric: the FULL 8-bit response must be right for it to count.
    y_pred_full = np.column_stack([m.predict(X_test) for m in models])
    full_response_acc = np.mean(np.all(y_pred_full == y_test, axis=1))

    results.append({
        'n_train': n_train,
        'avg_bit_acc': np.mean(per_bit_acc),
        'full_response_acc': full_response_acc
    })
    print(f"n_train={n_train:3d}  bit-acc={np.mean(per_bit_acc):.3f}  full-response-acc={full_response_acc:.3f}")

# ── Plot ─────────────────────────────────────────────────────────────────
results_df = pd.DataFrame(results)
fig, axes = plt.subplots(1, 2, figsize=(12, 5))

axes[0].plot(results_df['n_train'], results_df['avg_bit_acc'] * 100, 'b-o')
axes[0].axhline(90, color='r', linestyle='--', label='90% threshold')
axes[0].set_xlabel('Training CRPs'); axes[0].set_ylabel('Accuracy (%)')
axes[0].set_title('Bit-level accuracy vs training size'); axes[0].legend(); axes[0].grid(True)

axes[1].plot(results_df['n_train'], results_df['full_response_acc'] * 100, 'g-o')
axes[1].axhline(50, color='r', linestyle='--', label='50% threshold')
axes[1].set_xlabel('Training CRPs'); axes[1].set_ylabel('Accuracy (%)')
axes[1].set_title('Full 8-bit response accuracy vs training size'); axes[1].legend(); axes[1].grid(True)

plt.tight_layout()
plt.savefig('plots/ml_attack_naive_puf.png', dpi=150)
plt.show()

print("\nSaved plots/ml_attack_naive_puf.png")
print("With ~120 CRPs, bit accuracy typically exceeds 85%, meaning an attacker")
print("can predict most response bits without ever touching the hardware.")
```

**What to expect:** bit-level accuracy climbing past 85–90% by ~120 training CRPs; full-response accuracy lower (all 8 bits must be simultaneously right) but far above the 0.4% random-chance baseline.

---

## Part 8 — Defense: Hardening the PUF Against the Attack

### 8.1 Why the attack worked, and how to break it

Each raw response bit reflects exactly one oscillator-pair comparison, independent of the others. Once the model has seen enough of those comparisons, it learns the full frequency ranking of the oscillator pool and can predict any new pairing.

Two complementary fixes:

- **Hardware — XOR mixing.** Instead of outputting each cell's raw comparison bit, XOR it together with a neighboring cell's bit. Now each output bit depends on *two* independent oscillator comparisons instead of one, so an attacker has to correctly predict two comparisons simultaneously to get one output bit right — the model's job gets combinatorially harder without adding any new hardware complexity.
- **Software — challenge-dependent permutation.** Before deriving a key from the response, shuffle the response bytes in an order derived from the specific challenge set used. Even a perfectly-predicted raw response is useless to an attacker who doesn't know the permutation.

We implement the hardware fix here; it's the stronger and more interesting one to demonstrate.

### 8.2 `puf_array_xor.v` — hardened array (replaces `puf_array.v`)

```verilog
`timescale 1ns / 1ps

module puf_array_xor (
    input        clk,
    input        rstc,
    input        rst_dff,
    input  [7:0] C,
    input        out_trig,
    output [7:0] R
);
    wire [3:0] sel0 = C[3:0];
    wire [3:0] sel1 = C[7:4];

    wire [7:0] raw_R;   // raw, per-cell comparison outputs (what puf_array.v exposed directly)

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : cells
            puf_cell #(.CELL_ID(i)) cell (
                .clk(clk), .rstc(rstc), .rst_dff(rst_dff),
                .sel0(sel0), .sel1(sel1),
                .out_trig(out_trig), .R(raw_R[i])
            );
        end
    endgenerate

    // Circular XOR mixing: R[i] = raw[i] XOR raw[(i+1) mod 8]
    // No output bit is now an independent single measurement — each one
    // depends on two oscillator-pair comparisons at once.
    assign R[0] = raw_R[0] ^ raw_R[1];
    assign R[1] = raw_R[1] ^ raw_R[2];
    assign R[2] = raw_R[2] ^ raw_R[3];
    assign R[3] = raw_R[3] ^ raw_R[4];
    assign R[4] = raw_R[4] ^ raw_R[5];
    assign R[5] = raw_R[5] ^ raw_R[6];
    assign R[6] = raw_R[6] ^ raw_R[7];
    assign R[7] = raw_R[7] ^ raw_R[0];

endmodule
```

To use it: in `puf_top.v`, change the instantiation from `puf_array array (...)` to `puf_array_xor array (...)`. Re-run synthesis, generate a new bitstream, re-flash the board, and re-run `01_collect_crps.py`, saving the output to `data/crp_dataset_hardened.csv` this time (edit the output filename in the script, or just rename the file afterward).

### 8.3 `03_defense_verification.py` — proving the defense works

```python
# Runs the identical attack from Part 7 against both datasets and compares.

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score
import matplotlib.pyplot as plt

def load_and_prepare(csv_path: str):
    df = pd.read_csv(csv_path)
    X = np.array([[(c >> (7 - i)) & 1 for i in range(8)] for c in df['challenge']])
    y = np.array([[(r >> b) & 1 for b in range(8)] for r in df['response']])
    return X, y

def run_attack(X, y, n_train: int) -> float:
    X_train, X_test, y_train, y_test = train_test_split(X, y, train_size=n_train, random_state=42)
    accs = []
    for bit in range(8):
        m = LogisticRegression(max_iter=1000)
        m.fit(X_train, y_train[:, bit])
        accs.append(accuracy_score(y_test[:, bit], m.predict(X_test)))
    return float(np.mean(accs))

X_naive,    y_naive    = load_and_prepare('data/crp_dataset.csv')
X_hardened, y_hardened = load_and_prepare('data/crp_dataset_hardened.csv')

training_sizes = [20, 40, 80, 120, 160, 200]
acc_naive    = [run_attack(X_naive,    y_naive,    n) for n in training_sizes]
acc_hardened = [run_attack(X_hardened, y_hardened, n) for n in training_sizes]

print(f"{'CRPs':>6} | {'Naive PUF':>10} | {'Hardened PUF':>13}")
print("-" * 36)
for n, a, h in zip(training_sizes, acc_naive, acc_hardened):
    print(f"{n:>6} | {a*100:>9.1f}% | {h*100:>12.1f}%")

plt.figure(figsize=(9, 5))
plt.plot(training_sizes, [a*100 for a in acc_naive],    'r-o', label='Naive PUF (no defense)')
plt.plot(training_sizes, [a*100 for a in acc_hardened], 'g-o', label='Hardened PUF (XOR mixing)')
plt.axhline(50, color='gray', linestyle='--', label='Random-chance baseline')
plt.xlabel('Training CRPs available to attacker'); plt.ylabel('Attack accuracy (%)')
plt.title('ML Modeling Attack: Naive vs Hardened PUF')
plt.legend(); plt.grid(True); plt.tight_layout()
plt.savefig('plots/defense_comparison.png', dpi=150)
plt.show()
print("\nSaved plots/defense_comparison.png")
```

**What to expect:** naive-PUF accuracy climbing to 85–95% with more CRPs, as before. Hardened-PUF accuracy should stay much flatter, ideally in the 55–65% range even at 200 training CRPs — close to random guessing, because the XOR mixing breaks the linear structure logistic regression depends on.

---

## Part 9 — Reinforcement Learning for Challenge Selection

### 9.1 The problem this solves

You have 256 possible challenges. For real authentication you don't want to use all 256 — you want to pick a small set (say 8) that will hold up reliably over time. Two things make a challenge "good":

- **Stability** — asking the same challenge repeatedly gives the same response almost every time (low sensitivity to temperature/voltage noise)
- **Entropy** — the response bits are close to balanced between 0 and 1, so an attacker can't just guess the majority value and be right most of the time

Picking challenges by hand or at random risks including unstable or low-entropy ones, which weakens both reliability and security. A reinforcement learning (RL) agent can explore the challenge space and learn, from direct experience, which challenges consistently score well on both dimensions — without you having to hand-inspect all 256.

### 9.2 State, action, reward — the three things RL needs

If you've never seen RL before, here's the entire idea in three pieces:

- **Action** — a single decision the agent makes at each step. Here: *pick one challenge (0–255) to query next.*
- **Reward** — a number fed back to the agent immediately after it acts, saying how good that action turned out to be. Here: a combination of the observed stability and entropy of that challenge's response.
- **Policy / value estimate** — what the agent is actually learning: which actions tend to lead to high reward, so it can prefer them in the future. In Q-learning (below) this is a table of expected-reward estimates, one per challenge, called *Q-values*.

The agent doesn't need a complex notion of "state" here, because each challenge's quality doesn't depend on what happened before it — every challenge is an independent slot machine, and the agent's job is to find the best ones. This is technically a **multi-armed bandit** problem, the simplest member of the RL family, which makes it a good starting point if RL is new to you. We also show the fuller Q-learning/DQN formulation since you asked for RL specifically, and because it generalizes cleanly if you later expand to a larger challenge space.

### 9.3 `04_rl_challenge_selection.py` — Q-learning agent

This trains against a **simulator built from your real collected data**, so the agent can run thousands of trial queries in seconds instead of taking hours on physical hardware. The simulator reproduces the *exact* stability statistics your board measured — it isn't inventing behavior, it's replaying your real device's noise characteristics many times over.

```python
# Q-learning agent that discovers which challenges give the most reliable,
# highest-entropy responses. Trains against a simulator seeded from your
# real crp_dataset.csv so it reflects your actual board's behavior.

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import json
import os

os.makedirs('plots',  exist_ok=True)
os.makedirs('models', exist_ok=True)

# ── Step 1: build a noise-accurate simulator from your real data ─────────
df = pd.read_csv('data/crp_dataset.csv')
crp_lookup = {
    int(row['challenge']): {'response': int(row['response']), 'stability': float(row['stability'])}
    for _, row in df.iterrows()
}

def query_puf_simulated(challenge: int) -> int:
    """
    One simulated noisy query. Uses the real per-challenge stability score
    from your hardware: if stability = 0.857 (6 of 7 trials matched), each
    bit independently has a ~14.3% chance of flipping in this draw.
    """
    info = crp_lookup[challenge]
    flip_prob = 1.0 - info['stability']
    noisy = 0
    for bit in range(8):
        original = (info['response'] >> bit) & 1
        actual = (1 - original) if (np.random.random() < flip_prob) else original
        noisy |= (actual << bit)
    return noisy

# ── Step 2: reward function ───────────────────────────────────────────────
def entropy_score(response: int) -> float:
    """1.0 if exactly 4 of 8 bits are 1 (perfectly balanced), 0.0 if all-0 or all-1."""
    ones = bin(response).count('1')
    return 1.0 - abs(ones - 4) / 4.0

def get_reward(challenge: int, n_samples: int = 7):
    """
    Query the challenge n_samples times, majority-vote to find the stable
    response, then combine stability and entropy into one reward.
    Stability is weighted higher: an unstable CRP is useless even with
    perfect entropy, since authentication would fail unpredictably.
    """
    responses = [query_puf_simulated(challenge) for _ in range(n_samples)]
    stable = 0
    for bit in range(8):
        ones = sum(1 for r in responses if (r >> bit) & 1)
        if ones > n_samples // 2:
            stable |= (1 << bit)
    stability = sum(1 for r in responses if r == stable) / n_samples
    entropy   = entropy_score(stable)
    reward    = 0.6 * stability + 0.4 * entropy
    return reward, stability, entropy, stable

# ── Step 3: Q-learning agent ──────────────────────────────────────────────
# Q[a] holds this agent's current estimate of "how good is challenge a".
# At each step: with probability epsilon, try a random challenge (explore).
# Otherwise, pick whichever challenge currently has the highest Q (exploit).
# After seeing the reward: Q[a] += alpha * (reward - Q[a])   (a simple running average)

class QLearningChallengeSelector:
    def __init__(self, n_challenges=256, alpha=0.1, epsilon=0.3):
        self.n = n_challenges
        self.alpha = alpha
        self.epsilon = epsilon
        self.Q = np.full(n_challenges, 0.5)              # neutral starting estimate
        self.visit_count = np.zeros(n_challenges, dtype=int)

    def select_action(self) -> int:
        if np.random.random() < self.epsilon:
            return np.random.randint(self.n)
        return int(np.argmax(self.Q))

    def update(self, action: int, reward: float):
        self.Q[action] += self.alpha * (reward - self.Q[action])
        self.visit_count[action] += 1

    def get_top_k(self, k: int = 8) -> list:
        return np.argsort(self.Q)[::-1][:k].tolist()

# ── Step 4: train ──────────────────────────────────────────────────────────
N_EPISODES = 2000
agent = QLearningChallengeSelector(alpha=0.1, epsilon=0.3)
rewards_log = []

print("Training Q-learning agent...")
for episode in range(N_EPISODES):
    agent.epsilon = max(0.05, 0.3 * (1 - episode / N_EPISODES))  # explore less as it learns
    action = agent.select_action()
    reward, stability, entropy, _ = get_reward(action)
    agent.update(action, reward)
    rewards_log.append(reward)

    if episode % 200 == 0:
        avg_r = np.mean(rewards_log[-200:]) if episode > 0 else reward
        print(f"Episode {episode:4d} | avg reward {avg_r:.3f} | epsilon {agent.epsilon:.3f} | top-4 {agent.get_top_k(4)}")

print("\nTraining complete.")

# ── Step 5: evaluate RL-selected vs random challenges ──────────────────────
top_8 = agent.get_top_k(8)
random_8 = np.random.choice(256, 8, replace=False).tolist()
print(f"\nRL-selected challenges: {top_8}")

def evaluate_set(challenges: list, n_eval: int = 50) -> dict:
    stabilities, entropies = [], []
    for c in challenges:
        for _ in range(n_eval // len(challenges)):
            _, stab, ent, _ = get_reward(c)
            stabilities.append(stab); entropies.append(ent)
    return {
        'avg_stability': np.mean(stabilities),
        'avg_entropy':   np.mean(entropies),
        'combined':      0.6*np.mean(stabilities) + 0.4*np.mean(entropies)
    }

rl_eval, rnd_eval = evaluate_set(top_8), evaluate_set(random_8)
print(f"RL-selected:  stability={rl_eval['avg_stability']:.3f}  entropy={rl_eval['avg_entropy']:.3f}  combined={rl_eval['combined']:.3f}")
print(f"Random:       stability={rnd_eval['avg_stability']:.3f}  entropy={rnd_eval['avg_entropy']:.3f}  combined={rnd_eval['combined']:.3f}")

# ── Step 6: plots ────────────────────────────────────────────────────────
fig, axes = plt.subplots(1, 3, figsize=(15, 4))

q_grid = agent.Q.reshape(16, 16)
im = axes[0].imshow(q_grid, cmap='RdYlGn', vmin=0, vmax=1)
axes[0].set_title('Learned Q-values'); axes[0].set_xlabel('C[3:0]'); axes[0].set_ylabel('C[7:4]')
plt.colorbar(im, ax=axes[0])
for c in top_8:
    axes[0].plot(c & 0xF, (c >> 4) & 0xF, 'b*', markersize=12)

window = 50
smoothed = [np.mean(rewards_log[max(0, i-window):i+1]) for i in range(len(rewards_log))]
axes[1].plot(smoothed, 'b-'); axes[1].set_xlabel('Episode'); axes[1].set_ylabel('Reward (smoothed)')
axes[1].set_title('Reward over training'); axes[1].grid(True)

vc_grid = agent.visit_count.reshape(16, 16)
im2 = axes[2].imshow(vc_grid, cmap='Blues')
axes[2].set_title('Times each challenge was queried'); axes[2].set_xlabel('C[3:0]'); axes[2].set_ylabel('C[7:4]')
plt.colorbar(im2, ax=axes[2])

plt.tight_layout()
plt.savefig('plots/rl_challenge_selection.png', dpi=150)
plt.show()

with open('models/rl_selected_challenges.json', 'w') as f:
    json.dump({'challenges': top_8, 'q_values': agent.Q[top_8].tolist()}, f, indent=2)

print("\nSaved models/rl_selected_challenges.json")
```

### 9.4 Optional: DQN for a larger challenge space

Q-learning keeps one table entry per challenge — fine for 256 challenges, but it stops scaling if you later move to a PUF design with a much larger challenge space (e.g. a multi-stage XOR-PUF with thousands of possible inputs). Deep Q-Networks (DQN) replace the table with a small neural network that *generalizes* across challenges instead of memorizing each one individually. This is optional for your current 256-challenge design, but included here since you asked for RL broadly.

```python
# Optional: DQN variant. Only worth using if your challenge space grows
# beyond a few thousand — for 256 challenges, the Q-learning agent above
# is simpler, faster to train, and just as effective.

import torch
import torch.nn as nn
import torch.optim as optim
from collections import deque
import random as pyrandom

class QNetwork(nn.Module):
    """Maps a one-hot challenge encoding to an estimated Q-value per challenge."""
    def __init__(self, n_challenges=256):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(n_challenges, 128), nn.ReLU(),
            nn.Linear(128, 64),  nn.ReLU(),
            nn.Linear(64, n_challenges)
        )
    def forward(self, x):
        return self.net(x)

class DQNAgent:
    def __init__(self, n_challenges=256, lr=1e-3, epsilon=0.3):
        self.n = n_challenges
        self.epsilon = epsilon
        self.policy_net = QNetwork(n_challenges)
        self.optimizer = optim.Adam(self.policy_net.parameters(), lr=lr)
        self.memory = deque(maxlen=10000)

    def select_action(self) -> int:
        if pyrandom.random() < self.epsilon:
            return pyrandom.randint(0, self.n - 1)
        with torch.no_grad():
            q = self.policy_net(torch.ones(self.n))   # stateless: constant input
            return int(q.argmax().item())

    def remember(self, action: int, reward: float):
        self.memory.append((action, reward))

    def train_step(self, batch_size=32):
        if len(self.memory) < batch_size:
            return
        batch = pyrandom.sample(self.memory, batch_size)
        actions = torch.tensor([b[0] for b in batch], dtype=torch.long)
        rewards = torch.tensor([b[1] for b in batch], dtype=torch.float32)
        q_vals = self.policy_net(torch.ones(batch_size, self.n))
        q_taken = q_vals.gather(1, actions.unsqueeze(1)).squeeze()
        loss = nn.MSELoss()(q_taken, rewards)
        self.optimizer.zero_grad(); loss.backward(); self.optimizer.step()

    def get_top_k(self, k=8) -> list:
        with torch.no_grad():
            q = self.policy_net(torch.ones(self.n))
            return q.topk(k).indices.tolist()

dqn_agent = DQNAgent(n_challenges=256, epsilon=0.3)
print("Training DQN agent...")
for episode in range(2000):
    dqn_agent.epsilon = max(0.05, 0.3 * (1 - episode / 2000))
    action = dqn_agent.select_action()
    reward, _, _, _ = get_reward(action)
    dqn_agent.remember(action, reward)
    dqn_agent.train_step()
    if episode % 400 == 0 and episode > 0:
        print(f"Episode {episode}: top-4 = {dqn_agent.get_top_k(4)}")

print(f"\nDQN top 8 challenges: {dqn_agent.get_top_k(8)}")
torch.save(dqn_agent.policy_net.state_dict(), 'models/dqn_policy.pt')
```

---

## Part 10 — Running Everything End to End

```
1.  Build puf_top.v using puf_array (naive) → generate bitstream → flash to board
2.  Run 01_collect_crps.py on the board       → data/crp_dataset.csv
3.  Copy crp_dataset.csv to your computer
4.  Run 02_ml_attack.py                        → plots/ml_attack_naive_puf.png
                                                  (attack succeeds: 85-95% bit accuracy)

5.  Edit puf_top.v to use puf_array_xor instead of puf_array
6.  Re-synthesize, regenerate bitstream, re-flash the board
7.  Run 01_collect_crps.py again               → data/crp_dataset_hardened.csv
8.  Run 03_defense_verification.py             → plots/defense_comparison.png
                                                  (attack now fails: ~55-65% accuracy)

9.  Run 04_rl_challenge_selection.py           → plots/rl_challenge_selection.png
                                                  → models/rl_selected_challenges.json

10. Use the challenges from rl_selected_challenges.json as your enrollment set
    for any downstream authentication scheme (BCH error correction + key
    derivation, following the same pattern as a standard PUF fuzzy extractor).
```

---

## Part 11 — Expected Results and How to Read Them

### ML attack

| Metric | Naive PUF | Hardened PUF (XOR) |
|---|---|---|
| Bit accuracy at 120 CRPs | 85–95% | 55–65% |
| Full 8-bit response accuracy at 120 CRPs | 40–70% | 2–8% |
| CRPs needed for 90% bit accuracy | ~80–150 | not reached within 256 CRPs |

If your naive-PUF attack accuracy stays below ~70% even at 200 CRPs, check two things first: (a) your average stability from Part 6's sanity check — if it's under 0.7, your oscillators are too noisy for any of this to work cleanly; (b) whether Vivado's synthesis log shows the ring oscillator nets were merged (search the implemented netlist for your `w1`–`w7` nets — if they collapsed into fewer physical nets than expected, `KEEP="TRUE"` wasn't honored).

If your hardened-PUF attack accuracy is still above ~80% at 200 CRPs, double check that `puf_top.v` actually instantiates `puf_array_xor`, not the original `puf_array` — a common copy-paste miss.

### RL challenge selection

| Metric | RL-selected | Random |
|---|---|---|
| Average stability | 0.92–0.98 | 0.85–0.92 |
| Average entropy score | 0.80–0.95 | 0.65–0.80 |
| Combined score | 0.88–0.96 | 0.76–0.88 |

The Q-value heatmap should show visibly brighter (higher-value) regions rather than uniform noise — that's the agent converging on real structure in your board's oscillator variation, not random luck.

---

## Part 12 — Troubleshooting

**"Vivado reports a combinational loop error and synthesis fails"**
The `puf_constraints.xdc` file either isn't in your project's constraint sources, or the `ALLOW_COMBINATORIAL_LOOPS` lines didn't apply. Confirm the file is checked as active under the Constraints tree in Sources, then re-run Synthesis.

**"Every response is 0x00 or 0xFF regardless of challenge"**
The oscillators aren't actually varying — usually because only one oscillator is enabled globally instead of one-per-group, or because `KEEP="TRUE"` was dropped somewhere and Vivado merged the "identical" oscillator instances into one. Check the implemented design's netlist for how many distinct `ring_osc` instances actually survived synthesis.

**"PYNQ says 'Overlay not found' or fails to load the bitstream"**
The `.bit` and `.hwh` files must sit in the same folder as your notebook and must share the same base filename. Confirm you copied both, not just the `.bit` file.

**"The ML attack only reaches ~50% accuracy even on the naive PUF"**
Your CRP dataset is probably too noisy. Check the sanity-check output from Part 6 — if average stability is under 0.70, majority voting isn't converging cleanly. Try increasing `NUM_TRIALS` to 11 or 15 in `01_collect_crps.py`.

**"The RL agent always picks the same challenge and never explores"**
Epsilon likely decayed too fast, or the reward signal is too flat to differentiate challenges. Try raising the starting `epsilon` to 0.5, slowing its decay, and confirming `get_reward()` returns visibly different values for different challenges (print a few manually to check).

---

## Part 13 — File Reference

```
ro_puf_project/
├── verilog/
│   ├── clock_div_2.v          ← frequency divider (4.1)
│   ├── ring_osc.v             ← single ring oscillator (4.2)
│   ├── puf_cell.v             ← one PUF cell, one response bit (4.3)
│   ├── puf_array.v            ← 8 cells, naive/undefended PUF (4.4)
│   ├── puf_array_xor.v        ← 8 cells, XOR-hardened PUF (8.2)
│   ├── puf_driver.v           ← timing controller (4.5)
│   └── puf_top.v              ← top module, AXI GPIO ports (4.6)
│
├── vivado_project/            ← created by Vivado (Part 5)
│
├── python/
│   ├── 01_collect_crps.py             ← CRP collection from hardware (Part 6)
│   ├── 02_ml_attack.py                ← ML modeling attack demo (Part 7)
│   ├── 03_defense_verification.py     ← proves the hardware defense works (Part 8.3)
│   ├── 04_rl_challenge_selection.py   ← Q-learning + optional DQN agent (Part 9)
│   │
│   ├── data/
│   │   ├── crp_dataset.csv            ← naive PUF responses
│   │   └── crp_dataset_hardened.csv   ← XOR-hardened PUF responses
│   │
│   ├── models/
│   │   ├── rl_selected_challenges.json
│   │   └── dqn_policy.pt              ← optional
│   │
│   └── plots/
│       ├── ml_attack_naive_puf.png
│       ├── defense_comparison.png
│       └── rl_challenge_selection.png
│
└── README.md
```
