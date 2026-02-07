# Turbo-PIFO (Extreme Throughput & Hybrid Stability PIFO)

Turbo-PIFO is a high-performance evolution of the BMW-Tree, specifically engineered for extreme throughput (>400Mpps) and hardware stability on Xilinx FPGAs.

## Architectural Innovations

### 1. Interleaved Dual-Pipeline (IDP)
Instead of a single deep tree, Turbo-PIFO uses two identical sorting pipelines operating in parallel. A high-speed **Dispatcher** distributes Push operations based on a load-balancing hash, effectively doubling the theoretical throughput.

### 2. Register-SRAM Hybrid Storage
- **Level 0 (Root)**: Implemented using **Registers (FFs)**. This allows for zero-wait state access to the most critical part of the tree, eliminating SRAM arbitration bottlenecks for the highest priority packets.
- **Level 1+**: Implemented using **UltraRAM/BlockRAM**. These layers handle the large-scale capacity while benefiting from the deterministic timing provided by the Register-based root.

### 3. Speculative Pre-fetch Logic
The engine anticipates the next required SRAM address during the comparison phase of the previous stage, hiding memory latency and ensuring the pipeline remains full even under heavy "Pop" bursts.

## Performance Goals (Target: Xilinx Alveo U200)

| Metric | Target Value | Improvement vs. BMW-PIFO |
| :--- | :--- | :--- |
| **Throughput** | 400 - 500 Mpps | ~2x - 2.5x |
| **Fmax** | 350+ MHz | +15% (Reduced logic depth) |
| **Latency** | Deterministic $L$ cycles | Lower jitter due to Reg-Root |
| **Scale** | 64k+ Flows | Maintained via SRAM back-end |

## Directory Contents
- **`Turbo_TOP.sv`**: Top-level wrapper with interleaved pipeline management.
- **`Turbo_Dispatcher.sv`**: Logic for distributing packets across internal engines.
- **`Turbo_Engine.sv`**: Optimized BMW-core with hybrid storage support.
