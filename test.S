.section .text

.globl   test_asm
.type    test_asm, @function

# Function: test_asm
# Parameter: a0 (x10) = pointer to output array (32-bit integers)
test_asm:
    #       Save the pointer to output array
    mv       x23, x10

    addi     x5,  x0,  5                        # 1
    addi     x6,  x0,  3                        # 2
    add      x7,  x5,  x6                       # 4
    sw       x7,       0(sp)                    # 5
    lw       x24,      0(sp)                    # 8    
    add      x9,  x24,  x5                      # 8
    sub      x22, x9,  x6                       # 9
    mul      x11, x22, x7                       # 26
    addi     x5,  x0,  8                        # 27
    add      x12, x11, x5                       # 28
    and      x13, x12, x9                       # 29
    or       x14, x13, x11                      # 30
    xor      x15, x14, x12                      # 31
    sll      x16, x15, x6                       # 32
    srl      x17, x16, x5                       # 33
    addi     x18, x17, -1                       # 34
    sw       x18,      4(sp)                    # 35
    lw       x19,      4(sp)                    # 38
    add      x20, x29, x14                      # 38
    mul      x21, x20, x17                      # 55


    #       Store all register values to the output array
    sw       x5,   0(x23) # results [0] = x1    # 56
    sw       x6,   4(x23) # results [1] = x2    # 59
    sw       x7,   8(x23) # results [2] = x3    # 60
    sw       x24, 12(x23) # results [3] = x4    # 61
    sw       x9,  16(x23) # results [4] = x5    # 62
    sw       x22, 20(x23) # results [5] = x6    # 63
    sw       x11, 24(x23) # results [6] = x7    # 64
    sw       x12, 28(x23) # results [7] = x8    # 65
    sw       x13, 32(x23) # results [8] = x9    # 66
    sw       x14, 36(x23) # results [9] = x10   # 67
    sw       x15, 40(x23) # results[10] = x11   # 68
    sw       x16, 44(x23) # results[11] = x12   # 69
    sw       x17, 48(x23) # results[12] = x13   # 70
    sw       x18, 52(x23) # results[13] = x14   # 71
    sw       x19, 56(x23) # results[14] = x15   # 72
    sw       x20, 60(x23) # results[15] = x16   # 73
    sw       x21, 64(x23) # results[16] = x17   # 74

    ret

.size    test_asm, .-test_asm


