# 2D Convolution Accelerator for E203 SoC

## Overview

The 2D Convolution Accelerator provides hardware-accelerated 3x3 convolution operations for the E203 SoC. It follows the ICB (Internal Chip Bus) protocol and supports DMA-based result storage.

## Files

- `sirv_conv2d.v` - Core 2D convolution accelerator module
- `../../tb/tb_conv2d.v` - Testbench for verification

## Features

- ICB bus protocol compliant
- 3x3 image patch convolution with 3x3 kernel
- Signed 8-bit kernel weights, unsigned 8-bit image pixels
- 32-bit signed result output
- Optional DMA write of results to memory
- Interrupt generation on completion or error
- Single-cycle convolution computation

## Register Map

| Offset | Register    | Bits | Description                          |
|--------|-------------|------|--------------------------------------|
| 0x00   | CONV_CTRL   | [0]  | Enable: 1=enabled, 0=disabled        |
|        |             | [1]  | Start: Write 1 to start computation  |
|        |             | [2]  | DMA_EN: 1=write result via DMA       |
| 0x04   | CONV_STATUS | [0]  | Busy: 1=computation in progress      |
|        |             | [1]  | Done: 1=computation complete         |
|        |             | [2]  | Error: 1=DMA error occurred          |
| 0x08   | DST_ADDR    | [31:0] | Destination address for DMA write  |
| 0x0C   | RESULT      | [31:0] | Convolution result (read-only)     |
| 0x10   | IMG_0       | [23:0] | Image row 0: [pixel2:pixel1:pixel0]|
| 0x14   | IMG_1       | [23:0] | Image row 1: [pixel5:pixel4:pixel3]|
| 0x18   | IMG_2       | [23:0] | Image row 2: [pixel8:pixel7:pixel6]|
| 0x20   | KER_0       | [23:0] | Kernel row 0: [w2:w1:w0] (signed)  |
| 0x24   | KER_1       | [23:0] | Kernel row 1: [w5:w4:w3] (signed)  |
| 0x28   | KER_2       | [23:0] | Kernel row 2: [w8:w7:w6] (signed)  |

## Data Format

### Image Pixels (Unsigned 8-bit)
Each image register contains 3 pixels packed in the lower 24 bits:
```
[31:24] Reserved (unused)
[23:16] Pixel 2 (rightmost in row)
[15:8]  Pixel 1 (center in row)
[7:0]   Pixel 0 (leftmost in row)
```

Image layout:
```
pixel0 pixel1 pixel2   -> IMG_0
pixel3 pixel4 pixel5   -> IMG_1
pixel6 pixel7 pixel8   -> IMG_2
```

### Kernel Weights (Signed 8-bit)
Each kernel register contains 3 weights packed in the lower 24 bits:
```
[31:24] Reserved (unused)
[23:16] Weight 2 (rightmost in row)
[15:8]  Weight 1 (center in row)
[7:0]   Weight 0 (leftmost in row)
```

Kernel layout:
```
w0 w1 w2   -> KER_0
w3 w4 w5   -> KER_1
w6 w7 w8   -> KER_2
```

## Usage Example

### Basic Convolution
```verilog
// Example: Sobel horizontal edge detection kernel
// Kernel:
//   [ 1  0 -1 ]
//   [ 2  0 -2 ]
//   [ 1  0 -1 ]

// 1. Configure image data (3x3 patch)
// Image: [[1,2,3], [4,5,6], [7,8,9]]
conv_write(32'h10, 32'h00030201);  // IMG row 0: pixels 1,2,3
conv_write(32'h14, 32'h00060504);  // IMG row 1: pixels 4,5,6
conv_write(32'h18, 32'h00090807);  // IMG row 2: pixels 7,8,9

// 2. Configure kernel (-1 in signed 8-bit = 0xFF, -2 = 0xFE)
conv_write(32'h20, 32'h00FF0001);  // KER row 0: [1, 0, -1]
conv_write(32'h24, 32'h00FE0002);  // KER row 1: [2, 0, -2]
conv_write(32'h28, 32'h00FF0001);  // KER row 2: [1, 0, -1]

// 3. Start convolution (enable + start)
conv_write(32'h00, 32'h00000003);

// 4. Wait for completion
do {
    conv_read(32'h04, status);
} while ((status & 0x02) == 0);

// 5. Read result
conv_read(32'h0C, result);  // Result = -8

// 6. Clear done status
conv_write(32'h04, 32'h00000002);
```

### Convolution with DMA Write
```verilog
// 1-2. Configure image and kernel (same as above)

// 3. Configure destination address
conv_write(32'h08, 32'h00002000);  // DST = 0x2000

// 4. Start with DMA enabled (enable + start + dma_en)
conv_write(32'h00, 32'h00000007);

// 5. Wait for completion
do {
    conv_read(32'h04, status);
} while ((status & 0x02) == 0);

// Result is automatically written to memory address 0x2000
```

## Common Kernels

### Identity Kernel
```
0 0 0     -> 0x00000000
0 1 0     -> 0x00000100
0 0 0     -> 0x00000000
```

### Box Filter (Average)
```
1 1 1     -> 0x00010101
1 1 1     -> 0x00010101
1 1 1     -> 0x00010101
```

### Sobel Horizontal
```
 1  0 -1   -> 0x00FF0001
 2  0 -2   -> 0x00FE0002
 1  0 -1   -> 0x00FF0001
```

### Sobel Vertical
```
 1  2  1   -> 0x00010201
 0  0  0   -> 0x00000000
-1 -2 -1   -> 0x00FFFEFF
```

### Laplacian (Edge Detection)
```
 0 -1  0   -> 0x0000FF00
-1  4 -1   -> 0x00FF04FF
 0 -1  0   -> 0x0000FF00
```

## Mathematical Formula

The convolution result is computed as:
```
result = Σ(i=0 to 8) image[i] × kernel[i]
```

Where:
- `image[i]` is an unsigned 8-bit pixel value (0-255)
- `kernel[i]` is a signed 8-bit weight (-128 to 127)
- Result is a signed 32-bit integer

## Testing

Run the testbench to verify functionality:

```bash
cd /path/to/project
iverilog -o tb_conv2d \
  -I rtl/e203/core \
  rtl/e203/perips/sirv_conv2d.v \
  tb/tb_conv2d.v
./tb_conv2d
```

The testbench performs:
1. Register read/write verification
2. Sobel horizontal edge detection kernel test
3. DMA write verification
4. Interrupt signal verification
5. Identity kernel test
6. Box filter (sum) test

## Integration

To integrate the convolution accelerator into the E203 SoC:

1. Instantiate `sirv_conv2d` in your subsystem
2. Connect configuration ICB interface to the peripheral bus
3. Connect DMA ICB interface to the memory bus
4. Route `conv_irq` signal to the PLIC (Platform-Level Interrupt Controller)

## Performance

- Single 3x3 convolution: ~3 clock cycles (without DMA)
- With DMA write: ~5 clock cycles (depends on memory latency)

## License

Copyright 2018-2020 Nuclei System Technology, Inc.

Licensed under the Apache License, Version 2.0.
