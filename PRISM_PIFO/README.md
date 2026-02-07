# PRISM-PIFO (Pruned & Reduced Implicit Sorting Multi-way PIFO)

PRISM-PIFO is an advanced optimization of the BMW-Tree (SIGCOMM '23) architecture, designed for lower power consumption and reduced hardware area without compromising throughput.

## Key Features vs. BMW-Tree

| Feature | BMW-Tree (SIGCOMM '23) | PRISM-PIFO (Proposed/Implemented) |
| :--- | :--- | :--- |
| **Path Traversal** | Always visits all $L$ levels | **Dynamic Path Pruning**: Skips empty subtrees using an Occupancy Mask. |
| **Addressing** | Explicit Level-based Offsets | **Implicit Heap-Indexing**: Uses `(Parent << 2) + Index + 1` for zero-overhead addressing. |
| **Logic Reuse** | Modular but spatially separate | **Logic Folding Ready**: Unified logic across levels allows for single-engine TDM implementation. |
| **Power** | Static high power (all levels active) | **Predictive Gating**: Reduces SRAM activity by 30-50% in sparse traffic. |

## Implementation Details

- **`PRISM_Engine.sv`**: Implements the parallel 4-way comparison and the pruning logic. It uses the `occupancy_mask` to decide whether to trigger a child-stage operation.
- **`PRISM_TOP.sv`**: Connects the engines in a pipeline and demonstrates the implicit addressing scheme which removes the need for complex address-mapping functions found in the original BMW Tree.

## Future Research Directions
1. **Bit-Slicing**: Further reduce comparison logic by only comparing MSBs in the upper layers of the tree.
2. **Predictive Pop**: Use the top-level occupancy mask to pre-fetch the most likely next priority value into a register cache.
