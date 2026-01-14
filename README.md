# aoc_fpga_2025

Solved days 3 and 9 targeting CMOD A7-35T FPGA, running at 12Mhz.

[Day 9](#day-9)

[Day 3](#day-3)

## Day 9

### Approach

This solves part 2 of day 9. For this puzzle we have to find the largest area contained inside the shape with vertices the points of the puzzle input.

We split this up into two main parts: <br>
(1) Calculate the areas of all the possible rectangles (search) <br>
(2) Check whether each rectangles (if larger than the current largest valid) is contained inside the shape (verification) <br>

The puzzle input is around 500 lines long, needing at least 34 bits per vertex, so computing and then storing each possible area (34 bits per area) would require around 4.2Mb of data, far too much to be stored on our FPGA. So our approach needs to be careful with how much RAM it uses.

Using the block ram available on the chip, we can easily store all the vertices and edges of the shape and use this to find our answer.

Our approach to use (1) and (2) is to do both simultaneously, with one part of the FPGA (searcher) computing all the possible areas as fast as it can read from BRAM, then passing rectangles with larger areas than the current max to the verifier, which tests whether each rectangle is contained inside the larger shape.

With this approach, and sufficient parallelisation in our verifier we can theoretically compute the answer as fast as the searcher can calculate all the areas, which is around 10.4ms if we calculate 1 per cycle.

### Interior/Exterior logic

Mathematically, we can calculate whether each point is contained within the larger shape by casting a ray from x = 0 to that point, adding up the number of edges it crosses and calculating that number mod 2. Doing this for every point in every rectangle we need to check would require significant amounts of computation: looking at the puzzle input, such rectangles are going to contain potentially millions of points.

By making a two assumptions about the puzzle input and the shape it creates, we can simplify our logic significantly:<br>
(1) Our shape doesn't contain any adjacent edges.
(2) Every rectangle formed will have dimensions at least 3x3

i.e. our logic will not work for this shape (which is itself the largest rectangle it contains):
```
Fig 1
..............
.#xxx##xxxxx#.
.x...xx.....x.
.x...##.....x.
.x..........x.
.#xxxxxxxxxx#.
..............
```

For any rectangle we're testing, we take the edges of the rectangle of interior (not on the edge or vertcices) points, and a single ray from x = 0 to a single point inside the rectangle (not passing through a vertex):

```
Fig 2
..............        ...............
.#xxxxxxxxxx#.        ..#..........#.
.x..........x.        =>RTTTTTTTTTT..
.x..........x.        ...T........T..
.x..........x. -->    ...TTTTTTTTTT..
.#xxxxxxxxxx#.        ..#..........#.
..............        ...............
```

Where T are the interior edges we're testing and R is the point we cast the ray to.

The rectangle we're testing is invalid if any edge of the larger shape intersects any perpendicular interior edge, or the ray passes through an even number of edges.

Why does this work?

Our rectangle is invalid if any of the points are not contained inside the larger shape, if a perpendicular edge intersects an interior edge, we assume that at least 1 point in the rectangle is invalid (which is false in fig 1 above). We test the interior edges rather than the exterior edges as this avoids us falsely disqualifying a rectangle which may have other points on the rectangle edges, but none inside the rectangle itself.

In fig 3 below, on the left there is a rectangle with points A, B which would falsely be flagged as invalid if we tested the rectangle edges, we could get around this by ignoring the start and ends of larger shape edges, but then the rectangle on the right would be falsely flagged as valid. Testing the interior edges instead solves this problem.

```
Fig 3
..............        ...............
....#xxx#.....        ..Axxx#..#xxx#.
....x...x.....        ..x...x..x...x.
.Axx#...#xxx#.        ..x...#xx#...x.
.x..........x.        ..x..........x.
.#xxxxxxxxxxB.        ..#xxxxxxxxxxB.
..............        ...............
```

### Optimisation

#### Search logic:

- We construct the horizontal edges and vertical edges at the start of our program, we can calculate an initial `max_area` from the longest of these to filter out initial smaller rectangles.

- There are 500 * 499 / 2 = ~125000 possible rectangles, 500 of which are edges and can be ignored.

- Our FPGA has dual port BRAM, so we could possibly check 2 rectangles per cycle on most cycles, this reduces our required number of cycles from ~125000 -> ~62000.

#### Verification logic:

- We are storing horizontal and vertical edges in separate arrays in BRAM, this means we can check 2 horizontal and 2 vertical edges per cycle, this means we can verify each rectangle in a maximum of ~125 cycles (assuming an even split between vertical and horizontal edges).

- We can parallelise this logic easily by verifying multiple rectangles at the same time, we don't need to start searching through edges at index 0, we simply store the cycle number at which each rectangle is done verifying.

- Using sufficient parallel verifiers and a cache of rectangles waiting to be verified we could theoretically reduce the runtime to just slightly larger than the number of cycles needed to search through the possible rectangles.

#### Results

We calculate how many cycles the search logic waited for empty cache slots to store results and call this "wait cycles".

Using `VERIFY_PARALLEL = 40` we correctly compute the answer in 5.87ms (70712 cycles), with 7205 wait cycles.

With `VERIFY_PARALLEL = 80` we reduce wait cycles down to only 45, and the number of cycles is as we would expect for our search method.

<img width="711" height="439" alt="image" src="https://github.com/user-attachments/assets/880d27d5-5ed5-4b89-b223-0efe0c995f79" />




## Day 3

### Approach

Day 3 can be solved by using a sliding window approach on each line of the input.

Example: We take The line ex = 3456157947 (10 digits long) and we are taking the 4 digit joltage.

Our 1st digit will take the value of the max digit in **3458157**947 (digits 0 -> 6 incl.).

This is equal to 8, with address 3.

So our 2nd digit will then take the value of the max digit in 3458**1579**47 (digits 4 -> 7 incl.).

and so on, where we only check digits after the previous max, and ignoring the last 4 - n digits (n starting at 1).

### Implementation

The module stores the input as a 100 digit long binary coded decimal. We then use combinational logic to find each digit one at a time, we can also change the number of joltage digits we're looking for by changing the UART header.

To add to the sum there is also a binary coded decimal to binary module included, this converts the result from each line into a 64 bit value which we add to the current sum.

Once this has calculated for each line it then outputs the result as a 64 bit value (most significant byte first).

With this approach we can implement a solution to day 3, as well as UART transmitter and receiver on the target FPGA using around 10.3% (2140) of the FPGA's LUTs.

### Results

With this implementation we can calculate the joltage from each line in `2 * (joltage_digits)` clock cycles on the FPGA, at 12MHz and 12 digits this is ~2.0 μs

The puzzle input from day 3 is 200 lines, 100 digits per line. So the total time for computation will be around ~66 μs for part 1 and ~400 μs for part 2.

Using the python file to send the data to the FPGA and output the result yields the correct answer for both part 1 and 2, with a runtime of around 3 seconds (mainly due to communication over UART).

### How to run

#### Testbench

Included is a testbench which should test the module on a 5 line 100 digit input, calculating 12 digits of joltage.

The module should output 64 bits of data = 0x0000040C6D0C4961 if running correctly

#### CMOD A7

To run this on a CMOD A7, the .xdc file is included and you can then either use the included python file which expects an "input.txt" file with the input data, or has the same data as in the testbench included.

The python file will also create a binary file when run which can be manually sent to the device using a terminal emulator.

The result will be output as a raw hex value (64 bits).

Serial settings to communicate are:<br>
38_400 baud,<br>
even parity bit,<br>
1 stop bit

