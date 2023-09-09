**University of Pennsylvania, CIS 565: GPU Programming and Architecture,
Project 1 - Flocking**

* Gene Liu
  * [LinkedIn](https://www.linkedin.com/in/gene-l-3108641a3/)
* Tested on: Windows 10, i7-9750H @ 2.60GHz, 16GB RAM, GTX 1650 Max-Q 4096MB (personal laptop)
  * SM 7.5

### Screenshots/Gifs

![](images/5kboid.gif)

5k boids, 128 block size, 100 scene scale

![](images/50kboid.gif)

50k boids, 128 block size, 100 scene scale

![](images/500kboid.gif)

500k boids, 128 block size, 200 scene scale

### Performance Analysis

Performance analysis was done by comparing average FPS of each simulation. The following graphs show sim FPS as a result of varying boid count, with a constant block size of 128 and scene scale of 100, with data points at 5000, 10000, 50000, 100000, and 500000 boids for each scheme.

<img src="/images/fpsvsboidnumnv.jpg" alt="image" width="50%" height="auto">

<img src="/images/fpsvsboidnumv.jpg" alt="image" width="50%" height="auto">

Increasing the boid count decreased the FPS no matter the parllelization scheme, which is as expected. This is as an increased number of particles to track and update increases computation and hence reduces the frame rate. The coherent gridding performed the best, with uniform gridding and finally the naive parallelization following. This is also expected, as each method provides improvements upon the next.

The FPS compared to varying block sizes was also analyzed, with the same boid number of 50000, no visualization, and 100 scene scale. Data points were gathered at block sizes of 16, 32, 64, 128, 256, 512, and 1024.

<img src="/images/fpsvsblocksizenv.jpg" alt="image" width="50%" height="auto">

The results were once again as expected, with performance not gaining much after block size reaches 128. The three parallelization schemes showed varying performance levels in the expected order. Block size not improving performance can be explained as the warp size is constant at 32, limiting the degree of parallelization(the number of threads that can run at the same time), no matter the overall block size. At lower values at and around 32, the performance decrease can be attributed to not fully using parallelization and instead serialization operations.

### Questions

* For each implementation, how does changing the number of boids affect performance? Why do you think this is?

No matter the implementation, as the number of boids increased, the performance decreased. This makes sense as increasing the number of particles increases the computation needed to be done in updating velocities and checking neighbors, hence increasing the runtime of each loop and thus decreasing the frame rate. This computation eventually becomes the bottleneck and directly results in the decreased frame rate.

* For each implementation, how does changing the block count and block size affect performance? Why do you think this is?

Increasing the block size and count(keeping the total thread count constant) increases the performance of the simulation with diminishing returns. Increasing block size up to about 128 threads per block does drastically improve performance, likely due to fully utilizing the parallelization of the GPU. At lower block sizes, core cycles are wasted as there are not enough threads in the block to schedule at the same time or cover memory read latency. Once beyond 128 though, as the total number of threads performing computation stays the same and since we are fully utilizing the GPU cores and scheduling, and so not much performance is gained.

* For the coherent uniform grid: did you experience any performance improvements with the more coherent uniform grid? Was this the outcome you expected? Why or why not?

Yes, there was a visible performance improvement with the coherent unifrom grid compared to the uniform one. This is expected and due to the reduction of random memory accesses and increasing contiguous access, which is faster with regards to the GPU shared memory. This is relevant as all the data arrays live in GPU memory as they are arrays, and so contiguous memory access helps to reduce these memory read times. While the coherent uniform grid has an additional computation step in reordering/reshuffling the position and velocity arrays to match the sorted ones, this runtime is likely covered by the memory read improvements, resulting in overall faster sim performance.

* Did changing cell width and checking 27 vs 8 neighboring cells affect performance? Why or why not? Be careful: it is insufficient (and possibly incorrect) to say that 27-cell is slower simply because there are more cells to check!

Halving the cell width(to the same as the neighborhood distance) and checking 27 neighboring cells as a result actually improves performance compared to the original simulation. Although we do have to check more cells, each cell has half the side length and so 1/8 the area of a previous cell. Thus, the ratio of volume for the 27 cell check vs the 8 cell check is (27/8)/8 = 27/64, which means that these 27 cells constitute a lower volume than the previous 8 cells. On average, there are thus less boids in these checked cells(assuming a uniform boid distribution) and so the velocity update likely performs fewer loops, resulting in better performance.
