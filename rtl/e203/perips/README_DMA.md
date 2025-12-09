# DMA Controller for E203 SoC

## Overview

The DMA (Direct Memory Access) controller provides hardware-accelerated memory-to-memory data transfer capabilities for the E203 SoC. It follows the ICB (Internal Chip Bus) protocol used throughout the E203 design.

## Files

- `sirv_dma.v` - Core DMA controller module
- `../subsys/e203_subsys_dma_wrapper.v` - Wrapper for E203 subsystem integration  
- `../../tb/tb_dma.v` - Testbench for verification

## Features

- ICB bus protocol compliant
- Memory-to-memory data transfer
- Configurable source, destination, and transfer length
- Interrupt generation on completion or error
- State machine-based operation
- Error handling support

## Register Map

| Offset | Register    | Bits | Description                          |
|--------|-------------|------|--------------------------------------|
| 0x00   | DMA_CTRL    | [0]  | Enable: 1=enabled, 0=disabled        |
|        |             | [1]  | Start: Write 1 to start transfer     |
|        |             | [2]  | Direction (reserved for future use)  |
| 0x04   | DMA_STATUS  | [0]  | Busy: 1=transfer in progress         |
|        |             | [1]  | Done: 1=transfer complete            |
|        |             | [2]  | Error: 1=error occurred              |
| 0x08   | DMA_SRC     | [31:0] | Source address (word-aligned)      |
| 0x0C   | DMA_DST     | [31:0] | Destination address (word-aligned) |
| 0x10   | DMA_LEN     | [31:0] | Transfer length in bytes           |

## Usage Example

```verilog
// 1. Configure source address
dma_write(32'h08, 32'h00001000);  // SRC = 0x1000

// 2. Configure destination address  
dma_write(32'h0C, 32'h00002000);  // DST = 0x2000

// 3. Configure transfer length
dma_write(32'h10, 32'h00000040);  // LEN = 64 bytes

// 4. Enable and start DMA
dma_write(32'h00, 32'h00000003);  // CTRL: enable + start

// 5. Wait for completion
do {
    dma_read(32'h04, status);
} while ((status & 0x02) == 0);  // Wait for DONE bit

// 6. Clear done status
dma_write(32'h04, 32'h00000002);  // Clear DONE bit
```

## Constraints

- Source and destination addresses must be word-aligned (4-byte boundary)
- Transfer length must be a multiple of word size (4 bytes)
- Maximum register address space: 32 bytes (5-bit addressing)
- Transfers are performed word-by-word (32-bit)

## Testing

Run the testbench to verify functionality:

```bash
cd /path/to/project
iverilog -o tb_dma \
  -I rtl/e203/core \
  rtl/e203/perips/sirv_dma.v \
  tb/tb_dma.v
./tb_dma
```

The testbench performs:
1. Register read/write verification
2. Memory-to-memory transfer (64 bytes)
3. Data integrity verification
4. Interrupt signal verification

## Integration

To integrate the DMA controller into the E203 SoC:

1. Instantiate `e203_subsys_dma_wrapper` in your subsystem
2. Connect configuration ICB interface to the peripheral bus
3. Connect memory ICB interface to the memory bus
4. Route `dma_irq` signal to the PLIC (Platform-Level Interrupt Controller)

## License

Copyright 2018-2020 Nuclei System Technology, Inc.

Licensed under the Apache License, Version 2.0.
