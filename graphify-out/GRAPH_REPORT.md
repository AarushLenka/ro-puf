# Graph Report - .  (2026-08-21)

## Corpus Check
- Corpus is ~3,887 words - fits in a single context window. You may not need a graph.

## Summary
- 75 nodes · 66 edges · 18 communities (5 shown, 13 thin omitted)
- Extraction: 83% EXTRACTED · 12% INFERRED · 5% AMBIGUOUS · INFERRED: 8 edges (avg confidence: 0.81)
- Token cost: 4,200 input · 2,100 output

## Community Hubs (Navigation)
- Host-Hardware CRP Bridge
- PUF Top-Level Integration
- Deep Q-Network Agent
- RL Challenge Environment
- Tabular Q-Learning Selector
- Ring Oscillator (PUF_HOME)
- ML Modeling Attack
- Ring Oscillator (verilog)
- Clock Divider (PUF_HOME)
- PUF Array (PUF_HOME)
- XOR-Hardened Array (PUF_HOME)
- PUF Cell (PUF_HOME)
- PUF Driver FSM (PUF_HOME)
- Clock Divider (verilog)
- PUF Array (verilog)
- XOR-Hardened Array (verilog)
- PUF Cell (verilog)

## God Nodes (most connected - your core abstractions)
1. `DQNAgent` - 6 edges
2. `get_reward()` - 5 edges
3. `QLearningChallengeSelector` - 5 edges
4. `QNetwork` - 5 edges
5. `puf_top` - 5 edges
6. `puf_bd Vivado Block Design` - 5 edges
7. `puf_top` - 4 edges
8. `query_puf()` - 4 edges
9. `query_puf_simulated()` - 3 edges
10. `entropy_score()` - 3 edges

## Surprising Connections (you probably didn't know these)
- `ro-puf (Ring Oscillator PUF Project)` --conceptually_related_to--> `puf_top`  [INFERRED]
  README.md → verilog/puf_top.v
- `PUF Top IP Instance` --implements--> `puf_top`  [INFERRED]
  puf schematic.pdf → PUF_HOME/verilog/puf_top.v
- `AXI GPIO Challenge/Response Interface` --shares_data_with--> `query_puf()`  [INFERRED]
  puf schematic.pdf → python/01_collect_crps.py
- `Zynq7 Processing System` --shares_data_with--> `query_puf()`  [INFERRED]
  puf schematic.pdf → python/01_collect_crps.py
- `AXI GPIO Challenge/Response Interface` --shares_data_with--> `puf_driver`  [INFERRED]
  puf schematic.pdf → verilog/puf_driver.v

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **CRP Collection Data Path (host to PUF array)** — python_01_collect_crps_query_puf, puf_schematic_zynq_ps, puf_schematic_axi_gpio, puf_schematic_puf_top_ip, verilog_puf_driver_puf_driver [INFERRED 0.75]

## Communities (18 total, 13 thin omitted)

### Community 0 - "Host-Hardware CRP Bridge"
Cohesion: 0.18
Nodes (10): AXI GPIO Challenge/Response Interface, AXI Interconnect, Processor System Reset, puf_bd Vivado Block Design, Zynq7 Processing System, majority_vote(), query_puf(), Send one challenge, wait for the done flag, return the 8-bit response. (+2 more)

### Community 1 - "PUF Top-Level Integration"
Cohesion: 0.20
Nodes (8): puf_top, puf_array, puf_driver, PUF Top IP Instance, ro-puf (Ring Oscillator PUF Project), puf_top, puf_array, puf_driver

### Community 2 - "Deep Q-Network Agent"
Cohesion: 0.22
Nodes (3): DQNAgent, QNetwork, Maps a one-hot challenge encoding to an estimated Q-value per challenge.

### Community 3 - "RL Challenge Environment"
Cohesion: 0.36
Nodes (7): entropy_score(), evaluate_set(), get_reward(), query_puf_simulated(), One simulated noisy query. Uses the real per-challenge stability score     from, 1.0 if exactly 4 of 8 bits are 1 (perfectly balanced), 0.0 if all-0 or all-1., Query the challenge n_samples times, majority-vote to find the stable     respon

## Ambiguous Edges - Review These
- `puf_bd Vivado Block Design` → `AXI GPIO Challenge/Response Interface`  [AMBIGUOUS]
  puf schematic.pdf · relation: references
- `puf_bd Vivado Block Design` → `AXI Interconnect`  [AMBIGUOUS]
  puf schematic.pdf · relation: references
- `puf_bd Vivado Block Design` → `Processor System Reset`  [AMBIGUOUS]
  puf schematic.pdf · relation: references

## Knowledge Gaps
- **18 isolated node(s):** `clock_div_2`, `puf_array`, `puf_array_xor`, `puf_cell`, `puf_driver` (+13 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **13 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `puf_bd Vivado Block Design` and `AXI GPIO Challenge/Response Interface`?**
  _Edge tagged AMBIGUOUS (relation: references) - confidence is low._
- **What is the exact relationship between `puf_bd Vivado Block Design` and `AXI Interconnect`?**
  _Edge tagged AMBIGUOUS (relation: references) - confidence is low._
- **What is the exact relationship between `puf_bd Vivado Block Design` and `Processor System Reset`?**
  _Edge tagged AMBIGUOUS (relation: references) - confidence is low._
- **Why does `puf_bd Vivado Block Design` connect `Host-Hardware CRP Bridge` to `PUF Top-Level Integration`?**
  _High betweenness centrality (0.048) - this node is a cross-community bridge._
- **Why does `PUF Top IP Instance` connect `PUF Top-Level Integration` to `Host-Hardware CRP Bridge`?**
  _High betweenness centrality (0.047) - this node is a cross-community bridge._
- **Why does `DQNAgent` connect `Deep Q-Network Agent` to `RL Challenge Environment`?**
  _High betweenness centrality (0.031) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `puf_top` (e.g. with `PUF Top IP Instance` and `ro-puf (Ring Oscillator PUF Project)`) actually correct?**
  _`puf_top` has 2 INFERRED edges - model-reasoned connections that need verification._