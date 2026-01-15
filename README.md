# aoc_fpga_2025

Solutions for days 3 and 9 targeting CMOD A7-35T FPGA, running at 12Mhz.

[Day 9](#day-9)

[Day 3](#day-3)

## Day 9

### Approach

This solves part 2 of day 9. For this puzzle we have to find the are of the largest rectangle contained inside the polygon with vertices given by the puzzle input, the rectangle has two of these vertices as opposite points.

We split this up into two main parts: <br>
(1) Calculate the areas of all the possible rectangles (search) <br>
(2) Check whether each rectangles (if larger than the current largest valid) is contained inside the polygon (verification) <br>

The puzzle input is around 500 lines long, needing at least 34 bits per vertex, so computing and then storing each possible area (34 bits per area) would require around 4.2Mb of data, far too much to be stored on our FPGA. So our approach needs to be careful with how much RAM it uses.

Using the block ram available on the chip, we can easily store all the vertices and edges of the polygon and use this to find our answer.

Our approach to use (1) and (2) is to do both simultaneously, with one part of the FPGA (searcher) computing all the possible areas as fast as it can read from BRAM, then passing rectangles with larger areas than the current max to the verifier, which tests whether each rectangle is contained inside the larger polygon.

With this approach, and sufficient parallelisation in our verifier we can theoretically compute the answer as fast as the searcher can calculate all the areas, which is around 10.4ms if we calculate 1 per cycle.

### Interior/Exterior logic

#### Winding Number:

This is the number of times the polygon boundary "wraps around" a point. If odd, the point is inside; if even, it's outside. We calculate this by counting how many polygon edges a ray from the point to infinity crosses, then taking the result mod 2.

Calculating this for every point in every rectangle we need to check would require significant amounts of computation: looking at the puzzle input, such rectangles are going to contain potentially millions of points.

By making a two assumptions about the puzzle input and the polygon it creates, we can simplify our logic significantly:<br>
(1) Our polygon doesn't contain any adjacent edges.<br>
(2) Every rectangle formed will have dimensions at least 3x3<br>

i.e. our logic will not work for this polygon (which is itself the largest rectangle it contains):

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

Looking at my puzzle input these assumptions do hold true and I can find the correct answer using this method, if these assumptions aren't true, then we could double all the dimensions, as this would result in an input for which these assumptions do hold, but we would still not treat the case in figure 1 correctly.

For any rectangle we're testing, we construct a smaller test rectangle by removing the outermost layer of points (hence assumption 2). We then check only the edges of this smaller rectangle (marked T below) and a single ray from x = 0 to a single point inside the rectangle (not passing through a vertex):

```
Fig 2
Original Rectangle    The rectangle we test
..............        ...............
.#xxxxxxxxxx#.        ..#..........#.
.x..........x.        ==>RTTTTTTTTT..
.x..........x.        ...T........T..
.x..........x. -->    ...TTTTTTTTTT..
.#xxxxxxxxxx#.        ..#..........#.
..............        ...............

x = edges of original test rectangle
# = vertices of original rectangle  
T = edges we check (perimeter of inner rectangle)
R = point where we cast ray from x=0
```

Then, any rectangle we're testing is invalid if any edge of the larger polygon intersects any perpendicular interior edge (i.e. a horizontal edge intersects a vertical edge), or the ray passes through an even number of edges.

#### Why testing interior edges is sufficient:

A rectangle is valid if and only if all its points lie inside the polygon. We first know that the two vertices defining the rectangle are inside the polygon. Testing the interior edges reduces us to two cases.

**Case 1) - No intersections** the winding number of all the points in the interior are the same, so they are either all contained inside the polygon, or outside the polygon. We then use the winding number of the ray to determine between the two.

**Case 2) - edges intersects interior** the winding number of the interior points will no longer be all the same, so the rectangle contains a point not contained by the polygon, so cannot be a valid solution.

Case 2 we can immediately disqualify, in case 1 we then use the calculated winding number of the ray from x=0 to determine whether the interior is contained or not, this reduces us to the case below:

```
Fig 3
I - Interior point
V - Vertex (also Interior)

..........
..V.......
...IIII...
...IIII...
.......V..
```
Now if any of the rectangles edges are exterior then there must be an edge intersecting the interior, but as no edges intersect the interior, all the edges and vertices of the rectangle are contained in the polygon, so the rectangle is valid.

**Note - Another reason why we don't test intersections with the rectangles edges rather than the interior:**

In fig 4 below, on the left there is a rectangle with points A, B which would falsely be flagged as invalid if we tested the rectangle edges, we could attempt to get around this by ignoring the start and end of polygon edges, but then the rectangle on the right would be falsely flagged as valid. Testing the interior edges instead solves this problem.

```
Fig 4
Rectangles constructed by vertices A, B
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

- There are 500 * 499 / 2 = ~125000 possible rectangles, 500 of which are edges (one of the dimensions is 1) and can be ignored.

- Our FPGA has dual port BRAM, so we could read 2 new vertices per cycle and check 2 rectangles per cycle on most cycles, this reduces our required number of cycles from ~125000 -> ~62000.

#### Verification logic:

- We are storing horizontal and vertical edges in separate arrays in BRAM, this means we can check 2 horizontal and 2 vertical edges per cycle, this means we can verify each rectangle in a maximum of ~125 cycles (assuming an even split between vertical and horizontal edges).

- We can verify multiple rectangles simultaneously using parallel verifiers. Each verifier maintains its own position in the edge list and cycle counter, allowing it to process rectangles independently without restarting from edge 0 each time.

- Using sufficient parallel verifiers and a cache of rectangles waiting to be verified we could theoretically reduce the runtime to just slightly larger than the number of cycles needed to search through the possible rectangles.

(We refer to the number of parallel verifiers by the variable `VERIFY_PARALLEL`).

### Results

We calculate how many cycles the search logic waited for empty cache slots to store results and call this "wait cycles".

Using `VERIFY_PARALLEL = 40` we correctly compute the answer in 5.87ms (70712 cycles), with 7205 wait cycles.

With `VERIFY_PARALLEL = 80` we reduce wait cycles down to only 45, and the number of cycles is as we would expect for our search method.

<img width="711" height="439" alt="image" src="https://github.com/user-attachments/assets/880d27d5-5ed5-4b89-b223-0efe0c995f79" />

On the CMOD-A7 we can fit VERIFY_PARALLEL = 32, resulting in a runtime of around 6.3ms using < 0.1W of power, looking at software solutions to this problem suggests that this is faster than most of the more optimal solutions which generally have runtimes of around 10-20ms and run on CPUs requiring significantly more power.

### How to run

#### Simulation

Use input.py to convert your input "input.txt" into output_x.bin and output_y.bin, the source should read these as the initial values for the vertex data.

Ensure you set NUM_PTS to be larger than the number of lines in your input file + 1.

The default values will work for the puzzle inputs.

Included is a testbench which will output the result as well as the total runtime for the module.

#### CMOD-A7

Included is a .xdc file with constraints for the CMOD-A7, setting VERIFY_PARALLEL = 32 the design should synthesise (tested) and run on the device.

This communicated the result over UART at 9_600 BAUD, even parity bit, 1 stop bit



## Day 3

### Approach

Day 3 can be solved by using a sliding window approach on each line of the input.

Example: We take The line ex = 3456157947 (10 digits long) and we are taking the 4 digit joltage.

**Example:** Consider the line `ex = 3456157947` (10 digits) where we want 4 digits of joltage.

- **Digit 1:** Find max in positions 0-6 (`3456157`|`947`) → max = `8` at index 3
- **Digit 2:** Find max in positions 4-7 (`3456`|`1579`|`47`), starting after the previous max → max = `9` at index 7  
- **Digit 3:** Find max in positions 8-8 (`34561579`|`4`|`7`)
- **Digit 4:** Final digit is at position 9 (`345615794`|`7`)

The window shrinks as we progress: for the nth digit, we ignore the last (4-n) positions to ensure we can still extract 4 total digits.

### Implementation

The module stores the input as a 100 digit long binary coded decimal. 

Combinational logic finds each digit sequentially.

To add to the sum there is also a binary coded decimal to binary module included, this converts the result from each line into a 64 bit value which we add to the current sum.

Once this has calculated for each line it then outputs the result as a 64 bit value (most significant byte first).

We can change the number of joltage digits we're looking for by changing the UART header.

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

