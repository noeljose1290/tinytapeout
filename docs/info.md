<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

The design is an 8N1 UART transmitter implemented as a finite state machine (FSM).

The system runs on a 10 MHz clock
Baud rate is 115200, generated using an internal clock divider (CLKS_PER_BIT ≈ 87)
Transmission is triggered by a rising edge on uio_in[0]
Operation flow:
Idle state
TX line (uo_out[0]) stays HIGH (UART idle)
busy = 0
Send trigger
On rising edge of uio_in[0], the input byte (ui_in[7:0]) is latched
Start bit
TX line goes LOW for 1 baud period
Data bits
8 bits are transmitted LSB first
Each bit lasts one baud period
Stop bit
TX line goes HIGH for 1 baud period
Completion
done signal (uo_out[2]) pulses for one clock cycle
busy goes LOW
Last transmitted byte is stored in uio_out

## How to test

🖥️ Basic functionality test (simulation)
Apply a byte to ui_in[7:0]
Generate a rising edge on uio_in[0]
Observe:
uo_out[1] (busy) goes HIGH during transmission
uo_out[0] (TX) outputs serial waveform:
start bit (0)
8 data bits (LSB first)
stop bit (1)
uo_out[2] (done) pulses at completion
🔌 Real hardware test (recommended)
Connect:
uo_out[0] → RX pin of USB-to-serial adapter
GND → GND
Open a terminal:
Baud rate: 115200
Data: 8 bits
No parity
1 stop bit (8N1)
Provide inputs:
Set ui_in to the byte you want to send
Pulse uio_in[0] HIGH → LOW
Result:
The transmitted byte appears in the terminal

## External hardware

USB-to-Serial adapter (e.g., FTDI, CP2102, CH340)
Serial terminal software:
minicom
PuTTY
screen

👉 No additional hardware is required beyond a basic USB serial interface.
