# 🔋 AES-128 Low-Power Hardware Accelerator

![Language](https://img.shields.io/badge/Language-Verilog-blue)
![Target](https://img.shields.io/badge/Optimization-Low%20Power-orange)
![License](https://img.shields.io/badge/License-MIT-green)
![Status](https://img.shields.io/badge/Status-Fully%20Implemented-brightgreen)

## 📌 Overview

This repository contains a Verilog implementation of an **AES-128 encryption system** optimized to drastically reduce dynamic power consumption through **Architecture-Driven Voltage Scaling**. 

By employing an N=2 hardware duplication strategy and staggered execution, the architecture lowers the effective per-lane operating rate while strictly preserving the aggregate system throughput.

---

## 📊 Hardware Utilization & Metrics
Synthesized with a baseline 100 MHz target frequency. The results demonstrate a **50% reduction in dynamic power** compared to the baseline single-core design.

| Metric | Baseline (Single Core) | Proposed (N=2) | Change |
| :--- | :---: | :---: | :---: |
| **Dynamic Power** | 0.700 W | 0.350 W | **-50.0%** |
| **Total On-Chip Power** | 0.832 W | 0.489 W | **-41.2%** |
| **Throughput** | 1.28 Gbps | 1.28 Gbps | Preserved |
| **Per-Block Latency** | 100 ns | 200 ns | +100% |
| **Slice LUTs** | 3,978 | 10,618 | +6,640 |
| **Slice Registers (FFs)**| 262 | 3,790 | +3,528 |

*Note: The area increase is an expected architectural tradeoff resulting from duplication overhead, input broadcast routing, completion multiplexing, and Reorder Buffer (ROB) sequence tracking.*

---

## ✨ Key Features

### ✔ Architectural Optimizations (Low Power)
* **N=2 Hardware Duplication:** Two parallel AES lanes share an input broadcast, dividing the workload.
* **Staggered Execution:** Utilizes one global clock combined with a round-robin phase counter to generate per-lane clock-enable (CE) pulses.
* **Effective Update Rate:** Each lane operates at an effective rate of $f_{sample}/2$, allowing for lower dynamic switching power.

### ✔ Data Flow & Control
* **Baseline Core Execution:** Features a standard 10-round AES execution after the initial add-round-key (one round per clock).
* **Sequence-Aware Retirement:** Lane outputs in the parallel path are tagged by sequence ID and written to a Reorder Buffer (ROB).
* **In-Order Emittance:** Ensures the ciphertext is retired strictly in its original input order, cleanly abstracting the parallel execution from the downstream logic.

---

## 🚀 Verification & Results

The design has been verified using Verilog testbenches against the **NIST AES-128 ECB Known-Answer Test (KAT)** vectors. 

**Simulation Success:**
* **Baseline (`tb_aes_top.v`):** Validates the correctness of the single-core baseline encryption.
* **Proposed (`tb_aes_top_parallel.v`):** Validates the staggered CE dispatch and confirms the in-order output retirement from the ROB.

> **How to Run Simulation:** Use your preferred Verilog simulator. Compile all source files under `src/rtl/` together with the selected testbench from `sim/tb/`.

---

## 📂 Directory Structure
```text
AES128-LowPower-Architecture/
├── src/
│   └── rtl/
│       ├── addroundkey.v
│       ├── aes128_core.v
│       ├── aes128_core_ce.v
│       ├── aes_final_round.v
│       ├── aes_round.v
│       ├── aes_top.v
│       ├── aes_top_parallel.v
│       ├── key_expand.v
│       ├── mixcolumns.v
│       ├── sbox.v
│       ├── shiftrows.v
│       ├── subbytes.v
│       └── subword.v
├── sim/
│   └── tb/
│       ├── tb_aes_top.v
│       └── tb_aes_top_parallel.v
├── .gitattributes
├── .gitignore
└── README.md
