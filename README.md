# aoc_fpga_2025
Advent of code day 3 implemented using verilog.


## Introduction

This intends to implement a solution for day 3 of AOC2025 on a Digilient CMOD A7-35T FPGA, communicating over UART.

## Approach

Day 3 can be solved by using a sliding window approach on each line of the input.

Example: We take The line ex = 3456157947 (10 digits long) and we are taking the 4 digit joltage.

Our 1st digit will take the value of the max digit in **3458157**947 (digits 0 -> 6 incl.).

This is equal to 8, with address 3.

So our 2nd digit will then take the value of the max digit in 3458**1579**47 (digits 4 -> 7 incl.).

and so on, where we only check digits after the previous max, and ignoring the last 4 - n digits (n starting at 1).

## Implementation

The module stores the input as a 100 digit long binary coded decimal.

We then use combinational logic to find each digit one at a time, we can also easily change the number of joltage digits we're looking for by using variables `left_mask` and `right_mask`, to tell the combinational logic which sequence of digits to check for the max value.

To add to the sum there is also a binary coded decimal to binary module included, this converts the result from each line into a 64 bit value which we add to the current sum.

Once this has calculated for each line it then outputs the result as a 64 bit value (most significant byte first).

With this approach we can implement a solution to day 3, as well as UART transmitter and receiver on the target FPGA using around 10.3% (2140) of the FPGA's LUTs.

## UART Communication

The testbench communicates with the module using simulated UART communication, also included in this repository is a python file to communicate with the FPGA.

The device expects baud rate 38_400, even parity bit and 1 stop bit.

As the uart receiver module and main day3 module are separate, the device can receive 1 byte of input, and be halfway through receiving the next over UART while computing the previous line's value, this means we could theoretically communicate at baud rate `(12_000_000 / 30) = 400000`, at this clock frequency, assuming reliable communication over UART.

### UART Header

The device expects a 4 byte header to start the data, this allows the line length, number of lines and the number of digits to be varied within a preset range.

The Header is formatted as:

0xAA xxyyyz

xx -> line length in bytes (max 50 for 100 digits)<br>
yyy -> number of lines (max 4095)<br>
z -> number of joltage digits (max 15)<br>

As the device doesn't store previous lines, the max values for these parameters could easily be increased.

## Results

With this implementation we can calculate the joltage from each line in `2 * (joltage_digits)` clock cycles on the FPGA, at 12MHz and 12 digits this is ~2.0 μs

The user input from day 3 is 200 lines, 100 digits per line. So the total time for computation will be around ~66 μs for part 1 and ~400 μs for part 2.

Using the python file to send the data to the FPGA and output the result yields the correct answer for both part 1 and 2, with a runtime of around 3 seconds (mainly due to communication over UART), this runtime could be improved by increasing the baud rate.

## How to run

### Testbench

Included is a testbench which should test the module on a 5 line 100 digit input, calculating 12 digits of joltage.

The module should output 64 bits of data = 0x0000040C6D0C4961 if running correctly

### CMOD A7

To run this on a CMOD A7, the .xdc file is included and you can then either use the included python file which expects an "input.txt" file with the input data, or has the same data as in the testbench included.

The python file will also create a binary file when run which can be manually sent to the device using a terminal emulator.

The result will be output as a raw hex value (64 bits).

Serial settings to communicate are:<br>
38_400 baud,<br>
even parity bit,<br>
1 stop bit

